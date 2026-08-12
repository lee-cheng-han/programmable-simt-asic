module architectural_writeback_formal (
  input logic fatal_i,
  input logic [simt_gpu_pkg::KERNEL_EPOCH_WIDTH-1:0] current_epoch_i,
  input logic completion_valid_i,
  input simt_gpu_pkg::completion_record_t completion_i,
  input logic commit_ready_i
);
  import simt_gpu_pkg::*;
  logic clk=1'b0,rst=1'b0;
  logic completion_ready_o,commit_valid_o,stale_cancel_o;
  completion_record_t commit_o;
  logic gpr_write_valid_o,pred_write_valid_o;
  logic [WARP_ID_WIDTH-1:0] gpr_write_warp_o,pred_write_warp_o,clear_warp_o;
  logic [REG_INDEX_WIDTH-1:0] gpr_write_reg_o,clear_gpr_o;
  logic [PRED_INDEX_WIDTH-1:0] pred_write_pred_o,clear_pred_o;
  lane_mask_t gpr_write_mask_o,pred_write_mask_o,pred_write_data_o;
  word_t [LANES-1:0] gpr_write_data_o;
  logic clear_gpr_valid_o,clear_pred_valid_o;
  logic [KERNEL_EPOCH_WIDTH-1:0] clear_epoch_o;
  logic [INSTRUCTION_SEQUENCE_WIDTH-1:0] clear_sequence_o;

  architectural_writeback dut (.*);

  always_comb begin
    if(fatal_i) begin
      assert(!completion_ready_o && !commit_valid_o && !stale_cancel_o);
      assert(!gpr_write_valid_o && !pred_write_valid_o);
      assert(!clear_gpr_valid_o && !clear_pred_valid_o);
    end
    if(!fatal_i && completion_valid_i && completion_i.epoch!=current_epoch_i) begin
      assert(stale_cancel_o && completion_ready_o && !commit_valid_o);
      assert(!gpr_write_valid_o && !pred_write_valid_o);
      assert(!clear_gpr_valid_o && !clear_pred_valid_o);
    end
    if(!fatal_i && completion_valid_i && completion_i.epoch==current_epoch_i) begin
      assert(commit_valid_o);
      assert(completion_ready_o==commit_ready_i);
    end
    assert(!gpr_write_valid_o || (commit_valid_o && commit_ready_i));
    assert(!pred_write_valid_o || (commit_valid_o && commit_ready_i));
    assert(!clear_gpr_valid_o || (commit_valid_o && commit_ready_i));
    assert(!clear_pred_valid_o || (commit_valid_o && commit_ready_i));
  end
endmodule
