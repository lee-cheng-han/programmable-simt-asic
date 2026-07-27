module tb_completion_arbiter;
  import simt_gpu_pkg::*;
  localparam int unsigned SOURCES = 3;
  logic clk = 0;
  logic rst, clear, output_valid, output_ready;
  logic [SOURCES-1:0] source_valid, source_ready;
  completion_record_t source_completion [SOURCES];
  /* verilator lint_off UNUSEDSIGNAL */
  completion_record_t output_completion;
  /* verilator lint_on UNUSEDSIGNAL */
  logic [1:0] selected;
  int unsigned checks;

  /* verilator lint_off BLKSEQ */
  always #5 clk = ~clk;
  /* verilator lint_on BLKSEQ */
  completion_arbiter #(.SOURCES(SOURCES)) dut (
    .clk(clk), .rst(rst), .clear_i(clear),
    .source_valid_i(source_valid), .source_ready_o(source_ready),
    .source_completion_i(source_completion),
    .completion_valid_o(output_valid), .completion_ready_i(output_ready),
    .completion_o(output_completion), .selected_source_o(selected));

  initial begin
    rst = 1; clear = 0; output_ready = 0; source_valid = 0; checks = 0;
    for (int source = 0; source < SOURCES; source++) begin
      source_completion[source] = '0;
      source_completion[source].valid = 1;
      source_completion[source].sequence_number = 16'(source + 10);
      source_completion[source].completion_class = completion_class_t'(source);
    end
    repeat (2) @(posedge clk);
    rst = 0;
    source_valid = '1;

    for (int expected = 0; expected < SOURCES; expected++) begin
      #1;
      if (!output_valid || selected != 2'(expected) ||
          output_completion.sequence_number != 16'(expected + 10) ||
          source_ready != 0)
        $fatal(1, "arbitration mismatch expected=%0d selected=%0d", expected, selected);
      // Hold the selected record during a two-cycle sink stall.
      repeat (2) begin
        @(posedge clk);
        #1;
        if (selected != 2'(expected) || source_ready != 0)
          $fatal(1, "selection changed while stalled");
      end
      output_ready = 1;
      #1;
      if (source_ready != (3'b001 << expected))
        $fatal(1, "ready was not routed to selected source");
      @(posedge clk);
      #1;
      output_ready = 0;
      checks++;
    end

    $display("PASS tb_completion_arbiter checks=%0d", checks);
    $finish;
  end
endmodule
