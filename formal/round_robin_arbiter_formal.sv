module round_robin_arbiter_formal #(
  parameter int unsigned REQUESTERS = 4,
  parameter int unsigned INDEX_W = (REQUESTERS <= 1) ? 1 : $clog2(REQUESTERS)
);
  (* gclk *) logic clk;
  logic rst = 1'b1;
  (* anyseq *) logic clear_i;
  (* anyseq *) logic [REQUESTERS-1:0] request_i;
  (* anyseq *) logic grant_accept_i;
  logic grant_valid_o;
  logic [INDEX_W-1:0] grant_index_o;
  logic [REQUESTERS-1:0] grant_onehot_o;
  logic past_valid = 1'b0;
  logic [$clog2(REQUESTERS+1)-1:0] requester_zero_wait_q;

  round_robin_arbiter #(.REQUESTERS(REQUESTERS)) dut (.*);

  always_ff @(posedge clk) begin
    past_valid <= 1'b1;
    rst <= 1'b0;

    if (past_valid && !$past(rst) && !$past(clear_i) &&
        $past(grant_valid_o && !grant_accept_i)) begin
      assume(request_i[$past(grant_index_o)]);
      assert(grant_valid_o);
      assert(grant_index_o == $past(grant_index_o));
      assert(grant_onehot_o == $past(grant_onehot_o));
    end

    if (!rst && !clear_i && grant_valid_o) begin
      assert(grant_onehot_o != '0);
      assert((grant_onehot_o & (grant_onehot_o - 1'b1)) == '0);
      assert(grant_onehot_o[grant_index_o]);
      assert(request_i[grant_index_o]);
    end

    if (rst || clear_i || !request_i[0] ||
        (grant_valid_o && grant_accept_i && grant_index_o == 0))
      requester_zero_wait_q <= '0;
    else if (grant_valid_o && grant_accept_i)
      requester_zero_wait_q <= requester_zero_wait_q + 1'b1;

    if (!rst && !clear_i && request_i[0])
      assert(requester_zero_wait_q < REQUESTERS);
  end
endmodule
