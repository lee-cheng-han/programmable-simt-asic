module reset_synchronizer #(
  parameter int unsigned STAGES = 2
) (
  input  logic clk_i,
  input  logic async_reset_i,
  output logic reset_o
);
  logic [STAGES-1:0] sync_q;

  always_ff @(posedge clk_i or posedge async_reset_i) begin
    if (async_reset_i)
      sync_q <= '1;
    else
      sync_q <= {sync_q[STAGES-2:0], 1'b0};
  end

  assign reset_o = sync_q[STAGES-1];

`ifndef SYNTHESIS
  initial assert (STAGES >= 2);
`endif
endmodule
