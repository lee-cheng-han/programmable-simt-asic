`timescale 1ns/1ps
module tb_simt_core_uvm;
  import uvm_pkg::*;
  import simt_gpu_pkg::*;
  import simt_core_uvm_pkg::*;

  logic clk;
  initial clk=0;
  always #5 clk=~clk;
  simt_core_if core_if(clk);

  simt_core dut(
    .clk(clk),.rst(core_if.rst),.clear_i(core_if.clear),
    .prog_valid_i(core_if.prog_valid),.prog_addr_i(core_if.prog_addr),
    .prog_data_i(core_if.prog_data),.launch_valid_i(core_if.launch_valid),
    .launch_ready_o(core_if.launch_ready),.launch_pc_i(core_if.launch_pc),
    .launch_warp_count_i(core_if.launch_warp_count),.running_o(core_if.running),
    .execute_completion_ready_i(core_if.execute_completion_ready),
    .commit_ready_i(core_if.commit_ready),
    .done_o(core_if.done),.fault_o(core_if.fault),.fault_pc_o(core_if.fault_pc),
    .fault_code_o(core_if.fault_code),.commit_valid_o(core_if.commit_valid),
    .commit_o(core_if.commit),.cycle_count_o(core_if.cycle_count),
    .issue_count_o(core_if.issue_count),.commit_count_o(core_if.commit_count));

  initial begin
    core_if.rst=1; core_if.clear=0; core_if.prog_valid=0;
    core_if.launch_valid=0; core_if.prog_addr=0; core_if.prog_data=0;
    core_if.launch_pc=0; core_if.launch_warp_count=0;
    core_if.execute_completion_ready=1; core_if.commit_ready=1;
    repeat(2)@(posedge clk); @(negedge clk); core_if.rst=0;
  end

  initial begin
    uvm_config_db#(virtual simt_core_if)::set(null,"*","vif",core_if);
    run_test();
  end

  initial begin
    #20000;
    $fatal(1,"UVM testbench watchdog expired");
  end
endmodule
