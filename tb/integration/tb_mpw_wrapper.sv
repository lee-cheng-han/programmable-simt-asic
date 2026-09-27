module tb_mpw_wrapper;
  import simt_gpu_pkg::*;
  import simt_isa_pkg::*;

  logic clk = 0;
  logic reset_n = 0;
  logic cyc = 0, stb = 0, we = 0;
  logic [7:0] adr = 0;
  logic [31:0] wdata = 0, rdata;
  logic [3:0] sel = 0;
  logic ack, err;
  logic test_mode = 0, scan_enable = 0, scan_in = 0, scan_out;
  logic bist_start = 0, bist_active, bist_done, bist_fail;
  logic bist_fail_shared;
  logic [31:0] bist_fail_address;
  logic irq_done, irq_fault;
  int checks, bist_cycles;

  /* verilator lint_off BLKSEQ */
  always #5 clk = ~clk;
  /* verilator lint_on BLKSEQ */

  simt_mpw_wrapper #(.USE_IHP_IMEM(0), .USE_IHP_DATA_SRAM(0)) dut (
    .user_clock_i(clk), .user_reset_n_i(reset_n),
    .wbs_cyc_i(cyc), .wbs_stb_i(stb), .wbs_we_i(we), .wbs_adr_i(adr),
    .wbs_dat_i(wdata), .wbs_sel_i(sel), .wbs_ack_o(ack), .wbs_err_o(err),
    .wbs_dat_o(rdata), .test_mode_i(test_mode), .scan_enable_i(scan_enable),
    .scan_in_i(scan_in), .scan_out_o(scan_out), .bist_start_i(bist_start),
    .bist_active_o(bist_active), .bist_done_o(bist_done),
    .bist_fail_o(bist_fail), .bist_fail_shared_o(bist_fail_shared),
    .bist_fail_address_o(bist_fail_address), .irq_done_o(irq_done),
    .irq_fault_o(irq_fault));

  function automatic logic [31:0] enc(input opcode_t op);
    return {op, 26'b0};
  endfunction

  task automatic wr(input logic [7:0] address, input logic [31:0] data);
    @(negedge clk);
    cyc = 1; stb = 1; we = 1; adr = address; wdata = data; sel = 4'hf;
    #1;
    if (!ack || err) $fatal(1, "Wishbone write address=%h ack=%b err=%b",
                            address, ack, err);
    @(negedge clk);
    cyc = 0; stb = 0; we = 0;
    checks++;
  endtask

  task automatic rd(input logic [7:0] address, output logic [31:0] data);
    @(negedge clk);
    cyc = 1; stb = 1; we = 0; adr = address; sel = 4'hf;
    #1;
    if (!ack || err) $fatal(1, "Wishbone read address=%h ack=%b err=%b",
                            address, ack, err);
    data = rdata;
    @(negedge clk);
    cyc = 0; stb = 0;
    checks++;
  endtask

  task automatic program_word(input logic [31:0] instruction);
    wr(8'h10, 0);
    wr(8'h14, instruction);
  endtask

  task automatic wait_irq(input logic expect_fault);
    repeat (300) begin
      @(posedge clk);
      if (irq_done || irq_fault) break;
    end
    if (expect_fault) begin
      if (!irq_fault || irq_done) $fatal(1, "expected fault interrupt");
    end else if (!irq_done || irq_fault) begin
      $fatal(1, "expected done interrupt");
    end
    checks++;
  endtask

  initial begin
    logic [31:0] value;
    repeat (3) @(posedge clk);
    reset_n = 1;
    repeat (3) @(posedge clk);

    scan_enable = 1;
    scan_in = 1; #1;
    if (!scan_out) $fatal(1, "scan-one boundary bypass");
    scan_in = 0; #1;
    if (scan_out) $fatal(1, "scan-zero boundary bypass");
    scan_enable = 0;
    checks += 2;

    rd(8'h3c, value);
    if (value != 32'h53494d54) $fatal(1, "wrapper build ID");

    program_word(enc(OP_EXIT));
    wr(8'h0c, 1);
    wr(8'h00, 1);
    wait_irq(0);
    wr(8'h00, 2);
    repeat (3) @(posedge clk);
    if (irq_done || irq_fault) $fatal(1, "interrupts did not clear");

    // A predicated barrier encoding is reserved and faults at execution.
    program_word(32'h72000000);
    wr(8'h0c, 1);
    wr(8'h00, 1);
    wait_irq(1);
    wr(8'h00, 2);

    repeat (2) @(posedge clk);
    test_mode = 1;
    repeat (2) @(posedge clk);
    @(negedge clk);
    cyc = 1; stb = 1; we = 0; adr = 8'h3c; sel = 4'hf;
    #1;
    if (ack) $fatal(1, "Wishbone acknowledged during test mode");
    cyc = 0; stb = 0;
    checks++;

    @(negedge clk);
    bist_start = 1;
    @(negedge clk);
    bist_start = 0;
    bist_cycles = 0;
    repeat (100000) begin
      @(posedge clk);
      bist_cycles++;
      if (bist_done) break;
    end
    if (!bist_done || bist_active || bist_fail)
      $fatal(1, "wrapper BIST failed done=%b active=%b fail=%b space=%b address=%h",
             bist_done, bist_active, bist_fail, bist_fail_shared,
             bist_fail_address);
    if (bist_cycles < 6 * (1024 + 512))
      $fatal(1, "wrapper BIST completed too early cycles=%0d", bist_cycles);
    checks++;

    $display("PASS tb_mpw_wrapper checks=%0d bist_cycles=%0d", checks,
             bist_cycles);
    $finish;
  end
endmodule
