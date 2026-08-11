module integer_lane #(
  parameter int unsigned XLEN = 32
) (
  input  simt_isa_pkg::opcode_t opcode_i,
  input  logic                  active_i,
  input  logic                  predicate_i,
  input  logic [XLEN-1:0]       src_a_i,
  input  logic [XLEN-1:0]       src_b_i,
  input  logic signed [9:0]     imm_i,
  input  logic [XLEN-1:0]       special_i,
  output logic [XLEN-1:0]       result_o,
  output logic                  predicate_result_o,
  output logic                  branch_condition_o,
  output logic [XLEN-1:0]       memory_address_o,
  output logic [XLEN-1:0]       store_data_o,
  output logic                  operation_supported_o
);
  import simt_isa_pkg::*;

  logic [XLEN-1:0] immediate_extended;

  always_comb begin
    unique case (opcode_i)
      OP_NOP, OP_ADD, OP_SUB, OP_MUL, OP_MIN, OP_MAX, OP_AND, OP_OR, OP_XOR,
      OP_NOT, OP_SHL, OP_SHR, OP_SAR, OP_MOV, OP_MOVI, OP_SEL,
      OP_SETP_EQ, OP_SETP_NE, OP_SETP_LT, OP_SETP_LE, OP_SETP_GT, OP_SETP_GE,
      OP_LD_G, OP_ST_G, OP_LD_S, OP_ST_S, OP_BRA, OP_SSY, OP_BAR, OP_S2R,
      OP_EXIT, OP_SYNC: operation_supported_o = 1'b1;
      default: operation_supported_o = 1'b0;
    endcase
  end

  always_comb begin
    immediate_extended = {{(XLEN-10){imm_i[9]}}, imm_i};
    result_o = '0;
    predicate_result_o = 1'b0;
    branch_condition_o = 1'b0;
    memory_address_o = '0;
    store_data_o = '0;
    if (active_i) begin
      unique case (opcode_i)
        OP_NOP, OP_SSY, OP_SYNC, OP_BAR, OP_EXIT: begin end
        OP_ADD:  result_o = src_a_i + src_b_i;
        OP_SUB:  result_o = src_a_i - src_b_i;
        OP_MUL:  result_o = src_a_i * src_b_i;
        OP_MIN:  result_o = ($signed(src_a_i) < $signed(src_b_i)) ? src_a_i : src_b_i;
        OP_MAX:  result_o = ($signed(src_a_i) > $signed(src_b_i)) ? src_a_i : src_b_i;
        OP_AND:  result_o = src_a_i & src_b_i;
        OP_OR:   result_o = src_a_i | src_b_i;
        OP_XOR:  result_o = src_a_i ^ src_b_i;
        OP_NOT:  result_o = ~src_a_i;
        OP_SHL:  result_o = src_a_i << src_b_i[4:0];
        OP_SHR:  result_o = src_a_i >> src_b_i[4:0];
        OP_SAR:  result_o = $signed(src_a_i) >>> src_b_i[4:0];
        OP_MOV:  result_o = src_a_i;
        OP_MOVI: result_o = immediate_extended;
        OP_SEL:  result_o = predicate_i ? src_a_i : src_b_i;
        OP_SETP_EQ: predicate_result_o = (src_a_i == src_b_i);
        OP_SETP_NE: predicate_result_o = (src_a_i != src_b_i);
        OP_SETP_LT: predicate_result_o = ($signed(src_a_i) < $signed(src_b_i));
        OP_SETP_LE: predicate_result_o = ($signed(src_a_i) <= $signed(src_b_i));
        OP_SETP_GT: predicate_result_o = ($signed(src_a_i) > $signed(src_b_i));
        OP_SETP_GE: predicate_result_o = ($signed(src_a_i) >= $signed(src_b_i));
        OP_LD_G, OP_ST_G, OP_LD_S, OP_ST_S: begin
          memory_address_o = src_a_i + immediate_extended;
          store_data_o = src_b_i;
        end
        OP_BRA: branch_condition_o = predicate_i;
        OP_S2R: result_o = special_i;
        default: begin end
      endcase
    end
  end
endmodule
