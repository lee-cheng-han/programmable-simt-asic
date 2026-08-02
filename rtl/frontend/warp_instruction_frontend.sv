module warp_instruction_frontend #(
  parameter int unsigned IMEM_WORDS = 64,
  parameter int unsigned IMEM_ADDR_W = $clog2(IMEM_WORDS),
  parameter int unsigned WARPS = 4,
  parameter int unsigned WARP_ID_W = $clog2(WARPS)
) (
  input  logic clk,
  input  logic rst,
  input  logic clear_i,
  input  logic flush_i,

  input  logic prog_valid_i,
  input  logic [IMEM_ADDR_W-1:0] prog_addr_i,
  input  logic [31:0] prog_data_i,

  input  logic [WARPS-1:0] warp_active_i,
  input  logic [WARPS-1:0][31:0] warp_pc_i,
  input  logic consume_valid_i,
  input  logic [WARP_ID_W-1:0] consume_warp_i,

  output logic [WARPS-1:0] buffer_valid_o,
  output logic [WARPS-1:0][31:0] buffer_pc_o,
  output logic [WARPS-1:0][31:0] buffer_instruction_o,
  output logic request_valid_o,
  output logic [WARP_ID_W-1:0] request_warp_o,
  output logic [IMEM_ADDR_W-1:0] request_addr_o
);
  logic [31:0] storage [IMEM_WORDS];
  logic [WARPS-1:0] request_candidates;
  logic request_grant_valid;
  logic [WARPS-1:0] request_grant;
  logic response_pending_q;
  logic [WARP_ID_W-1:0] response_warp_q;
  logic [31:0] response_pc_q;
  logic [31:0] response_data_q;

  always_comb begin
    for (int unsigned warp = 0; warp < WARPS; warp++) begin
      request_candidates[warp] =
        warp_active_i[warp] && !buffer_valid_o[warp] &&
        !(response_pending_q &&
          response_warp_q == WARP_ID_W'(warp)) &&
        warp_pc_i[warp] < 32'(IMEM_WORDS);
    end
    request_valid_o = request_grant_valid && !prog_valid_i &&
                      !clear_i && !flush_i;
    request_addr_o = IMEM_ADDR_W'(warp_pc_i[request_warp_o]);
  end

  round_robin_arbiter #(.REQUESTERS(WARPS)) request_arbiter_u (
    .clk(clk),
    .rst(rst),
    .clear_i(clear_i || flush_i),
    .request_i(request_candidates),
    .grant_valid_o(request_grant_valid),
    .grant_index_o(request_warp_o),
    .grant_onehot_o(request_grant),
    .grant_accept_i(request_valid_o)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      buffer_valid_o <= '0;
      buffer_pc_o <= '0;
      buffer_instruction_o <= '0;
      response_pending_q <= 1'b0;
      response_warp_q <= '0;
      response_pc_q <= '0;
      response_data_q <= '0;
    end else if (clear_i || flush_i) begin
      buffer_valid_o <= '0;
      response_pending_q <= 1'b0;
    end else begin
      if (prog_valid_i)
        storage[prog_addr_i] <= prog_data_i;

      if (consume_valid_i)
        buffer_valid_o[consume_warp_i] <= 1'b0;

      response_pending_q <= request_valid_o;
      if (request_valid_o) begin
        response_warp_q <= request_warp_o;
        response_pc_q <= warp_pc_i[request_warp_o];
        response_data_q <= storage[request_addr_o];
      end

      if (response_pending_q &&
          warp_active_i[response_warp_q] &&
          warp_pc_i[response_warp_q] == response_pc_q) begin
        buffer_valid_o[response_warp_q] <= 1'b1;
        buffer_pc_o[response_warp_q] <= response_pc_q;
        buffer_instruction_o[response_warp_q] <= response_data_q;
      end
    end
  end

`ifndef SYNTHESIS
  always_comb begin
    assert ($onehot0(request_grant));
    if (request_valid_o) begin
      assert (request_grant[request_warp_o]);
      assert (warp_active_i[request_warp_o]);
      assert (!buffer_valid_o[request_warp_o]);
      assert (warp_pc_i[request_warp_o] < 32'(IMEM_WORDS));
    end
    for (int unsigned warp = 0; warp < WARPS; warp++)
      if (buffer_valid_o[warp]) begin
        assert (warp_active_i[warp]);
        assert (buffer_pc_o[warp] == warp_pc_i[warp]);
      end
  end
`endif
endmodule
