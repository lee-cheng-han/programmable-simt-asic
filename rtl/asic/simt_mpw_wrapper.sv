// Shuttle-facing digital-macro wrapper. Physical power pins are supplied by UPF
// and the final harness integration; the functional boundary remains Wishbone.
module simt_mpw_wrapper #(
  parameter bit USE_IHP_IMEM=1'b1,parameter bit USE_IHP_DATA_SRAM=1'b1
) (
  input logic user_clock_i,user_reset_n_i,
  input logic wbs_cyc_i,wbs_stb_i,wbs_we_i,input logic[7:0]wbs_adr_i,
  input logic[31:0]wbs_dat_i,input logic[3:0]wbs_sel_i,
  output logic wbs_ack_o,wbs_err_o,output logic[31:0]wbs_dat_o,
  input logic test_mode_i,scan_enable_i,scan_in_i,bist_start_i,
  output logic scan_out_o,bist_active_o,bist_done_o,bist_fail_o,
  output logic bist_fail_shared_o,output logic[31:0]bist_fail_address_o,
  output logic irq_done_o,irq_fault_o
);
  /* verilator lint_off UNUSEDSIGNAL */logic running;/* verilator lint_on UNUSEDSIGNAL */
  logic done,fault;
  simt_asic_top #(.USE_IHP_IMEM(USE_IHP_IMEM),.USE_IHP_DATA_SRAM(USE_IHP_DATA_SRAM))core_macro_u(
    .clk_i(user_clock_i),.reset_n_i(user_reset_n_i),
    .wb_cyc_i(wbs_cyc_i),.wb_stb_i(wbs_stb_i),.wb_we_i(wbs_we_i),
    .wb_adr_i(wbs_adr_i),.wb_dat_i(wbs_dat_i),.wb_sel_i(wbs_sel_i),
    .wb_ack_o(wbs_ack_o),.wb_err_o(wbs_err_o),.wb_dat_o(wbs_dat_o),
    .test_mode_i,.scan_enable_i,.scan_in_i,.scan_out_o,.bist_start_i,
    .bist_active_o,.bist_done_o,.bist_fail_o,.bist_fail_shared_o,
    .bist_fail_address_o,.running_o(running),.done_o(done),.fault_o(fault));
  assign irq_done_o=done;
  assign irq_fault_o=fault;
`ifndef SYNTHESIS
  assert property(@(posedge user_clock_i)test_mode_i|->!wbs_ack_o);
  assert property(@(posedge user_clock_i)bist_active_o|->test_mode_i);
`endif
endmodule
