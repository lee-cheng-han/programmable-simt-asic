`timescale 1ns/1ps
/* verilator lint_off PINCONNECTEMPTY */
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
    .fetch_response_ready_i(core_if.fetch_response_ready),
    .execute_completion_ready_i(core_if.execute_completion_ready),
    .commit_ready_i(core_if.commit_ready),
    .done_o(core_if.done),.fault_o(core_if.fault),.fault_pc_o(core_if.fault_pc),
    .fault_code_o(core_if.fault_code),.commit_valid_o(core_if.commit_valid),
    .commit_o(core_if.commit),.cycle_count_o(core_if.cycle_count),
    .issue_count_o(core_if.issue_count),.commit_count_o(core_if.commit_count),
    .watchdog_enable_i(1'b1),.watchdog_limit_i(32'd256),.host_mem_valid_i(1'b0),
    .host_mem_shared_i(1'b0),.host_mem_write_i(1'b0),.host_mem_address_i('0),
    .host_mem_write_data_i('0),.inject_fault_i('0),.host_mem_ready_o(),.host_mem_response_valid_o(),.host_mem_response_fault_o(),
    .host_mem_read_data_o(),.debug_warp_pc_o(),.debug_active_mask_o(),
    .debug_gpr_pending_o(),.debug_pred_pending_o(),.debug_stack_depth_o(),
    .debug_resident_o(),.debug_barrier_wait_o(),.debug_memory_busy_o(),
    .debug_tracker_occupancy_o(),.debug_alu_occupancy_o(),.debug_mul_occupancy_o(),
    .debug_wb_occupancy_o(),.debug_epoch_o(),.debug_quiescent_o(),
    .debug_stack_top_o(),.debug_tracker_summary_o(),.debug_memory_completion_occupancy_o());

  initial begin
    core_if.rst=1; core_if.clear=0; core_if.prog_valid=0;
    core_if.launch_valid=0; core_if.prog_addr=0; core_if.prog_data=0;
    core_if.launch_pc=0; core_if.launch_warp_count=0;
    core_if.fetch_response_ready=1;
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
