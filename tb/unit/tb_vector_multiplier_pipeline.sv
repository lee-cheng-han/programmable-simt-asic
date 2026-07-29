module tb_vector_multiplier_pipeline;
  import simt_gpu_pkg::*;
  logic clk = 0;
  logic rst, flush, issue_valid, issue_ready, completion_valid, completion_ready;
  logic [KERNEL_EPOCH_WIDTH-1:0] epoch;
  logic [WARP_ID_WIDTH-1:0] warp;
  logic [INSTRUCTION_SEQUENCE_WIDTH-1:0] sequence_number;
  logic [31:0] pc, instruction;
  lane_mask_t active_mask, write_mask;
  logic [REG_INDEX_WIDTH-1:0] dst;
  word_t [LANES-1:0] src_a, src_b;
  /* verilator lint_off UNUSEDSIGNAL */
  completion_record_t completion;
  /* verilator lint_on UNUSEDSIGNAL */
  logic [1:0] occupancy;
  logic [MULTIPLIER_LATENCY-1:0] stage_valid;
  int unsigned accepted, retired, checks;

  /* verilator lint_off BLKSEQ */
  always #5 clk = ~clk;
  /* verilator lint_on BLKSEQ */
  initial begin
    repeat (200) @(posedge clk);
    $fatal(1, "multiplier test timed out accepted=%0d retired=%0d occupancy=%0d stages=%b",
           accepted, retired, occupancy, stage_valid);
  end
  vector_multiplier_pipeline dut (.*,
    .flush_i(flush), .issue_valid_i(issue_valid), .issue_ready_o(issue_ready),
    .epoch_i(epoch), .warp_id_i(warp), .sequence_number_i(sequence_number),
    .pc_i(pc), .instruction_i(instruction), .active_mask_i(active_mask),
    .write_mask_i(write_mask), .gpr_dst_i(dst), .src_a_i(src_a),
    .src_b_i(src_b), .completion_valid_o(completion_valid),
    .completion_ready_i(completion_ready), .completion_o(completion),
    .queue_occupancy_o(occupancy), .stage_valid_o(stage_valid));

  task automatic drive_issue(input int unsigned id);
    issue_valid = 1;
    epoch = 6'(id + 1);
    warp = 2'(id % WARPS);
    sequence_number = INSTRUCTION_SEQUENCE_WIDTH'(32'h100 + id);
    pc = 32'(id * 4);
    instruction = 32'h0300_0000 | id;
    active_mask = 8'hff;
    write_mask = 8'hf7;
    dst = 4'(id + 1);
    for (int lane = 0; lane < LANES; lane++) begin
      src_a[lane] = 32'(id + lane + 2);
      src_b[lane] = 32'(lane + 3);
    end
  endtask

  task automatic check_completion(input int unsigned id);
    if (!completion_valid) $fatal(1, "missing completion id=%0d", id);
    if (completion.completion_class != COMPLETION_MULTIPLIER ||
        completion.epoch != 6'(id + 1) ||
        completion.warp_id != 2'(id % WARPS) ||
        completion.sequence_number !=
          INSTRUCTION_SEQUENCE_WIDTH'(32'h100 + id) ||
        completion.gpr_dst != 4'(id + 1) ||
        completion.gpr_mask != 8'hf7 ||
        !completion.clear_gpr_pending)
      $fatal(1, "completion tags mismatch id=%0d seq=%0h warp=%0d dst=%0d",
             id, completion.sequence_number, completion.warp_id,
             completion.gpr_dst);
    for (int lane = 0; lane < LANES; lane++)
      if (completion.gpr_data[lane] !=
          32'((id + lane + 2) * (lane + 3)))
        $fatal(1, "product mismatch id=%0d lane=%0d", id, lane);
    checks++;
  endtask

  initial begin
    rst = 1; flush = 0; issue_valid = 0; completion_ready = 1;
    epoch = 0; warp = 0; sequence_number = 0; pc = 0; instruction = 0;
    active_mask = 0; write_mask = 0; dst = 0; src_a = '{default:'0};
    src_b = '{default:'0};
    accepted = 0; retired = 0; checks = 0;
    repeat (2) @(posedge clk);
    rst = 0;

    // Initiation interval one: three tagged multiplies enter consecutively.
    @(negedge clk);
    for (int unsigned id = 0; id < 3; id++) begin
      drive_issue(id);
      #1;
      if (!issue_ready) $fatal(1, "pipeline rejected consecutive issue");
      @(posedge clk);
      accepted++;
      @(negedge clk);
    end
    issue_valid = 0;

    while (retired < accepted) begin
      #1;
      if (completion_valid) begin
        check_completion(retired);
        retired++;
      end
      @(posedge clk);
    end

    // Fill the pipeline and queue, then verify end-to-end backpressure.
    @(negedge clk);
    completion_ready = 0;
    for (int unsigned id = 3; id < 8; id++) begin
      drive_issue(id);
      #1;
      if (!issue_ready)
        $fatal(1, "capacity rejected id=%0d occupancy=%0d stages=%b",
               id, occupancy, stage_valid);
      @(posedge clk);
      accepted++;
      @(negedge clk);
    end
    issue_valid = 0;
    repeat (5) @(posedge clk);
    if (occupancy != 2 || issue_ready)
      $fatal(1, "full queue did not backpressure pipeline occupancy=%0d", occupancy);
    checks++;

    @(negedge clk);
    completion_ready = 1;
    while (retired < accepted) begin
      #1;
      if (completion_valid) begin
        check_completion(retired);
        retired++;
      end
      @(posedge clk);
    end

    drive_issue(9);
    @(posedge clk);
    issue_valid = 0;
    flush = 1;
    @(posedge clk);
    flush = 0;
    #1;
    if (completion_valid || occupancy != 0 || stage_valid != 0)
      $fatal(1, "flush did not cancel multiplier state");
    checks++;

    $display("PASS tb_vector_multiplier_pipeline checks=%0d", checks);
    $finish;
  end
endmodule
