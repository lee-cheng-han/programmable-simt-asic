module tb_banked_vector_memory;
  import simt_gpu_pkg::*;
  logic clk=0,rst,clear,request_valid,request_ready,request_store;
  lane_mask_t request_mask,response_mask,pending_mask;
  word_t [LANES-1:0] request_address,request_store_data,response_load_data;
  logic response_valid,response_ready,response_fault,response_misaligned;
  logic response_out_of_range,busy;
  int checks;
  /* verilator lint_off BLKSEQ */
  always #5 clk=~clk;
  /* verilator lint_on BLKSEQ */
  banked_vector_memory dut(.*,.clear_i(clear),.request_valid_i(request_valid),
    .request_ready_o(request_ready),.request_store_i(request_store),
    .request_mask_i(request_mask),.request_address_i(request_address),
    .request_store_data_i(request_store_data),.response_valid_o(response_valid),
    .response_ready_i(response_ready),.response_fault_o(response_fault),
    .response_misaligned_o(response_misaligned),
    .response_out_of_range_o(response_out_of_range),.response_mask_o(response_mask),
    .response_load_data_o(response_load_data),.pending_mask_o(pending_mask),
    .busy_o(busy));

  task automatic issue(input logic store,input lane_mask_t mask);
    @(negedge clk);request_store=store;request_mask=mask;request_valid=1;
    if(!request_ready)$fatal(1,"request not ready");
    @(posedge clk);@(negedge clk);request_valid=0;
  endtask
  task automatic finish_response;
    while(!response_valid)@(negedge clk);
    response_ready=1;@(posedge clk);@(negedge clk);response_ready=0;checks++;
  endtask

  initial begin
    rst=1;clear=0;request_valid=0;request_store=0;request_mask=0;
    response_ready=0;checks=0;
    for(int lane=0;lane<LANES;lane++)begin
      request_address[lane]=0;request_store_data[lane]=0;
    end
    repeat(2)@(posedge clk);@(negedge clk);rst=0;

    // Eight different banks complete in one service cycle.
    for(int lane=0;lane<LANES;lane++)begin
      request_address[lane]=word_t'(lane*4);
      request_store_data[lane]=32'h100+lane;
    end
    issue(1,8'hff);finish_response();
    issue(0,8'hff);while(!response_valid)@(negedge clk);
    if(response_mask!==8'hff||pending_mask!='0)$fatal(1,"response metadata mismatch");
    for(int lane=0;lane<LANES;lane++)
      if(response_load_data[lane]!==word_t'(32'h100+lane))
        $fatal(1,"distinct-bank load mismatch lane=%0d",lane);
    finish_response();

    // Same-bank stores replay by lane; highest lane wins a duplicate address.
    for(int lane=0;lane<LANES;lane++)begin
      request_address[lane]=0;request_store_data[lane]=32'h200+lane;
    end
    issue(1,8'hff);repeat(7)begin @(negedge clk);if(response_valid)
      $fatal(1,"same-bank store completed early");end finish_response();
    request_mask=8'hff;issue(0,8'hff);while(!response_valid)@(negedge clk);
    for(int lane=0;lane<LANES;lane++)
      if(response_load_data[lane]!==32'h207)$fatal(1,"broadcast mismatch");
    finish_response();

    // Inactive bad addresses are ignored; active bad addresses fault atomically.
    request_address[7]=32'hffff_ffff;request_address[0]=4;
    issue(0,8'h01);while(!response_valid)@(negedge clk);
    if(response_fault)$fatal(1,"inactive address was validated");finish_response();
    request_address[0]=3;issue(1,8'h01);while(!response_valid)@(negedge clk);
    if(!response_fault||!response_misaligned||busy)$fatal(1,"alignment fault mismatch");
    finish_response();
    request_address[0]=SCRATCHPAD_BYTES;issue(0,8'h01);
    while(!response_valid)@(negedge clk);
    if(!response_fault||!response_out_of_range)$fatal(1,"range fault mismatch");
    finish_response();
    $display("PASS tb_banked_vector_memory checks=%0d",checks);$finish;
  end
endmodule
