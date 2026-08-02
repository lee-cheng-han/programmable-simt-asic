module tb_warp_instruction_frontend;
  localparam int unsigned WORDS = 16;
  localparam int unsigned WARPS = 4;
  logic clk = 1'b0;
  logic rst, clear, flush, prog_valid, consume_valid;
  logic [3:0] prog_addr;
  logic [31:0] prog_data;
  logic [WARPS-1:0] warp_active;
  logic [WARPS-1:0][31:0] warp_pc;
  logic [1:0] consume_warp;
  logic [WARPS-1:0] buffer_valid;
  logic [WARPS-1:0][31:0] buffer_pc, buffer_instruction;
  logic request_valid;
  /* verilator lint_off UNUSEDSIGNAL */
  logic [1:0] request_warp;
  logic [3:0] request_addr;
  /* verilator lint_on UNUSEDSIGNAL */
  int unsigned checks;

  /* verilator lint_off BLKSEQ */
  always #5 clk = ~clk;
  /* verilator lint_on BLKSEQ */

  warp_instruction_frontend #(
    .IMEM_WORDS(WORDS),
    .WARPS(WARPS)
  ) dut (
    .clk(clk), .rst(rst), .clear_i(clear), .flush_i(flush),
    .prog_valid_i(prog_valid), .prog_addr_i(prog_addr),
    .prog_data_i(prog_data), .warp_active_i(warp_active),
    .warp_pc_i(warp_pc), .consume_valid_i(consume_valid),
    .consume_warp_i(consume_warp), .buffer_valid_o(buffer_valid),
    .buffer_pc_o(buffer_pc), .buffer_instruction_o(buffer_instruction),
    .request_valid_o(request_valid), .request_warp_o(request_warp),
    .request_addr_o(request_addr)
  );

  task automatic program_word(input logic [3:0] address);
    @(negedge clk);
    prog_valid = 1'b1;
    prog_addr = address;
    prog_data = 32'ha500_0000 | 32'(address);
    @(posedge clk);
    @(negedge clk);
    prog_valid = 1'b0;
  endtask

  task automatic wait_for_buffer(input int unsigned warp);
    repeat (20) begin
      @(negedge clk);
      if (buffer_valid[warp]) begin
        checks++;
        if (buffer_pc[warp] != warp_pc[warp] ||
            buffer_instruction[warp] !=
              (32'ha500_0000 | warp_pc[warp]))
          $fatal(1, "buffer mismatch warp=%0d pc=%0d instr=%08x",
                 warp, buffer_pc[warp], buffer_instruction[warp]);
        return;
      end
    end
    $fatal(1, "timed out waiting for warp=%0d", warp);
  endtask

  initial begin
    rst = 1'b1;
    clear = 1'b0;
    flush = 1'b0;
    prog_valid = 1'b0;
    prog_addr = '0;
    prog_data = '0;
    warp_active = '0;
    warp_pc = '0;
    consume_valid = 1'b0;
    consume_warp = '0;
    checks = 0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    for (int unsigned address = 0; address < WORDS; address++)
      program_word(4'(address));

    for (int unsigned warp = 0; warp < WARPS; warp++)
      warp_pc[warp] = 32'(warp + 1);
    warp_active = '1;
    for (int unsigned warp = 0; warp < WARPS; warp++)
      wait_for_buffer(warp);
    checks++;
    if (buffer_valid != '1)
      $fatal(1, "not all warp buffers filled valid=%b", buffer_valid);

    repeat (4) begin
      @(posedge clk);
      @(negedge clk);
      checks++;
      for (int unsigned warp = 0; warp < WARPS; warp++)
        if (!buffer_valid[warp] ||
            buffer_instruction[warp] !=
              (32'ha500_0000 | warp_pc[warp]))
          $fatal(1, "buffer changed without consume warp=%0d", warp);
    end

    @(negedge clk);
    consume_valid = 1'b1;
    consume_warp = 2'd2;
    @(posedge clk);
    #1;
    warp_pc[2] = 32'd9;
    @(negedge clk);
    consume_valid = 1'b0;
    wait_for_buffer(2);

    @(negedge clk);
    consume_valid = 1'b1;
    consume_warp = 2'd1;
    @(posedge clk);
    #1;
    warp_pc[1] = 32'd10;
    @(negedge clk);
    consume_valid = 1'b0;
    wait_for_buffer(1);
    checks++;
    if (buffer_pc[1] != 10)
      $fatal(1, "redirect retained wrong-path instruction");

    @(negedge clk);
    flush = 1'b1;
    @(posedge clk);
    @(negedge clk);
    flush = 1'b0;
    warp_active = '0;
    checks++;
    if (buffer_valid != '0 || request_valid)
      $fatal(1, "flush did not quiesce frontend");

    $display("PASS tb_warp_instruction_frontend checks=%0d", checks);
    $finish;
  end
endmodule
