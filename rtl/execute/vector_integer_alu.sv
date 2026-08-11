module vector_integer_alu #(
  parameter int unsigned LANES = 8,
  parameter int unsigned XLEN = 32
) (
  input  logic                         valid_i,
  input  simt_isa_pkg::opcode_t        opcode_i,
  input  logic [LANES-1:0]             active_mask_i,
  input  logic [LANES-1:0]             predicate_mask_i,
  input  logic                         predicate_invert_i,
  input  logic                         guard_exec_i,
  input  logic                         writes_gpr_i,
  input  logic                         writes_pred_i,
  input  logic [LANES-1:0][XLEN-1:0]   src_a_i,
  input  logic [LANES-1:0][XLEN-1:0]   src_b_i,
  input  logic signed [9:0]            imm_i,
  input  logic [LANES-1:0][XLEN-1:0]   special_i,
  output logic [LANES-1:0]             execute_mask_o,
  output logic [LANES-1:0]             gpr_write_mask_o,
  output logic [LANES-1:0]             pred_write_mask_o,
  output logic [LANES-1:0][XLEN-1:0]   result_o,
  output logic [LANES-1:0]             predicate_result_o,
  output logic [LANES-1:0]             branch_condition_o,
  output logic [LANES-1:0][XLEN-1:0]   memory_address_o,
  output logic [LANES-1:0][XLEN-1:0]   store_data_o,
  output logic                         unsupported_operation_o
);
  logic [LANES-1:0] selected_predicate;
  logic [LANES-1:0] lane_supported;

  always_comb begin
    selected_predicate = predicate_mask_i ^ {LANES{predicate_invert_i}};
    execute_mask_o = '0;
    if (valid_i)
      execute_mask_o = active_mask_i &
                       ({LANES{!guard_exec_i}} | selected_predicate);
    gpr_write_mask_o = execute_mask_o & {LANES{writes_gpr_i}};
    pred_write_mask_o = execute_mask_o & {LANES{writes_pred_i}};
  end

  always_comb unsupported_operation_o = valid_i && !(&lane_supported);

  for (genvar lane = 0; lane < LANES; lane++) begin : gen_lanes
    integer_lane #(.XLEN(XLEN)) lane_u (
      .opcode_i(opcode_i),
      .active_i(execute_mask_o[lane]),
      .predicate_i(selected_predicate[lane]),
      .src_a_i(src_a_i[lane]),
      .src_b_i(src_b_i[lane]),
      .imm_i(imm_i),
      .special_i(special_i[lane]),
      .result_o(result_o[lane]),
      .predicate_result_o(predicate_result_o[lane]),
      .branch_condition_o(branch_condition_o[lane]),
      .memory_address_o(memory_address_o[lane]),
      .store_data_o(store_data_o[lane]),
      .operation_supported_o(lane_supported[lane])
    );
  end

`ifndef SYNTHESIS
  always_comb begin
    assert ((gpr_write_mask_o & ~execute_mask_o) == '0)
      else $error("GPR write enabled for a non-executing lane");
    assert ((pred_write_mask_o & ~execute_mask_o) == '0)
      else $error("predicate write enabled for a non-executing lane");
  end
`endif
endmodule
