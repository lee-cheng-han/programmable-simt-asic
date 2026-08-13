module fatal_fault_controller (
  input logic clk, input logic rst, input logic clear_i,
  input logic host_fault_i, input logic [31:0] host_fault_pc_i,
  input logic fetch_fault_i, input logic [31:0] fetch_fault_pc_i,
  input logic illegal_fault_i, input logic [31:0] illegal_fault_pc_i,
  input logic unsupported_fault_i, input logic [31:0] unsupported_fault_pc_i,
  input logic memory_fault_i, input simt_gpu_pkg::fault_code_t memory_fault_code_i,
  input logic [31:0] memory_fault_pc_i,
  input logic control_fault_i,
  input simt_gpu_pkg::fault_code_t control_fault_code_i,
  input logic [31:0] control_fault_pc_i,
  output logic fatal_now_o, output logic fault_valid_o,
  output simt_gpu_pkg::fault_code_t fault_code_o,
  output logic [31:0] fault_pc_o,
  output logic [5:0] simultaneous_causes_o
);
  import simt_gpu_pkg::*;
  fault_code_t selected_code;
  logic [31:0] selected_pc;
  logic [5:0] causes;
  logic fault_valid_q; fault_code_t fault_code_q; logic [31:0] fault_pc_q;
  logic [5:0] causes_q;

  always_comb begin
    causes = {host_fault_i, fetch_fault_i, illegal_fault_i, memory_fault_i,
              control_fault_i, unsupported_fault_i};
    selected_code = FAULT_NONE; selected_pc = '0;
    if (host_fault_i) begin selected_code = FAULT_IMEM_WRITE_WHILE_BUSY;
      selected_pc = host_fault_pc_i; end
    else if (fetch_fault_i) begin selected_code = FAULT_FETCH_PC_RANGE;
      selected_pc = fetch_fault_pc_i; end
    else if (illegal_fault_i) begin selected_code = FAULT_ILLEGAL_INSTRUCTION;
      selected_pc = illegal_fault_pc_i; end
    else if (memory_fault_i) begin selected_code = memory_fault_code_i;
      selected_pc = memory_fault_pc_i; end
    else if (control_fault_i) begin selected_code = control_fault_code_i;
      selected_pc = control_fault_pc_i; end
    else if (unsupported_fault_i) begin selected_code = FAULT_UNSUPPORTED_STAGE;
      selected_pc = unsupported_fault_pc_i; end
    fatal_now_o = fault_valid_q || (|causes);
    fault_valid_o = fault_valid_q;
    fault_code_o = fault_code_q;
    fault_pc_o = fault_pc_q;
    simultaneous_causes_o = causes_q;
  end
  always_ff @(posedge clk) begin
    if (rst || clear_i) begin fault_valid_q <= 0; fault_code_q <= FAULT_NONE;
      fault_pc_q <= 0; causes_q <= 0; end
    else if (!fault_valid_q && |causes) begin fault_valid_q <= 1;
      fault_code_q <= selected_code; fault_pc_q <= selected_pc;
      causes_q <= causes; end
  end
`ifndef SYNTHESIS
  property p_sticky; @(posedge clk) disable iff (rst || clear_i)
    fault_valid_q |=> fault_valid_q && $stable(fault_code_q) &&
      $stable(fault_pc_q) && $stable(causes_q); endproperty
  assert property(p_sticky);
`endif
endmodule
