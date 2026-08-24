/* verilator lint_off UNUSEDSIGNAL */
module data_sram_bank_adapter #(
  parameter int unsigned WORDS=128,parameter int unsigned WORD_ADDR_W=$clog2(WORDS),
  parameter bit LOW_HALF_ONLY=1'b0,parameter bit USE_IHP_MACRO=1'b0)(
  input logic clk,rst,clear_i,input logic request_valid_i,output logic request_ready_o,
  input logic request_write_i,input logic[WORD_ADDR_W-1:0]request_addr_i,
  input logic[31:0]request_write_data_i,input logic[3:0]request_byte_enable_i,
  output logic response_valid_o,input logic response_ready_i,output logic[31:0]response_read_data_o,
  input logic bist_enable_i,bist_clk_i,bist_mem_enable_i,bist_write_enable_i,bist_read_enable_i,
  input logic[5:0]bist_addr_i,input logic[63:0]bist_write_data_i,bist_bit_mask_i);
  localparam int unsigned ROWS=LOW_HALF_ONLY?WORDS:(WORDS+1)/2;
  localparam int unsigned ROW_ADDR_W=(ROWS<=1)?1:$clog2(ROWS);
  logic[63:0]macro_dout,macro_din,macro_mask;logic[5:0]macro_addr;
  logic read_half_q,accepted_read,accepted_write;
  always_comb begin
    request_ready_o=!bist_enable_i&&(!response_valid_o||response_ready_i);
    accepted_read=request_valid_i&&request_ready_o&&!request_write_i;
    accepted_write=request_valid_i&&request_ready_o&&request_write_i;
    macro_addr='0;
    macro_addr[ROW_ADDR_W-1:0]=ROW_ADDR_W'(request_addr_i>>(LOW_HALF_ONLY?0:1));
    macro_din={2{request_write_data_i}};macro_mask='0;
    if(!LOW_HALF_ONLY&&request_addr_i[0])
      for(int byte_index=0;byte_index<4;byte_index++)
        macro_mask[32+byte_index*8+:8]={8{request_byte_enable_i[byte_index]}};
    else
      for(int byte_index=0;byte_index<4;byte_index++)
        macro_mask[byte_index*8+:8]={8{request_byte_enable_i[byte_index]}};
    response_read_data_o=read_half_q?macro_dout[63:32]:macro_dout[31:0];
  end
  generate
    if(USE_IHP_MACRO)begin:gen_ihp
      RM_IHPSG13_1P_64x64_c2_bm_bist macro_u(
        .A_CLK(clk),.A_MEN(accepted_read||accepted_write),.A_WEN(accepted_write),
        .A_REN(accepted_read),.A_ADDR(macro_addr),.A_DIN(macro_din),.A_DLY(1'b0),
        .A_DOUT(macro_dout),.A_BM(macro_mask),.A_BIST_CLK(bist_clk_i),
        .A_BIST_EN(bist_enable_i),.A_BIST_MEN(bist_mem_enable_i),
        .A_BIST_WEN(bist_write_enable_i),.A_BIST_REN(bist_read_enable_i),
        .A_BIST_ADDR(bist_addr_i),.A_BIST_DIN(bist_write_data_i),.A_BIST_BM(bist_bit_mask_i));
    end else begin:gen_behavioral
      logic[63:0]rows[ROWS];
      always_ff @(posedge clk)begin
        if(accepted_write)
          for(int bit_index=0;bit_index<64;bit_index++)
            if(macro_mask[bit_index])rows[macro_addr[ROW_ADDR_W-1:0]][bit_index]<=macro_din[bit_index];
        if(accepted_read)macro_dout<=rows[macro_addr[ROW_ADDR_W-1:0]];
      end
    end
  endgenerate
  always_ff @(posedge clk)begin
    if(rst||clear_i)begin response_valid_o<=1'b0;read_half_q<=1'b0;end
    else begin
      if(response_valid_o&&response_ready_i)response_valid_o<=1'b0;
      if(accepted_read)begin response_valid_o<=1'b1;read_half_q<=!LOW_HALF_ONLY&&request_addr_i[0];end
    end
  end
`ifndef SYNTHESIS
  initial begin
    assert(WORDS>=2&&WORDS<=128);assert((WORDS%2)==0);
    if(LOW_HALF_ONLY)assert(WORDS<=64);
  end
  property p_response_stable;@(posedge clk)disable iff(rst||clear_i)
    response_valid_o&&!response_ready_i|=>response_valid_o&&$stable(response_read_data_o);
  endproperty
  assert property(p_response_stable);
  property p_bist_excludes_functional;@(posedge clk)bist_enable_i|->!request_ready_o;endproperty
  assert property(p_bist_excludes_functional);
`endif
endmodule
/* verilator lint_on UNUSEDSIGNAL */
