/* verilator lint_off PINCONNECTEMPTY */
module tb_single_warp_lifecycle;
  import simt_gpu_pkg::*;
  logic clk=0,rst,clear,prog_valid,launch_valid;
  logic [5:0] prog_addr; logic [31:0] prog_data,launch_pc,fault_pc;
  logic launch_ready,running,done,fault,commit_valid;
  logic [2:0] launch_warp_count;
  /* verilator lint_off UNUSEDSIGNAL */
  logic [63:0] cycle_count,issue_count,commit_count;
  /* verilator lint_on UNUSEDSIGNAL */
  fault_code_t fault_code; completion_record_t commit;
  int unsigned commits, mul_commits;
  always #5 clk<=~clk;
  simt_core dut(.clk(clk),.rst(rst),.clear_i(clear),.*,
    .prog_valid_i(prog_valid),.prog_addr_i(prog_addr),.prog_data_i(prog_data),
    .launch_valid_i(launch_valid),.launch_ready_o(launch_ready),
    .launch_pc_i(launch_pc),.running_o(running),.done_o(done),.fault_o(fault),
    .launch_warp_count_i(launch_warp_count),
    .fetch_response_ready_i(1'b1),
    .execute_completion_ready_i(1'b1),.commit_ready_i(1'b1),
    .fault_pc_o(fault_pc),.fault_code_o(fault_code),
    .commit_valid_o(commit_valid),.commit_o(commit),
    .cycle_count_o(cycle_count),.issue_count_o(issue_count),
    .commit_count_o(commit_count),.watchdog_enable_i(1'b1),.watchdog_limit_i(32'd256),
    .host_mem_valid_i(1'b0),.host_mem_shared_i(1'b0),.host_mem_write_i(1'b0),
    .host_mem_address_i('0),.host_mem_write_data_i('0),.inject_fault_i('0),.host_mem_ready_o(),.host_mem_response_valid_o(),.host_mem_response_fault_o(),
    .host_mem_read_data_o(),.debug_warp_pc_o(),.debug_active_mask_o(),
    .debug_gpr_pending_o(),.debug_pred_pending_o(),.debug_stack_depth_o(),
    .debug_resident_o(),.debug_barrier_wait_o(),.debug_memory_busy_o(),
    .debug_tracker_occupancy_o(),.debug_alu_occupancy_o(),.debug_mul_occupancy_o(),
    .debug_wb_occupancy_o(),.debug_epoch_o(),.debug_quiescent_o(),
    .debug_stack_top_o(),.debug_tracker_summary_o(),.debug_memory_completion_occupancy_o());
  task automatic pulse_clear; @(negedge clk); clear=1; @(posedge clk); #1; clear=0; endtask
  task automatic program_word(input logic[5:0]a,input logic[31:0]d);
    @(negedge clk); prog_addr=a;prog_data=d;prog_valid=1;@(posedge clk);#1;prog_valid=0; endtask
  task automatic launch; @(negedge clk);if(!launch_ready)$fatal(1,"launch blocked");
    launch_valid=1;@(posedge clk);#1;launch_valid=0; endtask
  task automatic wait_fault(input fault_code_t expected,input logic[31:0]pc);
    repeat(20)begin @(negedge clk);#1;if(fault)begin
      if(fault_code!=expected||fault_pc!=pc)$fatal(1,"fault mismatch code=%0d pc=%0d",fault_code,fault_pc);
      return;end end $fatal(1,"fault timeout"); endtask
  initial begin
    rst=1;clear=0;prog_valid=0;prog_addr=0;prog_data=0;launch_valid=0;launch_pc=0;
    launch_warp_count=1;commits=0;
    repeat(2)@(posedge clk);@(negedge clk);rst=0;
    // Lane IDs 0..3 exit first; lanes 4..7 execute MOVI before the final EXIT.
    program_word(0,32'h74040003); program_word(1,32'h38080004);
    program_word(2,32'h48004800); program_word(3,32'h7a000000);
    program_word(4,32'h380c0009); program_word(5,32'h78000000); launch();
    repeat(80)begin @(negedge clk);#1;if(fault)$fatal(1,"partial-exit program faulted");
      if(commit_valid)begin
        if($isunknown(commit))$fatal(1,"unknown completion");
        if(commit.sequence_number==3 && commit.write_mask!=8'h0f)$fatal(1,"partial EXIT mask mismatch");
        if(commit.sequence_number==4 && (commit.gpr_mask!=8'hf0||commit.gpr_data[7]!=9))
          $fatal(1,"surviving-lane write mismatch");
        if(commit.sequence_number==5 && commit.active_mask!=8'hf0)$fatal(1,"final EXIT active mask mismatch");
        commits++;end
      if(done)break;end
    if(!done||commits!=6)$fatal(1,"partial-exit completion mismatch commits=%0d",commits);

    pulse_clear(); program_word(0,32'h38040007); program_word(1,32'h38080003);
    program_word(2,32'h0c0c4800); program_word(3,32'h78000000); launch();
    mul_commits=0;
    repeat(80)begin @(negedge clk);#1;
      if(fault)$fatal(1,"multiply program faulted");
      if(commit_valid)begin
        if(commit.sequence_number==2 &&
           (commit.completion_class!=COMPLETION_MULTIPLIER ||
            commit.gpr_dst!=3 || commit.gpr_data[4]!=21))
          $fatal(1,"multiply completion mismatch");
        mul_commits++;end
      if(done)break;end
    if(!done||mul_commits!=4)$fatal(1,"multiply completion count=%0d",mul_commits);

    pulse_clear(); program_word(0,32'h72000000); // predicated BAR is illegal at runtime
    launch(); wait_fault(FAULT_BARRIER_VIOLATION,0);
    if(done||commit_valid)$fatal(1,"unsupported instruction committed");

    pulse_clear(); program_word(0,32'hfc000000); launch();
    wait_fault(FAULT_ILLEGAL_INSTRUCTION,0);

    pulse_clear(); program_word(0,32'h38040007); program_word(1,32'h78000000); launch();
    @(negedge clk); prog_valid=1;prog_addr=6'd1;prog_data=32'h0;
    @(posedge clk);#1;prog_valid=0; wait_fault(FAULT_IMEM_WRITE_WHILE_BUSY,0);
    if(commit_valid||done)$fatal(1,"busy programming allowed architectural completion");

    pulse_clear();
    if(fault||done||running||!launch_ready)$fatal(1,"clear did not restore launch state");
    $display("PASS tb_single_warp_lifecycle commits=%0d",commits);$finish;
  end
endmodule
