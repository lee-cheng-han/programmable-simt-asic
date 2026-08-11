module architectural_writeback (
  input  logic                                            clk,
  input  logic                                            rst,
  input  logic                                            fatal_i,
  input  logic [simt_gpu_pkg::KERNEL_EPOCH_WIDTH-1:0]     current_epoch_i,

  input  logic                                            completion_valid_i,
  output logic                                            completion_ready_o,
  input  simt_gpu_pkg::completion_record_t                completion_i,

  output logic                                            commit_valid_o,
  input  logic                                            commit_ready_i,
  output simt_gpu_pkg::completion_record_t                commit_o,
  output logic                                            stale_cancel_o,

  output logic                                            gpr_write_valid_o,
  output logic [simt_gpu_pkg::WARP_ID_WIDTH-1:0]          gpr_write_warp_o,
  output logic [simt_gpu_pkg::REG_INDEX_WIDTH-1:0]        gpr_write_reg_o,
  output simt_gpu_pkg::lane_mask_t                        gpr_write_mask_o,
  output simt_gpu_pkg::word_t [simt_gpu_pkg::LANES-1:0]  gpr_write_data_o,

  output logic                                            pred_write_valid_o,
  output logic [simt_gpu_pkg::WARP_ID_WIDTH-1:0]          pred_write_warp_o,
  output logic [simt_gpu_pkg::PRED_INDEX_WIDTH-1:0]       pred_write_pred_o,
  output simt_gpu_pkg::lane_mask_t                        pred_write_mask_o,
  output simt_gpu_pkg::lane_mask_t                        pred_write_data_o,

  output logic                                            clear_gpr_valid_o,
  output logic                                            clear_pred_valid_o,
  output logic [simt_gpu_pkg::KERNEL_EPOCH_WIDTH-1:0]     clear_epoch_o,
  output logic [simt_gpu_pkg::WARP_ID_WIDTH-1:0]          clear_warp_o,
  output logic [simt_gpu_pkg::INSTRUCTION_SEQUENCE_WIDTH-1:0]
                                                            clear_sequence_o,
  output logic [simt_gpu_pkg::REG_INDEX_WIDTH-1:0]        clear_gpr_o,
  output logic [simt_gpu_pkg::PRED_INDEX_WIDTH-1:0]       clear_pred_o
);
  import simt_gpu_pkg::*;

  logic epoch_match;
  logic commit_fire;
  logic writes_allowed;

  assign epoch_match = completion_i.epoch == current_epoch_i;
  assign commit_valid_o = completion_valid_i && epoch_match && !fatal_i;
  assign stale_cancel_o = completion_valid_i && !epoch_match && !fatal_i;
  assign completion_ready_o = !fatal_i && (!epoch_match || commit_ready_i);
  assign commit_fire = commit_valid_o && commit_ready_i;
  assign writes_allowed = completion_i.status == COMPLETION_STATUS_OK;

  always_comb begin
    commit_o = completion_i;

    gpr_write_valid_o = commit_fire && writes_allowed &&
                        completion_i.writes_gpr && (|completion_i.gpr_mask);
    gpr_write_warp_o = completion_i.warp_id;
    gpr_write_reg_o = completion_i.gpr_dst;
    gpr_write_mask_o = completion_i.gpr_mask;
    gpr_write_data_o = completion_i.gpr_data;

    pred_write_valid_o = commit_fire && writes_allowed &&
                         completion_i.writes_pred && (|completion_i.pred_mask);
    pred_write_warp_o = completion_i.warp_id;
    pred_write_pred_o = completion_i.pred_dst;
    pred_write_mask_o = completion_i.pred_mask;
    pred_write_data_o = completion_i.pred_data;

    clear_gpr_valid_o = commit_fire && completion_i.clear_gpr_pending;
    clear_pred_valid_o = commit_fire && completion_i.clear_pred_pending;
    clear_epoch_o = completion_i.epoch;
    clear_warp_o = completion_i.warp_id;
    clear_sequence_o = completion_i.sequence_number;
    clear_gpr_o = completion_i.gpr_dst;
    clear_pred_o = completion_i.pred_dst;
  end

`ifndef SYNTHESIS
  property p_fatal_suppresses_architectural_commit;
    @(posedge clk) disable iff (rst)
      fatal_i |-> !(commit_valid_o || gpr_write_valid_o ||
                    pred_write_valid_o || clear_gpr_valid_o ||
                    clear_pred_valid_o);
  endproperty
  assert property (p_fatal_suppresses_architectural_commit)
    else $error("fatal priority failed to suppress architectural commit");

  property p_stale_completion_has_no_side_effect;
    @(posedge clk) disable iff (rst)
      stale_cancel_o |-> !(commit_valid_o || gpr_write_valid_o ||
                           pred_write_valid_o || clear_gpr_valid_o ||
                           clear_pred_valid_o);
  endproperty
  assert property (p_stale_completion_has_no_side_effect)
    else $error("stale completion produced an architectural side effect");
`endif
endmodule
