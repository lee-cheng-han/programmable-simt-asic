module tb_alu_completion_writeback;
  import simt_gpu_pkg::*;

  logic clk = 1'b0;
  logic rst;
  logic flush;
  logic result_valid;
  logic result_ready;
  logic [KERNEL_EPOCH_WIDTH-1:0] epoch;
  logic [WARP_ID_WIDTH-1:0] warp_id;
  logic [INSTRUCTION_SEQUENCE_WIDTH-1:0] sequence_number;
  logic [31:0] pc;
  logic [31:0] instruction;
  lane_mask_t active_mask;
  lane_mask_t write_mask;
  logic writes_gpr;
  logic [REG_INDEX_WIDTH-1:0] gpr_dst;
  lane_mask_t gpr_mask;
  word_t [LANES-1:0] gpr_data;
  logic writes_pred;
  logic [PRED_INDEX_WIDTH-1:0] pred_dst;
  lane_mask_t pred_mask;
  lane_mask_t pred_data;
  logic completion_valid;
  logic completion_ready;
  completion_record_t completion;
  logic [1:0] occupancy;
  logic fatal;
  logic [KERNEL_EPOCH_WIDTH-1:0] current_epoch;
  logic commit_valid;
  logic commit_ready;
  completion_record_t committed;
  logic stale_cancel;
  logic gpr_write_valid;
  logic [WARP_ID_WIDTH-1:0] gpr_write_warp;
  logic [REG_INDEX_WIDTH-1:0] gpr_write_reg;
  lane_mask_t gpr_write_mask;
  word_t [LANES-1:0] gpr_write_data;
  logic pred_write_valid;
  logic [WARP_ID_WIDTH-1:0] pred_write_warp;
  logic [PRED_INDEX_WIDTH-1:0] pred_write_pred;
  lane_mask_t pred_write_mask;
  lane_mask_t pred_write_data;
  logic clear_gpr_valid;
  logic clear_pred_valid;
  logic [KERNEL_EPOCH_WIDTH-1:0] clear_epoch;
  logic [WARP_ID_WIDTH-1:0] clear_warp;
  logic [INSTRUCTION_SEQUENCE_WIDTH-1:0] clear_sequence;
  logic [REG_INDEX_WIDTH-1:0] clear_gpr;
  logic [PRED_INDEX_WIDTH-1:0] clear_pred;
  int unsigned checks;

  always #5 clk <= ~clk;

  alu_completion_stage stage_u (
    .clk(clk), .rst(rst), .flush_i(flush),
    .result_valid_i(result_valid), .result_ready_o(result_ready),
    .epoch_i(epoch), .warp_id_i(warp_id),
    .sequence_number_i(sequence_number), .pc_i(pc),
    .instruction_i(instruction), .active_mask_i(active_mask),
    .write_mask_i(write_mask), .writes_gpr_i(writes_gpr),
    .gpr_dst_i(gpr_dst), .gpr_mask_i(gpr_mask), .gpr_data_i(gpr_data),
    .writes_pred_i(writes_pred), .pred_dst_i(pred_dst),
    .pred_mask_i(pred_mask), .pred_data_i(pred_data),
    .completion_valid_o(completion_valid),
    .completion_ready_i(completion_ready), .completion_o(completion),
    .occupancy_o(occupancy)
  );

  architectural_writeback writeback_u (
    .clk(clk), .rst(rst),
    .fatal_i(fatal), .current_epoch_i(current_epoch),
    .completion_valid_i(completion_valid),
    .completion_ready_o(completion_ready), .completion_i(completion),
    .commit_valid_o(commit_valid), .commit_ready_i(commit_ready),
    .commit_o(committed), .stale_cancel_o(stale_cancel),
    .gpr_write_valid_o(gpr_write_valid),
    .gpr_write_warp_o(gpr_write_warp), .gpr_write_reg_o(gpr_write_reg),
    .gpr_write_mask_o(gpr_write_mask), .gpr_write_data_o(gpr_write_data),
    .pred_write_valid_o(pred_write_valid),
    .pred_write_warp_o(pred_write_warp),
    .pred_write_pred_o(pred_write_pred),
    .pred_write_mask_o(pred_write_mask), .pred_write_data_o(pred_write_data),
    .clear_gpr_valid_o(clear_gpr_valid),
    .clear_pred_valid_o(clear_pred_valid), .clear_epoch_o(clear_epoch),
    .clear_warp_o(clear_warp), .clear_sequence_o(clear_sequence),
    .clear_gpr_o(clear_gpr), .clear_pred_o(clear_pred)
  );

  task automatic drive_result(
    input logic [KERNEL_EPOCH_WIDTH-1:0] record_epoch,
    input logic [INSTRUCTION_SEQUENCE_WIDTH-1:0] record_sequence,
    input logic record_writes_gpr,
    input logic record_writes_pred,
    input lane_mask_t record_gpr_mask,
    input lane_mask_t record_pred_mask
  );
    epoch = record_epoch;
    warp_id = record_sequence[WARP_ID_WIDTH-1:0];
    sequence_number = record_sequence;
    pc = 32'h0000_0400 | word_t'(record_sequence);
    instruction = 32'h0400_0000 | word_t'(record_sequence);
    active_mask = 8'hf3;
    write_mask = record_gpr_mask | record_pred_mask;
    writes_gpr = record_writes_gpr;
    gpr_dst = record_sequence[REG_INDEX_WIDTH-1:0];
    gpr_mask = record_gpr_mask;
    for (int unsigned lane = 0; lane < LANES; lane++)
      gpr_data[lane] = 32'h6000_0000 |
                       (word_t'(record_sequence) << 8) | word_t'(lane);
    writes_pred = record_writes_pred;
    pred_dst = record_sequence[PRED_INDEX_WIDTH-1:0];
    pred_mask = record_pred_mask;
    pred_data = 8'ha6;
  endtask

  task automatic enqueue_result;
    @(negedge clk);
    if (!result_ready) $fatal(1, "ALU completion stage not ready");
    result_valid = 1'b1;
    @(posedge clk);
    #1;
    result_valid = 1'b0;
  endtask

  initial begin
    rst = 1'b1;
    flush = 1'b0;
    result_valid = 1'b0;
    fatal = 1'b0;
    current_epoch = 6'h15;
    commit_ready = 1'b0;
    checks = 0;
    drive_result(6'h15, 16'h1235, 1'b1, 1'b0, 8'hb6, 8'h00);

    if (SIMT_STACK_DEPTH != 8 || SCRATCHPAD_BYTES != 4096 ||
        SHMEM_BYTES != 2048 || MAX_MEMORY_OPS != 4 ||
        MULTIPLIER_LATENCY != 3)
      $fatal(1, "unexpected package configuration");

    repeat (2) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    enqueue_result();
    checks++;
    if (!completion_valid || commit_valid !== 1'b1 || occupancy != 1 ||
        completion.valid !== 1'b1 || completion.epoch != 6'h15 ||
        completion.sequence_number != 16'h1235 ||
        completion.completion_class != COMPLETION_ALU ||
        completion.status != COMPLETION_STATUS_OK ||
        !completion.clear_gpr_pending || completion.clear_pred_pending)
      $fatal(1, "canonical ALU completion record mismatch");

    repeat (2) begin
      @(posedge clk);
      #1;
      checks++;
      if (!commit_valid || gpr_write_valid || clear_gpr_valid || occupancy != 1)
        $fatal(1, "stalled writeback changed architectural state");
    end

    @(negedge clk);
    commit_ready = 1'b1;
    #1;
    checks++;
    if (!commit_valid || !gpr_write_valid || pred_write_valid ||
        !clear_gpr_valid || clear_pred_valid || gpr_write_warp != 2'd1 ||
        gpr_write_reg != 4'h5 || gpr_write_mask != 8'hb6 ||
        clear_epoch != 6'h15 || clear_warp != 2'd1 ||
        clear_sequence != 16'h1235 || clear_gpr != 4'h5 ||
        committed !== completion)
      $fatal(1, "GPR architectural commit mismatch");
    for (int unsigned lane = 0; lane < LANES; lane++) begin
      if (gpr_write_data[lane] !=
          (32'h6000_0000 | (32'h0000_1235 << 8) | word_t'(lane)))
        $fatal(1, "GPR write data mismatch lane=%0d", lane);
    end
    @(posedge clk);
    #1;
    commit_ready = 1'b0;

    // An empty predicate mask still retires and clears its pending bit.
    drive_result(6'h15, 16'h2202, 1'b0, 1'b1, 8'h00, 8'h00);
    enqueue_result();
    @(negedge clk);
    commit_ready = 1'b1;
    #1;
    checks++;
    if (!commit_valid || pred_write_valid || !clear_pred_valid ||
        clear_pred != 2'd2 || pred_write_warp != 2'd2 ||
        pred_write_pred != 2'd2 || pred_write_mask != 0 ||
        pred_write_data != 8'ha6)
      $fatal(1, "empty-mask predicate retirement mismatch");
    @(posedge clk);
    #1;
    commit_ready = 1'b0;

    // A stale completion drains as cancellation without waiting for commit.
    drive_result(6'h14, 16'h3303, 1'b1, 1'b0, 8'hff, 8'h00);
    enqueue_result();
    @(negedge clk);
    #1;
    checks++;
    if (!stale_cancel || !completion_ready || commit_valid ||
        gpr_write_valid || clear_gpr_valid)
      $fatal(1, "stale completion cancellation mismatch");
    @(posedge clk);
    #1;
    checks++;
    if (completion_valid || occupancy != 0)
      $fatal(1, "stale completion did not drain");

    // Fatal priority suppresses a ready writeback in the assertion cycle.
    drive_result(6'h15, 16'h4404, 1'b1, 1'b0, 8'hff, 8'h00);
    enqueue_result();
    @(negedge clk);
    commit_ready = 1'b1;
    fatal = 1'b1;
    #1;
    checks++;
    if (completion_ready || commit_valid || gpr_write_valid ||
        clear_gpr_valid || stale_cancel)
      $fatal(1, "fatal priority did not suppress writeback");
    @(posedge clk);
    #1;
    checks++;
    if (!completion_valid || occupancy != 1)
      $fatal(1, "fatal cycle consumed completion");

    @(negedge clk);
    flush = 1'b1;
    @(posedge clk);
    #1;
    flush = 1'b0;
    fatal = 1'b0;
    commit_ready = 1'b0;
    checks++;
    if (completion_valid || occupancy != 0)
      $fatal(1, "fatal flush did not cancel completion");

    $display("PASS tb_alu_completion_writeback checks=%0d", checks);
    $finish;
  end
endmodule
