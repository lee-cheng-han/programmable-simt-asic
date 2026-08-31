`timescale 1ns/1ps
/* verilator lint_off PINCONNECTEMPTY */
module tb_xsim_core_scaling;
  import simt_gpu_pkg::*;

  logic clk=0,rst=1,clear=0,prog_valid=0,launch_valid=0;
  logic[5:0]prog_addr=0;
  logic[31:0]prog_data=0,launch_pc=0,fault_pc;
  logic[2:0]launch_warp_count=0;
  logic launch_ready,running,done,fault,commit_valid;
  fault_code_t fault_code;
  completion_record_t commit;
  logic[63:0]cycle_count,issue_count,commit_count;
  int unsigned test_case,warps,words,commits;

  always #5 clk=~clk;
  always @(posedge clk)
    if($test$plusargs("VERBOSE"))
      $display("TICK time=%0t rst=%0b launch=%0b ready=%0b running=%0b issue=%0d commit=%0d done=%0b",
               $time,rst,launch_valid,launch_ready,running,
               issue_count,commit_count,done);
  simt_core dut(
    .clk(clk),.rst(rst),.clear_i(clear),.prog_valid_i(prog_valid),
    .prog_addr_i(prog_addr),.prog_data_i(prog_data),
    .launch_valid_i(launch_valid),.launch_ready_o(launch_ready),
    .launch_pc_i(launch_pc),.launch_warp_count_i(launch_warp_count),
    .fetch_response_ready_i(1'b1),
    .execute_completion_ready_i(1'b1),.commit_ready_i(1'b1),
    .running_o(running),.done_o(done),.fault_o(fault),
    .fault_pc_o(fault_pc),.fault_code_o(fault_code),
    .commit_valid_o(commit_valid),.commit_o(commit),
    .cycle_count_o(cycle_count),.issue_count_o(issue_count),
    .commit_count_o(commit_count),.diagnostic_count_o(),.counter_saturated_o(),.watchdog_enable_i(1'b1),.watchdog_limit_i(32'd256),
    .host_mem_valid_i(1'b0),.host_mem_shared_i(1'b0),.host_mem_write_i(1'b0),
    .host_mem_address_i('0),.host_mem_write_data_i('0),.inject_fault_i('0),.host_mem_ready_o(),.host_mem_response_valid_o(),.host_mem_response_fault_o(),
    .host_mem_read_data_o(),.debug_warp_pc_o(),.debug_active_mask_o(),
    .debug_gpr_pending_o(),.debug_pred_pending_o(),.debug_stack_depth_o(),
    .debug_resident_o(),.debug_barrier_wait_o(),.debug_memory_busy_o(),
    .debug_tracker_occupancy_o(),.debug_alu_occupancy_o(),.debug_mul_occupancy_o(),
    .debug_wb_occupancy_o(),.debug_epoch_o(),.debug_quiescent_o(),
    .debug_stack_top_o(),.debug_tracker_summary_o(),.debug_memory_completion_occupancy_o());

  task automatic write_word(input int unsigned address,input logic[31:0]data);
    @(negedge clk);prog_addr=6'(address);prog_data=data;prog_valid=1;
    @(negedge clk);prog_valid=0;
  endtask

  initial begin
    if(!$value$plusargs("CASE=%d",test_case))test_case=0;
    if(!$value$plusargs("WARPS=%d",warps))warps=1;
    if(warps<1||warps>WARPS)$fatal(1,"invalid warp count");
    repeat(2)@(posedge clk);@(negedge clk);rst=0;
    case(test_case)
      0:begin write_word(0,32'h78000000);words=1;end
      1:begin write_word(0,32'h38040007);write_word(1,32'h78000000);words=2;end
      2:begin write_word(0,32'h74040001);write_word(1,32'h78000000);words=2;end
      3:begin
        write_word(0,32'h38040007);write_word(1,32'h38080003);
        write_word(2,32'h040c4800);write_word(3,32'h78000000);words=4;
      end
      4:begin
        write_word(0,32'h38040007);write_word(1,32'h38080003);
        write_word(2,32'h0c0c4800);write_word(3,32'h78000000);words=4;
      end
      default:$fatal(1,"invalid diagnostic case");
    endcase
    @(negedge clk);launch_warp_count=3'(warps);#1;
    if(!launch_ready)$fatal(1,"launch not ready");
    launch_valid=1;@(negedge clk);launch_valid=0;
    repeat(200)begin
      @(negedge clk);#1;
      if(commit_valid)commits++;
      if(fault)$fatal(1,"fault code=%0d pc=%0d",fault_code,fault_pc);
      if(done)begin
        if(issue_count!=64'(words*warps)||commit_count!=64'(words*warps))
          $fatal(1,"counter mismatch issue=%0d commit=%0d",issue_count,commit_count);
        $display("PASS xsim scaling case=%0d warps=%0d cycles=%0d commits=%0d",
                 test_case,warps,cycle_count,commits);
        $finish;
      end
    end
    $fatal(1,"simulation-cycle timeout case=%0d warps=%0d",test_case,warps);
  end
endmodule
