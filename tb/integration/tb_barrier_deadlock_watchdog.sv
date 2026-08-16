module tb_barrier_deadlock_watchdog;
  import simt_gpu_pkg::*;import simt_isa_pkg::*;
  logic clk=0,rst,clear,prog_valid,launch_valid,launch_ready,running,done,fault,commit_valid;
  logic[5:0]prog_addr;logic[31:0]prog_data,launch_pc,fault_pc;logic[2:0]launch_warp_count;
  fault_code_t fault_code;completion_record_t commit;logic[63:0]cycles,issues,commits;
  /* verilator lint_off UNUSEDSIGNAL */ logic unused_running=running,unused_commit=commit_valid;
  logic[31:0]unused_fault_pc=fault_pc;fault_code_t unused_fault_code=fault_code;
  completion_record_t unused_record=commit;logic[63:0]unused_counts=cycles^issues^commits;
  /* verilator lint_on UNUSEDSIGNAL */
  /* verilator lint_off BLKSEQ */ always #5 clk=~clk; /* verilator lint_on BLKSEQ */
  simt_core #(.BARRIER_TIMEOUT_CYCLES(32)) dut(.clk,.rst,.clear_i(clear),
    .prog_valid_i(prog_valid),.prog_addr_i(prog_addr),
    .prog_data_i(prog_data),.launch_valid_i(launch_valid),.launch_ready_o(launch_ready),
    .launch_pc_i(launch_pc),.launch_warp_count_i(launch_warp_count),
    .fetch_response_ready_i(1'b1),.execute_completion_ready_i(1'b1),.commit_ready_i(1'b1),
    .running_o(running),.done_o(done),.fault_o(fault),.fault_pc_o(fault_pc),
    .fault_code_o(fault_code),.commit_valid_o(commit_valid),.commit_o(commit),
    .cycle_count_o(cycles),.issue_count_o(issues),.commit_count_o(commits));
  function automatic logic[31:0]enc(input opcode_t op,input logic[3:0]rd,
    input logic[3:0]ra,input logic[3:0]rb,input logic[9:0]imm);
    return {op,4'b0,rd,ra,rb,imm};endfunction
  task automatic put(input logic[5:0]addr,input logic[31:0]word);
    @(negedge clk);prog_addr=addr;prog_data=word;prog_valid=1;
    @(posedge clk);@(negedge clk);prog_valid=0;endtask
  initial begin
    rst=1;clear=0;prog_valid=0;launch_valid=0;prog_addr=0;prog_data=0;
    launch_pc=0;launch_warp_count=4;
    repeat(2)@(posedge clk);@(negedge clk);rst=0;
    // Warp zero exits; warps one through three branch to BAR and can never release.
    put(0,enc(OP_S2R,1,0,0,1));put(1,enc(OP_MOVI,2,0,0,0));
    put(2,enc(OP_SETP_EQ,0,1,2,0));put(3,enc(OP_BRA,0,0,0,1)|32'h03000000);
    put(4,enc(OP_BAR,0,0,0,0));put(5,enc(OP_EXIT,0,0,0,0));
    @(negedge clk);if(!launch_ready)$fatal(1,"launch not ready");launch_valid=1;
    @(posedge clk);@(negedge clk);launch_valid=0;
    repeat(100)begin @(negedge clk);if(done)$fatal(1,"deadlock asserted done");if(fault)break;end
    if(!fault||fault_code!=FAULT_BARRIER_DEADLOCK||fault_pc!=4)
      $fatal(1,"missing watchdog fault code=%0d pc=%0d",fault_code,fault_pc);
    $display("PASS tb_barrier_deadlock_watchdog code=%0d pc=%0d",fault_code,fault_pc);$finish;
  end
endmodule
