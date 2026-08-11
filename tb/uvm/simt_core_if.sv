`timescale 1ns/1ps
interface simt_core_if(input logic clk);
  import simt_gpu_pkg::*;

  logic rst=1, clear=0;
  logic prog_valid=0;
  logic [5:0] prog_addr=0;
  logic [31:0] prog_data=0;
  logic launch_valid=0, launch_ready;
  logic [31:0] launch_pc=0;
  logic [2:0] launch_warp_count=0;
  logic running, done, fault;
  logic [31:0] fault_pc;
  fault_code_t fault_code;
  logic commit_valid;
  completion_record_t commit;
  logic [63:0] cycle_count, issue_count, commit_count;

endinterface
