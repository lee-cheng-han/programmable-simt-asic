module instruction_sram_adapter #(
  parameter int unsigned WORDS = 64,
  parameter int unsigned WORD_ADDR_W = $clog2(WORDS),
  parameter bit USE_IHP_MACRO = 1'b0
) (
  input  logic clk,
  input  logic rst,
  input  logic clear_i,
  input  logic prog_valid_i,
  input  logic [WORD_ADDR_W-1:0] prog_addr_i,
  input  logic [31:0] prog_data_i,
  input  logic read_valid_i,
  input  logic [WORD_ADDR_W-1:0] read_addr_i,
  input  logic response_ready_i,
  output logic response_valid_o,
  output logic [31:0] response_data_o
);
  localparam int unsigned ROWS = (WORDS + 1) / 2;
  localparam int unsigned ROW_ADDR_W = (ROWS <= 1) ? 1 : $clog2(ROWS);
  logic [63:0] macro_dout;
  /* verilator lint_off UNUSEDSIGNAL */
  logic [63:0] macro_din;
  logic [63:0] macro_mask;
  logic [5:0] macro_addr;
  /* verilator lint_on UNUSEDSIGNAL */
  logic read_half_q;

  always_comb begin
    macro_addr = '0;
    macro_din = '0;
    macro_mask = '0;
    if (prog_valid_i) begin
      macro_addr[ROW_ADDR_W-1:0] = prog_addr_i[WORD_ADDR_W-1:1];
      if (prog_addr_i[0]) begin
        macro_din[63:32] = prog_data_i;
        macro_mask[63:32] = '1;
      end else begin
        macro_din[31:0] = prog_data_i;
        macro_mask[31:0] = '1;
      end
    end else begin
      macro_addr[ROW_ADDR_W-1:0] = read_addr_i[WORD_ADDR_W-1:1];
    end
    response_data_o = read_half_q ? macro_dout[63:32] : macro_dout[31:0];
  end

  generate
    if (USE_IHP_MACRO) begin : gen_ihp
      RM_IHPSG13_1P_64x64_c2_bm_bist macro_u (
        .A_CLK(clk), .A_MEN(prog_valid_i || read_valid_i),
        .A_WEN(prog_valid_i), .A_REN(read_valid_i), .A_ADDR(macro_addr),
        .A_DIN(macro_din), .A_DLY(1'b0), .A_DOUT(macro_dout),
        .A_BM(macro_mask), .A_BIST_CLK(1'b0), .A_BIST_EN(1'b0),
        .A_BIST_MEN(1'b0), .A_BIST_WEN(1'b0), .A_BIST_REN(1'b0),
        .A_BIST_ADDR('0), .A_BIST_DIN('0), .A_BIST_BM('0));
    end else begin : gen_behavioral
      logic [63:0] rows [ROWS];
      always_ff @(posedge clk) begin
        if (prog_valid_i) begin
          if (prog_addr_i[0])
            rows[prog_addr_i[WORD_ADDR_W-1:1]][63:32] <= prog_data_i;
          else
            rows[prog_addr_i[WORD_ADDR_W-1:1]][31:0] <= prog_data_i;
        end
        if (read_valid_i)
          macro_dout <= rows[read_addr_i[WORD_ADDR_W-1:1]];
      end
    end
  endgenerate

  always_ff @(posedge clk) begin
    if (rst || clear_i) begin
      response_valid_o <= 1'b0;
      read_half_q <= 1'b0;
    end else begin
      if (response_valid_o && response_ready_i)
        response_valid_o <= 1'b0;
      if (read_valid_i) begin
        response_valid_o <= 1'b1;
        read_half_q <= read_addr_i[0];
      end
    end
  end

`ifndef SYNTHESIS
  initial assert (WORDS <= 128);
  property p_response_stable;
    @(posedge clk) disable iff (rst || clear_i)
      response_valid_o && !response_ready_i
      |=> response_valid_o && $stable(response_data_o);
  endproperty
  assert property (p_response_stable);
`endif
endmodule
