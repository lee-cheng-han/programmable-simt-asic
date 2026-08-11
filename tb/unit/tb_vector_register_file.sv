module tb_vector_register_file;
  localparam int unsigned LANES = 8;
  localparam int unsigned WARPS = 4;
  localparam int unsigned REGS = 16;
  localparam int unsigned XLEN = 32;

  logic clk = 1'b0;
  logic rst;
  logic read_valid;
  logic [1:0] read_warp;
  logic [3:0] read_ra, read_rb;
  logic [LANES-1:0][XLEN-1:0] read_a, read_b;
  logic write_valid;
  logic [1:0] write_warp;
  logic [3:0] write_reg;
  logic [LANES-1:0] write_mask;
  logic [LANES-1:0][XLEN-1:0] write_data;
  logic [LANES-1:0][XLEN-1:0] expected [WARPS][REGS];
  int unsigned checks;

  always #5 clk <= ~clk;

  vector_register_file dut (
    .clk(clk), .rst(rst),
    .read_a_valid_i(read_valid), .read_b_valid_i(read_valid),
    .read_warp_i(read_warp),
    .read_ra_i(read_ra), .read_rb_i(read_rb),
    .read_a_o(read_a), .read_b_o(read_b),
    .write_valid_i(write_valid), .write_warp_i(write_warp),
    .write_reg_i(write_reg), .write_lane_mask_i(write_mask),
    .write_data_i(write_data)
  );

  function automatic logic [31:0] pattern(
    input int unsigned warp,
    input int unsigned reg_id,
    input int unsigned lane,
    input int unsigned salt
  );
    return 32'h4000_0000 | (warp << 20) | (reg_id << 12) | (lane << 4) | salt;
  endfunction

  task automatic drive_write(
    input int unsigned warp,
    input int unsigned reg_id,
    input logic [LANES-1:0] mask,
    input int unsigned salt
  );
    @(negedge clk);
    write_valid = 1'b1;
    write_warp = 2'(warp);
    write_reg = 4'(reg_id);
    write_mask = mask;
    for (int unsigned lane = 0; lane < LANES; lane++) begin
      write_data[lane] = pattern(warp, reg_id, lane, salt);
      if (mask[lane]) expected[warp][reg_id][lane] = write_data[lane];
    end
    @(posedge clk);
    #1;
    write_valid = 1'b0;
    write_mask = '0;
  endtask

  task automatic check_pair(
    input int unsigned warp,
    input int unsigned reg_a,
    input int unsigned reg_b
  );
    @(negedge clk);
    read_valid = 1'b1;
    read_warp = 2'(warp);
    read_ra = 4'(reg_a);
    read_rb = 4'(reg_b);
    #1;
    checks++;
    if (read_a !== expected[warp][reg_a])
      $fatal(1, "source A mismatch warp=%0d reg=%0d", warp, reg_a);
    if (read_b !== expected[warp][reg_b])
      $fatal(1, "source B mismatch warp=%0d reg=%0d", warp, reg_b);
  endtask

  initial begin
    rst = 1'b1;
    read_valid = 1'b0;
    read_warp = '0;
    read_ra = '0;
    read_rb = '0;
    write_valid = 1'b0;
    write_warp = '0;
    write_reg = '0;
    write_mask = '0;
    write_data = '0;
    checks = 0;

    repeat (2) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    // Initialize and then read every architectural location.
    for (int unsigned warp = 0; warp < WARPS; warp++)
      for (int unsigned reg_id = 0; reg_id < REGS; reg_id++)
        drive_write(warp, reg_id, '1, 1);

    for (int unsigned warp = 0; warp < WARPS; warp++)
      for (int unsigned reg_id = 0; reg_id < REGS; reg_id++)
        check_pair(warp, reg_id, (reg_id + 7) % REGS);

    // Alternating masks prove that inactive lanes preserve their old values.
    drive_write(2, 5, 8'b0101_1010, 2);
    check_pair(2, 5, 5);
    drive_write(2, 5, 8'b1010_0101, 3);
    check_pair(2, 5, 5);

    // Same-cycle forwarding is checked before the write clock edge. Both read
    // ports target the writeback register; only masked lanes may see new data.
    @(negedge clk);
    read_valid = 1'b1;
    read_warp = 2'd1;
    read_ra = 4'd9;
    read_rb = 4'd9;
    write_valid = 1'b1;
    write_warp = 2'd1;
    write_reg = 4'd9;
    write_mask = 8'b1001_0110;
    for (int unsigned lane = 0; lane < LANES; lane++)
      write_data[lane] = pattern(1, 9, lane, 4);
    #1;
    for (int unsigned lane = 0; lane < LANES; lane++) begin
      if (write_mask[lane]) begin
        if (read_a[lane] !== write_data[lane] || read_b[lane] !== write_data[lane])
          $fatal(1, "forwarding mismatch lane=%0d", lane);
        expected[1][9][lane] = write_data[lane];
      end else if (read_a[lane] !== expected[1][9][lane] ||
                   read_b[lane] !== expected[1][9][lane]) begin
        $fatal(1, "unmasked forwarding changed lane=%0d", lane);
      end
      checks++;
    end
    @(posedge clk);
    #1;
    write_valid = 1'b0;
    write_mask = '0;
    check_pair(1, 9, 9);

    // Forwarding comparisons must include warp, register, valid, and lane mask.
    @(negedge clk);
    write_valid = 1'b1;
    write_warp = 2'd3;
    write_reg = 4'd8;
    write_mask = '1;
    for (int unsigned lane = 0; lane < LANES; lane++)
      write_data[lane] = pattern(3, 8, lane, 5);
    read_valid = 1'b1;
    read_warp = 2'd0;
    read_ra = 4'd8;
    read_rb = 4'd8;
    #1;
    if (read_a !== expected[0][8] || read_b !== expected[0][8])
      $fatal(1, "forwarding ignored warp ID");
    checks++;
    @(posedge clk);
    #1;
    write_valid = 1'b0;

    read_valid = 1'b0;
    #1;
    if (read_a !== '0 || read_b !== '0)
      $fatal(1, "invalid read must return deterministic zero");
    checks++;

    $display("PASS tb_vector_register_file checks=%0d", checks);
    $finish;
  end
endmodule
