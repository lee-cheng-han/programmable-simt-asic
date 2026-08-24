module tb_data_sram_bank_adapter;
  logic clk=0,rst,clear,request_valid,request_ready_b,request_ready_m,request_write;
  logic[6:0]request_addr;logic[31:0]request_write_data;logic[3:0]request_byte_enable;
  logic response_valid_b,response_valid_m,response_ready;logic[31:0]response_data_b,response_data_m;
  logic bist_enable,bist_clk=0,bist_mem_enable,bist_write_enable,bist_read_enable;
  logic[5:0]bist_addr;logic[63:0]bist_write_data,bist_bit_mask;int checks;
  /* verilator lint_off BLKSEQ */ always #5 clk=~clk;always #7 bist_clk=~bist_clk; /* verilator lint_on BLKSEQ */
  data_sram_bank_adapter behavioral(.clk,.rst,.clear_i(clear),.request_valid_i(request_valid),
    .request_ready_o(request_ready_b),.request_write_i(request_write),.request_addr_i(request_addr),
    .request_write_data_i(request_write_data),.request_byte_enable_i(request_byte_enable),
    .response_valid_o(response_valid_b),.response_ready_i(response_ready),.response_read_data_o(response_data_b),
    .bist_enable_i(bist_enable),.bist_clk_i(bist_clk),.bist_mem_enable_i(bist_mem_enable),
    .bist_write_enable_i(bist_write_enable),.bist_read_enable_i(bist_read_enable),.bist_addr_i(bist_addr),
    .bist_write_data_i(bist_write_data),.bist_bit_mask_i(bist_bit_mask));
  data_sram_bank_adapter #(.USE_IHP_MACRO(1)) macro_model(.clk,.rst,.clear_i(clear),
    .request_valid_i(request_valid),.request_ready_o(request_ready_m),.request_write_i(request_write),
    .request_addr_i(request_addr),.request_write_data_i(request_write_data),.request_byte_enable_i(request_byte_enable),
    .response_valid_o(response_valid_m),.response_ready_i(response_ready),.response_read_data_o(response_data_m),
    .bist_enable_i(bist_enable),.bist_clk_i(bist_clk),.bist_mem_enable_i(bist_mem_enable),
    .bist_write_enable_i(bist_write_enable),.bist_read_enable_i(bist_read_enable),.bist_addr_i(bist_addr),
    .bist_write_data_i(bist_write_data),.bist_bit_mask_i(bist_bit_mask));
  task automatic request(input logic wr,input logic[6:0]addr,input logic[31:0]data,input logic[3:0]be);
    @(negedge clk);request_write=wr;request_addr=addr;request_write_data=data;request_byte_enable=be;request_valid=1;
    if(!request_ready_b||!request_ready_m)$fatal(1,"adapter not ready");
    @(posedge clk);@(negedge clk);request_valid=0;
  endtask
  task automatic check_read(input logic[31:0]expected);
    if(!response_valid_b||!response_valid_m||response_data_b!==expected||response_data_m!==expected||response_data_b!==response_data_m)
      $fatal(1,"adapter mismatch expected=%08x behavioral=%08x macro=%08x",expected,response_data_b,response_data_m);
    checks++;response_ready=1;@(posedge clk);@(negedge clk);response_ready=0;
  endtask
  initial begin
    rst=1;clear=0;request_valid=0;request_write=0;request_addr=0;request_write_data=0;request_byte_enable=0;
    response_ready=0;bist_enable=0;bist_mem_enable=0;bist_write_enable=0;bist_read_enable=0;
    bist_addr=0;bist_write_data=0;bist_bit_mask=0;checks=0;
    repeat(2)@(posedge clk);@(negedge clk);rst=0;
    request(1,7'd0,32'h11223344,4'hf);request(1,7'd1,32'haabbccdd,4'hf);
    request(0,7'd0,0,0);check_read(32'h11223344);request(0,7'd1,0,0);check_read(32'haabbccdd);
    request(1,7'd0,32'hdeadbeef,4'b0101);request(0,7'd0,0,0);check_read(32'h11ad33ef);
    request(0,7'd1,0,0);@(negedge clk);if(!response_valid_b)$fatal(1,"missing response");
    repeat(3)begin @(posedge clk);@(negedge clk);if(response_data_b!==32'haabbccdd||response_data_m!==32'haabbccdd)$fatal(1,"stalled data changed");end
    response_ready=1;@(posedge clk);@(negedge clk);response_ready=0;checks++;
    bist_enable=1;@(negedge clk);if(request_ready_b||request_ready_m)$fatal(1,"BIST did not own port");checks++;
    $display("PASS tb_data_sram_bank_adapter checks=%0d",checks);$finish;
  end
endmodule
