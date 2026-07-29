module tb_four_warp_divergence;
  import simt_gpu_pkg::*;
  logic clk=0,rst,clear,prog_valid,launch_valid;
  logic [5:0] prog_addr;
  logic [31:0] prog_data,launch_pc,fault_pc;
  logic [2:0] launch_warp_count;
  logic launch_ready,running,done,fault,commit_valid;
  fault_code_t fault_code;
  /* verilator lint_off UNUSEDSIGNAL */
  completion_record_t commit;
  /* verilator lint_on UNUSEDSIGNAL */
  logic [63:0] cycle_count,issue_count,commit_count;
  word_t final_r3 [LANES];
  word_t shadow_gpr [REGS_PER_THREAD][LANES];
  lane_mask_t shadow_pred [PREDS_PER_THREAD];
  lane_mask_t shadow_active;
  integer trace_file;
  word_t multi_r3 [WARPS][LANES];
  word_t nested_r4 [LANES];
  int unsigned commits, multi_sequence [WARPS], multi_commits, nested_commits;

  /* verilator lint_off BLKSEQ */
  always #5 clk=~clk;
  /* verilator lint_on BLKSEQ */
  simt_core dut(
    .clk(clk),.rst(rst),.clear_i(clear),.prog_valid_i(prog_valid),
    .prog_addr_i(prog_addr),.prog_data_i(prog_data),
    .launch_valid_i(launch_valid),.launch_ready_o(launch_ready),
    .launch_pc_i(launch_pc),.launch_warp_count_i(launch_warp_count),
    .running_o(running),.done_o(done),.fault_o(fault),
    .fault_pc_o(fault_pc),.fault_code_o(fault_code),
    .commit_valid_o(commit_valid),.commit_o(commit),
    .cycle_count_o(cycle_count),.issue_count_o(issue_count),
    .commit_count_o(commit_count));

  task automatic word(input logic[5:0] a,input logic[31:0] d);
    @(negedge clk);prog_addr=a;prog_data=d;prog_valid=1;
    @(posedge clk);@(negedge clk);prog_valid=0;
  endtask
  task automatic clear_core;
    @(negedge clk);clear=1;@(posedge clk);@(negedge clk);clear=0;
  endtask
  task automatic launch(input int unsigned warps);
    if(warps<1||warps>WARPS)$fatal(1,"invalid launch count");
    @(negedge clk);launch_warp_count=3'(warps);#1;
    if(!launch_ready)$fatal(1,"launch blocked");
    launch_valid=1;@(posedge clk);@(negedge clk);launch_valid=0;
  endtask
  task automatic expect_fault(input fault_code_t code,input logic[31:0] pc);
    repeat(30)begin @(negedge clk);#1;if(fault)begin
      if(fault_code!=code||fault_pc!=pc)
        $fatal(1,"fault mismatch code=%0d pc=%0d",fault_code,fault_pc);
      return;end end
    $fatal(1,"fault timeout expected=%0d",code);
  endtask

  initial begin
    rst=1;clear=0;prog_valid=0;prog_addr=0;prog_data=0;
    launch_valid=0;launch_pc=0;launch_warp_count=1;commits=0;
    shadow_active='1;
    for(int reg_index=0;reg_index<REGS_PER_THREAD;reg_index++)
      for(int lane=0;lane<LANES;lane++)shadow_gpr[reg_index][lane]=0;
    for(int pred=0;pred<PREDS_PER_THREAD;pred++)shadow_pred[pred]=0;
    for(int lane=0;lane<LANES;lane++)final_r3[lane]=0;
    trace_file=$fopen("build/rtl_divergence.trace","w");
    repeat(2)@(posedge clk);@(negedge clk);rst=0;

    word(0,32'h74040003);word(1,32'h38080004);
    word(2,32'h48004800);word(3,32'h6c000004);
    word(4,32'h6a000002);word(5,32'h380c0009);
    word(6,32'h68000001);word(7,32'h380c0005);
    word(8,32'h7c000000);word(9,32'h78000000);
    launch(1);
    repeat(160)begin @(negedge clk);#1;
      if(fault)$fatal(1,"divergence program faulted code=%0d pc=%0d",
                       fault_code,fault_pc);
      if(commit_valid)begin
        if(commit.sequence_number!=16'(commits))
          $fatal(1,"sequence mismatch got=%0d expected=%0d",
                 commit.sequence_number,commits);
        if(commit.pc==7 && commit.gpr_mask!=8'h0f)
          $fatal(1,"taken-path mask mismatch %h",commit.gpr_mask);
        if(commit.pc==5 && commit.gpr_mask!=8'hf0)
          $fatal(1,"deferred-path mask mismatch %h",commit.gpr_mask);
        if(commit.writes_gpr&&commit.gpr_dst==3)
          for(int lane=0;lane<LANES;lane++)
            if(commit.gpr_mask[lane])final_r3[lane]=commit.gpr_data[lane];
        if(commit.writes_gpr)
          for(int lane=0;lane<LANES;lane++)
            if(commit.gpr_mask[lane])
              shadow_gpr[commit.gpr_dst][lane]=commit.gpr_data[lane];
        if(commit.writes_pred)
          for(int lane=0;lane<LANES;lane++)
            if(commit.pred_mask[lane])
              shadow_pred[commit.pred_dst][lane]=commit.pred_data[lane];
        if(commit.pc==4)shadow_active=8'h0f;
        if(commit.pc==8)shadow_active=(commits==6)?8'hf0:8'hff;
        if(commit.pc==9)shadow_active='0;
        $fwrite(trace_file,"E %0d %08x %08x %02x\nR",
                commits,commit.pc,commit.instruction,shadow_active);
        for(int reg_index=0;reg_index<REGS_PER_THREAD;reg_index++)
          for(int lane=0;lane<LANES;lane++)
            $fwrite(trace_file," %08x",shadow_gpr[reg_index][lane]);
        $fwrite(trace_file,"\nP");
        for(int pred=0;pred<PREDS_PER_THREAD;pred++)
          $fwrite(trace_file," %02x",shadow_pred[pred]);
        $fwrite(trace_file,"\n");
        commits++;end
      if(done)break;end
    if(!done||running||cycle_count==0||commits!=11||
       issue_count!=11||commit_count!=11)
      $fatal(1,"divergence drain mismatch commits=%0d issue=%0d count=%0d",
             commits,issue_count,commit_count);
    for(int lane=0;lane<LANES;lane++)
      if(final_r3[lane]!=(lane<4?5:9))
        $fatal(1,"reconverged value mismatch lane=%0d value=%0d",
               lane,final_r3[lane]);
    $fclose(trace_file);

    // All four warps independently split and reconverge at the same time.
    clear_core();multi_commits=0;
    for(int warp=0;warp<WARPS;warp++)begin
      multi_sequence[warp]=0;
      for(int lane=0;lane<LANES;lane++)multi_r3[warp][lane]=0;
    end
    launch(4);
    repeat(500)begin @(negedge clk);#1;
      if(fault)$fatal(1,"multi-warp divergence faulted");
      if(commit_valid)begin
        int unsigned warp;
        warp=int'(commit.warp_id);
        if(commit.sequence_number!=16'(multi_sequence[warp]))
          $fatal(1,"multi-warp sequence mismatch warp=%0d",warp);
        if(commit.writes_gpr&&commit.gpr_dst==3)
          for(int lane=0;lane<LANES;lane++)
            if(commit.gpr_mask[lane])
              multi_r3[warp][lane]=commit.gpr_data[lane];
        multi_sequence[warp]++;multi_commits++;end
      if(done)break;end
    if(!done||multi_commits!=44)$fatal(1,"multi-warp commits=%0d",multi_commits);
    for(int warp=0;warp<WARPS;warp++)
      for(int lane=0;lane<LANES;lane++)
        if(multi_r3[warp][lane]!=(lane<4?5:9))
          $fatal(1,"multi-warp value warp=%0d lane=%0d",warp,lane);

    // A depth-two nested split produces three independently masked results.
    clear_core();
    word(0,32'h74040003);word(1,32'h38080004);word(2,32'h48004800);
    word(3,32'h6c00000b);word(4,32'h6a000002);word(5,32'h3810005a);
    word(6,32'h68000008);word(7,32'h380c0002);word(8,32'h48044c00);
    word(9,32'h6c000004);word(10,32'h6a400002);word(11,32'h3810001e);
    word(12,32'h68000001);word(13,32'h3810000a);
    word(14,32'h7c000000);word(15,32'h7c000000);word(16,32'h78000000);
    nested_commits=0;
    for(int lane=0;lane<LANES;lane++)nested_r4[lane]=0;
    launch(1);
    repeat(300)begin @(negedge clk);#1;
      if(fault)$fatal(1,"nested divergence faulted code=%0d pc=%0d",
                       fault_code,fault_pc);
      if(commit_valid)begin
        if(commit.sequence_number!=16'(nested_commits))
          $fatal(1,"nested sequence mismatch");
        if(commit.writes_gpr&&commit.gpr_dst==4)
          for(int lane=0;lane<LANES;lane++)
            if(commit.gpr_mask[lane])nested_r4[lane]=commit.gpr_data[lane];
        nested_commits++;end
      if(done)break;end
    if(!done||nested_commits!=19)$fatal(1,"nested commits=%0d",nested_commits);
    for(int lane=0;lane<LANES;lane++)
      if(nested_r4[lane]!=(lane<2?10:lane<4?30:90))
        $fatal(1,"nested value lane=%0d value=%0d",lane,nested_r4[lane]);

    clear_core();word(0,32'h7c000000);launch(1);
    expect_fault(FAULT_SIMT_STACK_UNDERFLOW,0);

    clear_core();
    for(int pc=0;pc<9;pc++)word(6'(pc),32'h6c000000);
    launch(1);expect_fault(FAULT_SIMT_STACK_OVERFLOW,8);

    $display("PASS tb_four_warp_divergence baseline=%0d multi=%0d nested=%0d",
             commits,multi_commits,nested_commits);
    $finish;
  end
endmodule
