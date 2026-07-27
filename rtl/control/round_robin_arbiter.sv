module round_robin_arbiter #(
  parameter int unsigned REQUESTERS = 4,
  parameter int unsigned INDEX_W = (REQUESTERS <= 1) ? 1 : $clog2(REQUESTERS)
) (
  input  logic                  clk,
  input  logic                  rst,
  input  logic                  clear_i,
  input  logic [REQUESTERS-1:0] request_i,
  output logic                  grant_valid_o,
  output logic [INDEX_W-1:0]    grant_index_o,
  output logic [REQUESTERS-1:0] grant_onehot_o,
  input  logic                  grant_accept_i
);
  logic [INDEX_W-1:0] priority_q;

  always_comb begin
    grant_valid_o = 1'b0;
    grant_index_o = priority_q;
    grant_onehot_o = '0;
    for (int unsigned offset = 0; offset < REQUESTERS; offset++) begin
      logic [INDEX_W-1:0] candidate;
      candidate = INDEX_W'((int'(priority_q) + offset) % REQUESTERS);
      if (!grant_valid_o && request_i[candidate]) begin
        grant_valid_o = 1'b1;
        grant_index_o = INDEX_W'(candidate);
        grant_onehot_o[candidate] = 1'b1;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst || clear_i)
      priority_q <= '0;
    else if (grant_valid_o && grant_accept_i)
      priority_q <= INDEX_W'((int'(grant_index_o) + 1) % REQUESTERS);
  end

`ifndef SYNTHESIS
  property p_onehot_grant;
    @(posedge clk) disable iff (rst || clear_i)
      grant_valid_o |-> $onehot(grant_onehot_o);
  endproperty
  assert property (p_onehot_grant);

  property p_grant_is_requested;
    @(posedge clk) disable iff (rst || clear_i)
      grant_valid_o |-> request_i[grant_index_o];
  endproperty
  assert property (p_grant_is_requested);

  property p_stable_while_stalled;
    @(posedge clk) disable iff (rst || clear_i)
      grant_valid_o && !grant_accept_i
      |=> grant_valid_o && $stable(grant_index_o) &&
          $stable(grant_onehot_o);
  endproperty
  assert property (p_stable_while_stalled);
`endif
endmodule
