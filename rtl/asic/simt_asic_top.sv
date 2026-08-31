module simt_asic_top #(
  parameter int unsigned IMEM_WORDS = 64,
  parameter int unsigned IMEM_ADDR_W = $clog2(IMEM_WORDS),
  parameter bit USE_IHP_IMEM = 1'b1,
  parameter bit USE_IHP_DATA_SRAM = 1'b1,
  parameter bit ENABLE_FAULT_INJECTION = 1'b0
) (
  input logic clk_i, reset_n_i,
  input logic wb_cyc_i, wb_stb_i, wb_we_i,
  input logic [7:0] wb_adr_i,
  input logic [31:0] wb_dat_i,
  input logic [3:0] wb_sel_i,
  output logic wb_ack_o, wb_err_o,
  output logic [31:0] wb_dat_o,
  input logic test_mode_i, scan_enable_i, scan_in_i,
  output logic scan_out_o,
  input logic bist_start_i,output logic bist_active_o,bist_done_o,bist_fail_o,
  output logic bist_fail_shared_o,output logic[31:0]bist_fail_address_o,
  output logic running_o, done_o, fault_o
);
  import simt_gpu_pkg::*;
  logic reset_sync, core_reset, clear, launch_valid, launch_ready, prog_valid,test_mode_q,test_entry;
  logic [31:0] launch_pc, prog_data, fault_pc;
  logic [2:0] launch_warp_count;
  logic [IMEM_ADDR_W-1:0] prog_addr;
  fault_code_t fault_code;
  logic [63:0] cycle_count, issue_count, commit_count;
  logic [7:0][31:0] diagnostic_count;
  logic counter_saturated;
  logic quiescent,watchdog_enable,host_mem_valid,host_mem_shared,host_mem_write;
  logic host_mem_ready,host_mem_response_valid,host_mem_response_fault;
  logic bist_mem_valid,bist_mem_shared,bist_mem_write;
  logic[31:0]bist_mem_address,bist_mem_write_data;
  logic core_mem_valid,core_mem_shared,core_mem_write;
  logic[31:0]core_mem_address,core_mem_write_data;
  logic[31:0]watchdog_limit,host_mem_address,host_mem_write_data,host_mem_read_data;
  logic[4:0]inject_fault;
  logic[WARPS-1:0][31:0]debug_warp_pc;
  lane_mask_t debug_active_mask[WARPS];
  logic[WARPS-1:0][REGS_PER_THREAD-1:0]debug_gpr_pending;
  logic[WARPS-1:0][PREDS_PER_THREAD-1:0]debug_pred_pending;
  logic[WARPS-1:0][3:0]debug_stack_depth;
  logic[WARPS-1:0][31:0]debug_stack_top;
  logic[WARPS-1:0]debug_resident,debug_barrier_wait,debug_memory_busy;
  logic[2:0]debug_tracker_occupancy;logic[1:0]debug_alu_occupancy,debug_mul_occupancy,debug_wb_occupancy;
  logic[MAX_MEMORY_OPS-1:0][7:0]debug_tracker_summary;logic[1:0]debug_memory_completion_occupancy;
  logic[KERNEL_EPOCH_WIDTH-1:0]debug_epoch;

  reset_synchronizer reset_u(
    .clk_i(clk_i), .async_reset_i(!reset_n_i), .reset_o(reset_sync));
  assign core_reset = reset_sync;
  assign test_entry=test_mode_i&&!test_mode_q;
  always_ff @(posedge clk_i)
    if(reset_sync)test_mode_q<=1'b0;else test_mode_q<=test_mode_i;
  // Scan insertion stitches this preserved boundary anchor into the generated
  // chain. RTL simulation intentionally models the pre-insertion bypass.
  assign scan_out_o = scan_enable_i ? scan_in_i : 1'b0;

  asic_host_controller #(.IMEM_ADDR_W(IMEM_ADDR_W),
    .ENABLE_FAULT_INJECTION(ENABLE_FAULT_INJECTION)) host_u(
    .clk_i, .reset_i(core_reset), .test_mode_i,
    .wb_cyc_i, .wb_stb_i, .wb_we_i, .wb_adr_i, .wb_dat_i, .wb_sel_i,
    .wb_ack_o, .wb_err_o, .wb_dat_o, .clear_o(clear),
    .launch_valid_o(launch_valid), .launch_ready_i(launch_ready),
    .launch_pc_o(launch_pc), .launch_warp_count_o(launch_warp_count),
    .prog_valid_o(prog_valid), .prog_addr_o(prog_addr), .prog_data_o(prog_data),
    .running_i(running_o), .done_i(done_o), .fault_i(fault_o),
    .fault_pc_i(fault_pc), .fault_code_i(fault_code),
    .cycle_count_i(cycle_count), .issue_count_i(issue_count),
    .commit_count_i(commit_count),.quiescent_i(quiescent),.epoch_i(debug_epoch),
    .diagnostic_count_i(diagnostic_count),.counter_saturated_i(counter_saturated),
    .debug_warp_pc_i(debug_warp_pc),.debug_active_mask_i(debug_active_mask),
    .debug_gpr_pending_i(debug_gpr_pending),.debug_pred_pending_i(debug_pred_pending),
    .debug_stack_depth_i(debug_stack_depth),.debug_resident_i(debug_resident),
    .debug_stack_top_i(debug_stack_top),.debug_tracker_summary_i(debug_tracker_summary),
    .debug_memory_completion_occupancy_i(debug_memory_completion_occupancy),
    .debug_barrier_wait_i(debug_barrier_wait),.debug_memory_busy_i(debug_memory_busy),
    .debug_tracker_occupancy_i(debug_tracker_occupancy),.debug_alu_occupancy_i(debug_alu_occupancy),
    .debug_mul_occupancy_i(debug_mul_occupancy),.debug_wb_occupancy_i(debug_wb_occupancy),
    .watchdog_enable_o(watchdog_enable),.watchdog_limit_o(watchdog_limit),
    .host_mem_valid_o(host_mem_valid),.host_mem_shared_o(host_mem_shared),
    .host_mem_write_o(host_mem_write),.host_mem_address_o(host_mem_address),
    .host_mem_write_data_o(host_mem_write_data),.host_mem_ready_i(host_mem_ready),
    .host_mem_response_valid_i(host_mem_response_valid),
    .host_mem_response_fault_i(host_mem_response_fault),.host_mem_read_data_i(host_mem_read_data),
    .inject_fault_o(inject_fault),.bist_done_i(bist_done_o));

  sram_bist_controller bist_u(.clk_i,.reset_i(reset_sync),.test_mode_i,.start_i(bist_start_i),
    .active_o(bist_active_o),.done_o(bist_done_o),.fail_o(bist_fail_o),
    .fail_shared_o(bist_fail_shared_o),.fail_address_o(bist_fail_address_o),
    .host_valid_o(bist_mem_valid),.host_shared_o(bist_mem_shared),.host_write_o(bist_mem_write),
    .host_address_o(bist_mem_address),.host_write_data_o(bist_mem_write_data),
    .host_ready_i(host_mem_ready),.host_response_valid_i(host_mem_response_valid),
    .host_response_fault_i(host_mem_response_fault),.host_read_data_i(host_mem_read_data));
  assign core_mem_valid=test_mode_i?bist_mem_valid:host_mem_valid;
  assign core_mem_shared=test_mode_i?bist_mem_shared:host_mem_shared;
  assign core_mem_write=test_mode_i?bist_mem_write:host_mem_write;
  assign core_mem_address=test_mode_i?bist_mem_address:host_mem_address;
  assign core_mem_write_data=test_mode_i?bist_mem_write_data:host_mem_write_data;

  /* verilator lint_off PINCONNECTEMPTY */
  simt_core #(.IMEM_WORDS(IMEM_WORDS), .IMEM_ADDR_W(IMEM_ADDR_W),
    .USE_IHP_IMEM(USE_IHP_IMEM), .USE_IHP_DATA_SRAM(USE_IHP_DATA_SRAM),
    .ENABLE_FAULT_INJECTION(ENABLE_FAULT_INJECTION)) core_u(
    .clk(clk_i), .rst(core_reset), .clear_i(clear||test_entry),
    .prog_valid_i(prog_valid), .prog_addr_i(prog_addr), .prog_data_i(prog_data),
    .launch_valid_i(launch_valid), .launch_ready_o(launch_ready),
    .launch_pc_i(launch_pc), .launch_warp_count_i(launch_warp_count),
    .fetch_response_ready_i(1'b1), .execute_completion_ready_i(1'b1),
    .commit_ready_i(1'b1), .running_o, .done_o, .fault_o,
    .fault_pc_o(fault_pc), .fault_code_o(fault_code),
    .commit_valid_o(), .commit_o(),
    .cycle_count_o(cycle_count), .issue_count_o(issue_count),
    .commit_count_o(commit_count),.watchdog_enable_i(watchdog_enable),
    .diagnostic_count_o(diagnostic_count),.counter_saturated_o(counter_saturated),
    .watchdog_limit_i(watchdog_limit),.host_mem_valid_i(core_mem_valid),
    .host_mem_shared_i(core_mem_shared),.host_mem_write_i(core_mem_write),
    .host_mem_address_i(core_mem_address),.host_mem_write_data_i(core_mem_write_data),
    .host_mem_ready_o(host_mem_ready),.host_mem_response_valid_o(host_mem_response_valid),
    .host_mem_response_fault_o(host_mem_response_fault),.host_mem_read_data_o(host_mem_read_data),
    .inject_fault_i(ENABLE_FAULT_INJECTION?inject_fault:'0),.debug_warp_pc_o(debug_warp_pc),
    .debug_active_mask_o(debug_active_mask),.debug_gpr_pending_o(debug_gpr_pending),
    .debug_pred_pending_o(debug_pred_pending),.debug_stack_depth_o(debug_stack_depth),
    .debug_stack_top_o(debug_stack_top),
    .debug_resident_o(debug_resident),.debug_barrier_wait_o(debug_barrier_wait),
    .debug_memory_busy_o(debug_memory_busy),.debug_tracker_occupancy_o(debug_tracker_occupancy),
    .debug_tracker_summary_o(debug_tracker_summary),
    .debug_memory_completion_occupancy_o(debug_memory_completion_occupancy),
    .debug_alu_occupancy_o(debug_alu_occupancy),.debug_mul_occupancy_o(debug_mul_occupancy),
    .debug_wb_occupancy_o(debug_wb_occupancy),.debug_epoch_o(debug_epoch),
    .debug_quiescent_o(quiescent));
  /* verilator lint_on PINCONNECTEMPTY */
endmodule
