module tb_memory_subsystem;
  import simt_gpu_pkg::*;
  logic clk=0,rst,clear,fatal,request_valid,request_ready,request_shared,request_store;
  logic[KERNEL_EPOCH_WIDTH-1:0]request_epoch;logic[WARP_ID_WIDTH-1:0]request_warp;
  logic[INSTRUCTION_SEQUENCE_WIDTH-1:0]request_sequence;logic[31:0]request_pc,request_instruction;
  lane_mask_t request_active_mask,request_mask;logic[REG_INDEX_WIDTH-1:0]request_gpr_dst;
  word_t [LANES-1:0] request_address,request_store_data;
  logic completion_valid,completion_ready;
  /* verilator lint_off UNUSEDSIGNAL */ completion_record_t completion;
  /* verilator lint_on UNUSEDSIGNAL */
  logic fault_valid;fault_code_t fault_code;logic[31:0]fault_pc;
  logic[WARPS-1:0]warp_busy;logic[2:0]tracker_occupancy;int checks;
  /* verilator lint_off BLKSEQ */ always #5 clk=~clk; /* verilator lint_on BLKSEQ */
  memory_subsystem dut(.*,.clear_i(clear),.fatal_i(fatal),
    .request_valid_i(request_valid),.request_ready_o(request_ready),
    .request_shared_i(request_shared),.request_store_i(request_store),
    .request_epoch_i(request_epoch),.request_warp_i(request_warp),
    .request_sequence_i(request_sequence),.request_pc_i(request_pc),
    .request_instruction_i(request_instruction),.request_active_mask_i(request_active_mask),
    .request_mask_i(request_mask),.request_gpr_dst_i(request_gpr_dst),
    .request_address_i(request_address),.request_store_data_i(request_store_data),
    .completion_valid_o(completion_valid),.completion_ready_i(completion_ready),
    .completion_o(completion),.fault_valid_o(fault_valid),.fault_code_o(fault_code),
    .fault_pc_o(fault_pc),.warp_busy_o(warp_busy),.tracker_occupancy_o(tracker_occupancy));
  task automatic issue(input int warp,input logic shared,input logic store,input int seq_id);
    @(negedge clk);request_warp=WARP_ID_WIDTH'(warp);request_shared=shared;
    request_store=store;request_sequence=INSTRUCTION_SEQUENCE_WIDTH'(seq_id);
    request_pc=32'(seq_id*4);request_instruction=store?32'h5c000000:32'h580c0000;
    for(int lane=0;lane<LANES;lane++)begin
      request_address[lane]=word_t'(warp*256+lane*32);
      request_store_data[lane]=word_t'(32'h1000+warp*16+lane);
    end
    #1;
    if(!request_ready)$fatal(1,"request rejected warp=%0d occupancy=%0d",warp,tracker_occupancy);
    request_valid=1;@(posedge clk);@(negedge clk);request_valid=0;
  endtask
  task automatic take_completion(input int expected_warp,input logic writes);
    while(!completion_valid)@(negedge clk);
    if(completion.warp_id!=WARP_ID_WIDTH'(expected_warp)||
       completion.completion_class!=COMPLETION_MEMORY||completion.writes_gpr!=writes)
      $fatal(1,"completion mismatch warp=%0d got=%0d",expected_warp,completion.warp_id);
    completion_ready=1;@(posedge clk);@(negedge clk);completion_ready=0;checks++;
  endtask
  initial begin
    rst=1;clear=0;fatal=0;request_valid=0;request_shared=0;request_store=0;
    request_epoch=1;request_warp=0;request_sequence=0;request_pc=0;request_instruction=0;
    request_active_mask='1;request_mask='1;request_gpr_dst=3;completion_ready=0;checks=0;
    for(int lane=0;lane<LANES;lane++)begin request_address[lane]=0;request_store_data[lane]=0;end
    repeat(2)@(posedge clk);@(negedge clk);rst=0;
    issue(0,0,1,0);issue(1,1,1,0);issue(2,0,1,0);issue(3,1,1,0);
    if(request_ready||tracker_occupancy!=4||warp_busy!=4'b1111)
      $fatal(1,"four-tracker capacity mismatch occupancy=%0d busy=%b",tracker_occupancy,warp_busy);
    // Same-warp and fifth requests remain blocked until their tracker retires.
    repeat(20)@(negedge clk);
    take_completion(0,0);take_completion(1,0);take_completion(2,0);take_completion(3,0);
    if(tracker_occupancy!=0||warp_busy!='0)$fatal(1,"trackers did not drain");
    issue(0,0,0,1);while(!completion_valid)@(negedge clk);
    for(int lane=0;lane<LANES;lane++)
      if(completion.gpr_data[lane]!==word_t'(32'h1000+lane))
        $fatal(1,"load data mismatch lane=%0d",lane);
    take_completion(0,1);
    // An active misaligned lane faults without producing a completion.
    request_mask=8'h01;@(negedge clk);request_address[0]=3;request_warp=0;
    request_shared=0;request_store=1;request_sequence=2;request_pc=32'h88;
    request_valid=1;@(posedge clk);@(negedge clk);request_valid=0;
    repeat(10)begin @(negedge clk);if(fault_valid)break;end
    if(!fault_valid||fault_code!=FAULT_MEMORY_MISALIGNED||fault_pc!=32'h88)
      $fatal(1,"memory fault mismatch");checks++;
    $display("PASS tb_memory_subsystem checks=%0d",checks);$finish;
  end
endmodule
