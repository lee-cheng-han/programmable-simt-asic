/* verilator lint_off DECLFILENAME */
(* blackbox *)
module RM_IHPSG13_1P_64x64_c2_bm_bist (
  input logic A_CLK, A_MEN, A_WEN, A_REN,
  input logic [5:0] A_ADDR,
  input logic [63:0] A_DIN,
  input logic A_DLY,
  output logic [63:0] A_DOUT,
  input logic [63:0] A_BM,
  input logic A_BIST_CLK, A_BIST_EN, A_BIST_MEN, A_BIST_WEN, A_BIST_REN,
  input logic [5:0] A_BIST_ADDR,
  input logic [63:0] A_BIST_DIN, A_BIST_BM
);
endmodule
/* verilator lint_on DECLFILENAME */
