module tb_shared_reduction;
  import simt_gpu_pkg::*;import simt_isa_pkg::*;
  logic clk=0,rst,clear,prog_valid,launch_valid,launch_ready,running,done,fault,commit_valid;
  logic[5:0]prog_addr;logic[31:0]prog_data,launch_pc,fault_pc;logic[2:0]launch_warp_count;
  fault_code_t fault_code;completion_record_t commit;
  logic[63:0]cycles,issues,commits;int observed,results,barriers;
  /* verilator lint_off UNUSEDSIGNAL */ logic unused_running=running;
  logic[63:0]unused_cycles=cycles; /* verilator lint_on UNUSEDSIGNAL */
  /* verilator lint_off BLKSEQ */ always #5 clk=~clk; /* verilator lint_on BLKSEQ */
  simt_core dut(.clk,.rst,.clear_i(clear),.prog_valid_i(prog_valid),.prog_addr_i(prog_addr),
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
    launch_pc=0;launch_warp_count=4;observed=0;results=0;barriers=0;
    repeat(2)@(posedge clk);@(negedge clk);rst=0;
    put(0,enc(OP_S2R,1,0,0,1));put(1,enc(OP_MOVI,2,0,0,2));
    put(2,enc(OP_SHL,3,1,2,0));put(3,enc(OP_ST_S,0,3,1,0));
    put(4,enc(OP_BAR,0,0,0,0));put(5,enc(OP_MOVI,4,0,0,0));
    put(6,enc(OP_LD_S,5,4,0,0));put(7,enc(OP_MOVI,4,0,0,4));
    put(8,enc(OP_LD_S,6,4,0,0));put(9,enc(OP_ADD,5,5,6,0));
    put(10,enc(OP_MOVI,4,0,0,8));put(11,enc(OP_LD_S,6,4,0,0));
    put(12,enc(OP_ADD,5,5,6,0));put(13,enc(OP_MOVI,4,0,0,10'd12));
    put(14,enc(OP_LD_S,6,4,0,0));put(15,enc(OP_ADD,5,5,6,0));
    put(16,enc(OP_EXIT,0,0,0,0));
    @(negedge clk);if(!launch_ready)$fatal(1,"launch not ready");launch_valid=1;
    @(posedge clk);@(negedge clk);launch_valid=0;
    repeat(2000)begin @(negedge clk);
      if(commit_valid)begin
        observed++;
        if(commit.instruction[31:26]==OP_BAR)barriers++;
        if(commit.pc==15)begin
          results++;
          if(barriers!=4||commit.gpr_mask!=8'hff)$fatal(1,"reduction crossed barrier");
          for(int lane=0;lane<8;lane++)if(commit.gpr_data[lane]!=6)
            $fatal(1,"bad reduction warp=%0d lane=%0d value=%0d",commit.warp_id,lane,commit.gpr_data[lane]);
        end
      end
      if(done||fault)break;
    end
    if(fault)$fatal(1,"reduction fault code=%0d pc=%0d",fault_code,fault_pc);
    if(!done||observed!=68||results!=4||issues!=68||commits!=68)
      $fatal(1,"reduction drain mismatch observed=%0d results=%0d",observed,results);
    $display("PASS tb_shared_reduction commits=%0d cycles=%0d",observed,cycles);$finish;
  end
endmodule
