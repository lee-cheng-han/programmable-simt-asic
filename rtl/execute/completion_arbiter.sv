module completion_arbiter #(
  parameter int unsigned SOURCES = 3,
  parameter int unsigned INDEX_W = (SOURCES <= 1) ? 1 : $clog2(SOURCES)
) (
  input  logic                                           clk,
  input  logic                                           rst,
  input  logic                                           clear_i,
  input  logic [SOURCES-1:0]                             source_valid_i,
  output logic [SOURCES-1:0]                             source_ready_o,
  input  simt_gpu_pkg::completion_record_t               source_completion_i [SOURCES],
  output logic                                           completion_valid_o,
  input  logic                                           completion_ready_i,
  output simt_gpu_pkg::completion_record_t               completion_o,
  output logic [INDEX_W-1:0]                             selected_source_o
);
  logic [SOURCES-1:0] grant;
  logic grant_valid;

  round_robin_arbiter #(.REQUESTERS(SOURCES)) arbiter_u (
    .clk(clk), .rst(rst), .clear_i(clear_i), .request_i(source_valid_i),
    .grant_valid_o(grant_valid), .grant_index_o(selected_source_o),
    .grant_onehot_o(grant),
    .grant_accept_i(completion_valid_o && completion_ready_i)
  );

  always_comb begin
    completion_valid_o = grant_valid;
    completion_o = '0;
    source_ready_o = '0;
    if (grant_valid) begin
      completion_o = source_completion_i[selected_source_o];
      source_ready_o = grant & {SOURCES{completion_ready_i}};
    end
  end
endmodule
