module tb_round_robin_arbiter;
  localparam int unsigned REQUESTERS = 4;
  logic clk = 0;
  logic rst, clear, accept;
  logic [REQUESTERS-1:0] request, grant;
  logic valid;
  logic [1:0] index;
  int unsigned checks;

  /* verilator lint_off BLKSEQ */
  always #5 clk = ~clk;
  /* verilator lint_on BLKSEQ */
  round_robin_arbiter #(.REQUESTERS(REQUESTERS)) dut (
    .clk(clk), .rst(rst), .clear_i(clear), .request_i(request),
    .grant_valid_o(valid), .grant_index_o(index),
    .grant_onehot_o(grant), .grant_accept_i(accept)
  );

  task automatic expect_grant(input int unsigned expected);
    #1;
    if (!valid || index != 2'(expected) || grant != (4'b0001 << expected))
      $fatal(1, "grant mismatch expected=%0d actual=%0d onehot=%b",
             expected, index, grant);
    checks++;
  endtask

  initial begin
    rst = 1; clear = 0; accept = 0; request = 0;
    repeat (2) @(posedge clk);
    rst = 0;

    request = 4'b1111;
    for (int unsigned expected = 0; expected < REQUESTERS; expected++) begin
      expect_grant(expected);
      accept = 1;
      @(posedge clk);
      #1;
      accept = 0;
    end
    expect_grant(0);

    // A selected requester remains selected throughout downstream stalls.
    request = 4'b1010;
    expect_grant(1);
    repeat (3) begin
      @(posedge clk);
      expect_grant(1);
    end
    accept = 1;
    @(posedge clk);
    #1;
    accept = 0;
    expect_grant(3);

    // Removing the stalled request permits a new combinational selection.
    request = 4'b0100;
    expect_grant(2);
    accept = 1;
    @(posedge clk);
    #1;
    accept = 0;
    request = 0;
    #1;
    if (valid || grant != 0) $fatal(1, "idle grant was not empty");
    checks++;

    clear = 1;
    @(posedge clk);
    #1;
    clear = 0;
    request = 4'b1001;
    expect_grant(0);

    $display("PASS tb_round_robin_arbiter checks=%0d", checks);
    $finish;
  end
endmodule
