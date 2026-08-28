// Equivalence-only, pin-sensitive abstraction for the independently verified
// and synthesized processor core. This makes the ASIC wrapper a compositional
// proof partition; it is not a functional processor model.
module simt_core #(
  parameter int unsigned IMEM_WORDS = 64,
  parameter int unsigned IMEM_ADDR_W = $clog2(IMEM_WORDS),
  parameter bit USE_IHP_IMEM = 1'b0,
  parameter bit USE_IHP_DATA_SRAM = 1'b0,
  parameter int unsigned BARRIER_TIMEOUT_CYCLES = 256,
  parameter bit ENABLE_FAULT_INJECTION = 1'b0
) (
  input logic clk, rst, clear_i, prog_valid_i,
  input logic [IMEM_ADDR_W-1:0] prog_addr_i,
  input logic [31:0] prog_data_i,
  input logic launch_valid_i,
  output logic launch_ready_o,
  input logic [31:0] launch_pc_i,
  input logic [2:0] launch_warp_count_i,
  input logic fetch_response_ready_i, execute_completion_ready_i, commit_ready_i,
  output logic running_o, done_o, fault_o,
  output logic [31:0] fault_pc_o,
  output simt_gpu_pkg::fault_code_t fault_code_o,
  output logic commit_valid_o,
  output simt_gpu_pkg::completion_record_t commit_o,
  output logic [63:0] cycle_count_o, issue_count_o, commit_count_o,
  input logic watchdog_enable_i,input logic[31:0]watchdog_limit_i,
  input logic host_mem_valid_i,host_mem_shared_i,host_mem_write_i,
  input logic[31:0]host_mem_address_i,host_mem_write_data_i,
  output logic host_mem_ready_o,host_mem_response_valid_o,host_mem_response_fault_o,
  output logic[31:0]host_mem_read_data_o,input logic[4:0]inject_fault_i,
  output logic[simt_gpu_pkg::WARPS-1:0][31:0]debug_warp_pc_o,
  output simt_gpu_pkg::lane_mask_t debug_active_mask_o[simt_gpu_pkg::WARPS],
  output logic[simt_gpu_pkg::WARPS-1:0][simt_gpu_pkg::REGS_PER_THREAD-1:0]debug_gpr_pending_o,
  output logic[simt_gpu_pkg::WARPS-1:0][simt_gpu_pkg::PREDS_PER_THREAD-1:0]debug_pred_pending_o,
  output logic[simt_gpu_pkg::WARPS-1:0][3:0]debug_stack_depth_o,
  output logic[simt_gpu_pkg::WARPS-1:0][31:0]debug_stack_top_o,
  output logic[simt_gpu_pkg::WARPS-1:0]debug_resident_o,debug_barrier_wait_o,debug_memory_busy_o,
  output logic[2:0]debug_tracker_occupancy_o,
  output logic[simt_gpu_pkg::MAX_MEMORY_OPS-1:0][7:0]debug_tracker_summary_o,
  output logic[1:0]debug_memory_completion_occupancy_o,
  output logic[1:0]debug_alu_occupancy_o,debug_mul_occupancy_o,debug_wb_occupancy_o,
  output logic[simt_gpu_pkg::KERNEL_EPOCH_WIDTH-1:0]debug_epoch_o,
  output logic debug_quiescent_o
);
  logic pin_mix;
  always_comb begin
    pin_mix = clk ^ rst ^ clear_i ^ prog_valid_i ^ (^prog_addr_i) ^
      (^prog_data_i) ^ launch_valid_i ^ (^launch_pc_i) ^
      (^launch_warp_count_i) ^ fetch_response_ready_i ^
      execute_completion_ready_i ^ commit_ready_i ^ USE_IHP_IMEM ^
      USE_IHP_DATA_SRAM ^ (IMEM_WORDS == 0) ^ (BARRIER_TIMEOUT_CYCLES == 0)^
      ENABLE_FAULT_INJECTION^watchdog_enable_i^(^watchdog_limit_i)^host_mem_valid_i^
      host_mem_shared_i^host_mem_write_i^(^host_mem_address_i)^(^host_mem_write_data_i)^
      (^inject_fault_i);
    launch_ready_o = !rst && !pin_mix;
    running_o = pin_mix;
    done_o = clear_i && pin_mix;
    fault_o = rst && pin_mix;
    fault_pc_o = launch_pc_i ^ prog_data_i;
    fault_code_o = simt_gpu_pkg::fault_code_t'(prog_data_i[3:0]);
    commit_valid_o = commit_ready_i && pin_mix;
    commit_o = '0;
    commit_o.valid = commit_valid_o;
    commit_o.pc = launch_pc_i;
    commit_o.instruction = prog_data_i;
    cycle_count_o = {32'(IMEM_WORDS), launch_pc_i};
    issue_count_o = {32'(BARRIER_TIMEOUT_CYCLES), prog_data_i};
    commit_count_o = {61'b0, launch_warp_count_i};
    host_mem_ready_o=!rst;host_mem_response_valid_o=host_mem_valid_i;
    host_mem_response_fault_o=host_mem_address_i[1:0]!=0;
    host_mem_read_data_o=host_mem_address_i^host_mem_write_data_i;
    debug_warp_pc_o={simt_gpu_pkg::WARPS{launch_pc_i}};
    for(int w=0;w<simt_gpu_pkg::WARPS;w++)debug_active_mask_o[w]={simt_gpu_pkg::LANES{pin_mix}};
    debug_gpr_pending_o={simt_gpu_pkg::WARPS{prog_data_i[simt_gpu_pkg::REGS_PER_THREAD-1:0]}};
    debug_pred_pending_o='0;debug_stack_depth_o='0;debug_stack_top_o='0;
    debug_resident_o={simt_gpu_pkg::WARPS{running_o}};
    debug_barrier_wait_o='0;debug_memory_busy_o='0;debug_tracker_occupancy_o='0;
    debug_tracker_summary_o='0;debug_memory_completion_occupancy_o='0;
    debug_alu_occupancy_o='0;debug_mul_occupancy_o='0;debug_wb_occupancy_o='0;
    debug_epoch_o=launch_pc_i[simt_gpu_pkg::KERNEL_EPOCH_WIDTH-1:0];debug_quiescent_o=!running_o;
  end
endmodule
