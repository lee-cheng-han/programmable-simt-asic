module simt_asic_top #(
  parameter int unsigned IMEM_WORDS = 64,
  parameter int unsigned IMEM_ADDR_W = $clog2(IMEM_WORDS),
  parameter bit USE_IHP_IMEM = 1'b1,
  parameter bit USE_IHP_DATA_SRAM = 1'b1
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
  output logic running_o, done_o, fault_o
);
  import simt_gpu_pkg::*;
  logic reset_sync, core_reset, clear, launch_valid, launch_ready, prog_valid;
  logic [31:0] launch_pc, prog_data, fault_pc;
  logic [2:0] launch_warp_count;
  logic [IMEM_ADDR_W-1:0] prog_addr;
  fault_code_t fault_code;
  logic [63:0] cycle_count, issue_count, commit_count;

  reset_synchronizer reset_u(
    .clk_i(clk_i), .async_reset_i(!reset_n_i), .reset_o(reset_sync));
  assign core_reset = reset_sync || test_mode_i;
  // Scan insertion stitches this preserved boundary anchor into the generated
  // chain. RTL simulation intentionally models the pre-insertion bypass.
  assign scan_out_o = scan_enable_i ? scan_in_i : 1'b0;

  asic_host_controller #(.IMEM_ADDR_W(IMEM_ADDR_W)) host_u(
    .clk_i, .reset_i(core_reset), .test_mode_i,
    .wb_cyc_i, .wb_stb_i, .wb_we_i, .wb_adr_i, .wb_dat_i, .wb_sel_i,
    .wb_ack_o, .wb_err_o, .wb_dat_o, .clear_o(clear),
    .launch_valid_o(launch_valid), .launch_ready_i(launch_ready),
    .launch_pc_o(launch_pc), .launch_warp_count_o(launch_warp_count),
    .prog_valid_o(prog_valid), .prog_addr_o(prog_addr), .prog_data_o(prog_data),
    .running_i(running_o), .done_i(done_o), .fault_i(fault_o),
    .fault_pc_i(fault_pc), .fault_code_i(fault_code),
    .cycle_count_i(cycle_count), .issue_count_i(issue_count),
    .commit_count_i(commit_count));

  /* verilator lint_off PINCONNECTEMPTY */
  simt_core #(.IMEM_WORDS(IMEM_WORDS), .IMEM_ADDR_W(IMEM_ADDR_W),
    .USE_IHP_IMEM(USE_IHP_IMEM), .USE_IHP_DATA_SRAM(USE_IHP_DATA_SRAM)) core_u(
    .clk(clk_i), .rst(core_reset), .clear_i(clear),
    .prog_valid_i(prog_valid), .prog_addr_i(prog_addr), .prog_data_i(prog_data),
    .launch_valid_i(launch_valid), .launch_ready_o(launch_ready),
    .launch_pc_i(launch_pc), .launch_warp_count_i(launch_warp_count),
    .fetch_response_ready_i(1'b1), .execute_completion_ready_i(1'b1),
    .commit_ready_i(1'b1), .running_o, .done_o, .fault_o,
    .fault_pc_o(fault_pc), .fault_code_o(fault_code),
    .commit_valid_o(), .commit_o(),
    .cycle_count_o(cycle_count), .issue_count_o(issue_count),
    .commit_count_o(commit_count));
  /* verilator lint_on PINCONNECTEMPTY */
endmodule
