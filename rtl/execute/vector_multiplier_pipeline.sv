module vector_multiplier_pipeline (
  input  logic                                            clk,
  input  logic                                            rst,
  input  logic                                            flush_i,

  input  logic                                            issue_valid_i,
  output logic                                            issue_ready_o,
  input  logic [simt_gpu_pkg::KERNEL_EPOCH_WIDTH-1:0]     epoch_i,
  input  logic [simt_gpu_pkg::WARP_ID_WIDTH-1:0]          warp_id_i,
  input  logic [simt_gpu_pkg::INSTRUCTION_SEQUENCE_WIDTH-1:0]
                                                            sequence_number_i,
  input  logic [31:0]                                     pc_i,
  input  logic [31:0]                                     instruction_i,
  input  simt_gpu_pkg::lane_mask_t                        active_mask_i,
  input  simt_gpu_pkg::lane_mask_t                        write_mask_i,
  input  logic [simt_gpu_pkg::REG_INDEX_WIDTH-1:0]        gpr_dst_i,
  input  simt_gpu_pkg::word_t [simt_gpu_pkg::LANES-1:0]  src_a_i,
  input  simt_gpu_pkg::word_t [simt_gpu_pkg::LANES-1:0]  src_b_i,

  output logic                                            completion_valid_o,
  input  logic                                            completion_ready_i,
  output simt_gpu_pkg::completion_record_t                completion_o,
  output logic [1:0]                                      queue_occupancy_o,
  output logic [simt_gpu_pkg::MULTIPLIER_LATENCY-1:0]     stage_valid_o
);
  import simt_gpu_pkg::*;

  completion_record_t stage_q [MULTIPLIER_LATENCY];
  logic [MULTIPLIER_LATENCY-1:0] valid_q;
  logic [MULTIPLIER_LATENCY-1:0] advance;
  completion_record_t issue_record;
  logic queue_input_ready;

  always_comb begin
    issue_record = '0;
    issue_record.valid = issue_valid_i;
    issue_record.epoch = epoch_i;
    issue_record.warp_id = warp_id_i;
    issue_record.sequence_number = sequence_number_i;
    issue_record.pc = pc_i;
    issue_record.instruction = instruction_i;
    issue_record.active_mask = active_mask_i;
    issue_record.write_mask = write_mask_i;
    issue_record.writes_gpr = 1'b1;
    issue_record.gpr_dst = gpr_dst_i;
    issue_record.gpr_mask = write_mask_i;
    issue_record.clear_gpr_pending = 1'b1;
    issue_record.completion_class = COMPLETION_MULTIPLIER;
    issue_record.status = COMPLETION_STATUS_OK;
    for (int unsigned lane = 0; lane < LANES; lane++)
      issue_record.gpr_data[lane] = src_a_i[lane] * src_b_i[lane];

    advance[MULTIPLIER_LATENCY-1] =
      !valid_q[MULTIPLIER_LATENCY-1] || queue_input_ready;
    for (int stage = MULTIPLIER_LATENCY-2; stage >= 0; stage--)
      advance[stage] = !valid_q[stage] || advance[stage+1];
    issue_ready_o = advance[0];
    stage_valid_o = valid_q;
  end

  always_ff @(posedge clk) begin
    if (rst || flush_i) begin
      valid_q <= '0;
      for (int unsigned stage = 0; stage < MULTIPLIER_LATENCY; stage++)
        stage_q[stage] <= '0;
    end else begin
      for (int stage = MULTIPLIER_LATENCY-1; stage > 0; stage--) begin
        if (advance[stage]) begin
          valid_q[stage] <= valid_q[stage-1];
          if (valid_q[stage-1])
            stage_q[stage] <= stage_q[stage-1];
        end
      end
      if (advance[0]) begin
        valid_q[0] <= issue_valid_i;
        if (issue_valid_i)
          stage_q[0] <= issue_record;
      end
    end
  end

  completion_queue queue_u (
    .clk(clk), .rst(rst), .flush_i(flush_i),
    .completion_valid_i(valid_q[MULTIPLIER_LATENCY-1]),
    .completion_ready_o(queue_input_ready),
    .completion_i(stage_q[MULTIPLIER_LATENCY-1]),
    .completion_valid_o(completion_valid_o),
    .completion_ready_i(completion_ready_i),
    .completion_o(completion_o),
    .occupancy_o(queue_occupancy_o)
  );

`ifndef SYNTHESIS
  initial assert (MULTIPLIER_LATENCY == 3);
  property p_payload_stable_while_blocked;
    @(posedge clk) disable iff (rst || flush_i)
      valid_q[MULTIPLIER_LATENCY-1] && !queue_input_ready
      |=> valid_q[MULTIPLIER_LATENCY-1] &&
          $stable(stage_q[MULTIPLIER_LATENCY-1]);
  endproperty
  assert property (p_payload_stable_while_blocked);
`endif
endmodule
