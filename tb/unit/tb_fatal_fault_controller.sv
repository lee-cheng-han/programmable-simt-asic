module tb_fatal_fault_controller;
  import simt_gpu_pkg::*;
  logic clk=0,rst,clear,host_fault,fetch_fault,illegal_fault,memory_fault;
  logic control_fault,unsupported_fault,fatal_now,fault_valid;
  logic[31:0]host_pc,fetch_pc,illegal_pc,memory_pc,control_pc,unsupported_pc,fault_pc;
  fault_code_t memory_code,control_code,fault_code;
  logic[5:0]causes;int checks;
  /* verilator lint_off BLKSEQ */ always #5 clk=~clk; /* verilator lint_on BLKSEQ */
  fatal_fault_controller dut(.clk,.rst,.clear_i(clear),.host_fault_i(host_fault),
    .host_fault_pc_i(host_pc),.fetch_fault_i(fetch_fault),.fetch_fault_pc_i(fetch_pc),
    .illegal_fault_i(illegal_fault),.illegal_fault_pc_i(illegal_pc),
    .unsupported_fault_i(unsupported_fault),.unsupported_fault_pc_i(unsupported_pc),
    .memory_fault_i(memory_fault),.memory_fault_code_i(memory_code),.memory_fault_pc_i(memory_pc),
    .control_fault_i(control_fault),.control_fault_code_i(control_code),.control_fault_pc_i(control_pc),
    .fatal_now_o(fatal_now),.fault_valid_o(fault_valid),.fault_code_o(fault_code),
    .fault_pc_o(fault_pc),.simultaneous_causes_o(causes));
  task automatic no_causes;
    host_fault=0;fetch_fault=0;illegal_fault=0;memory_fault=0;control_fault=0;unsupported_fault=0;
  endtask
  task automatic release_fault;
    @(negedge clk);clear=1;@(posedge clk);@(negedge clk);clear=0;
    if(fault_valid||fatal_now)$fatal(1,"clear did not remove sticky fault");
  endtask
  task automatic check_pair(input int high,input int low,input fault_code_t expected,input logic[31:0]pc);
    no_causes();case(high)0:host_fault=1;1:fetch_fault=1;2:illegal_fault=1;
      3:memory_fault=1;4:control_fault=1;default:unsupported_fault=1;endcase
    case(low)0:host_fault=1;1:fetch_fault=1;2:illegal_fault=1;
      3:memory_fault=1;4:control_fault=1;default:unsupported_fault=1;endcase
    #1;if(!fatal_now)$fatal(1,"same-cycle fatal suppression missing");
    @(posedge clk);@(negedge clk);no_causes();
    if(!fault_valid||fault_code!=expected||fault_pc!=pc||!causes[5-high]||!causes[5-low])
      $fatal(1,"fault priority mismatch high=%0d low=%0d code=%0d pc=%0d causes=%b",
        high,low,fault_code,fault_pc,causes);
    checks++;release_fault();
  endtask
  initial begin
    rst=1;clear=0;no_causes();checks=0;
    host_pc=10;fetch_pc=20;illegal_pc=30;memory_pc=40;control_pc=50;unsupported_pc=60;
    memory_code=FAULT_MEMORY_OUT_OF_RANGE;control_code=FAULT_BARRIER_VIOLATION;
    repeat(2)@(posedge clk);@(negedge clk);rst=0;
    for(int high=0;high<5;high++)for(int low=high+1;low<6;low++)case(high)
      0:check_pair(high,low,FAULT_IMEM_WRITE_WHILE_BUSY,host_pc);
      1:check_pair(high,low,FAULT_FETCH_PC_RANGE,fetch_pc);
      2:check_pair(high,low,FAULT_ILLEGAL_INSTRUCTION,illegal_pc);
      3:check_pair(high,low,memory_code,memory_pc);
      4:check_pair(high,low,control_code,control_pc);
    endcase
    // Clear and reset outrank a simultaneously presented fatal cause.
    @(negedge clk);host_fault=1;clear=1;@(posedge clk);@(negedge clk);host_fault=0;clear=0;
    if(fault_valid)$fatal(1,"clear/fault collision captured fault");checks++;
    @(negedge clk);host_fault=1;rst=1;@(posedge clk);@(negedge clk);host_fault=0;rst=0;
    if(fault_valid)$fatal(1,"reset/fault collision captured fault");checks++;
    // Once sticky, later sources cannot replace the first accepted record.
    illegal_fault=1;@(posedge clk);@(negedge clk);illegal_fault=0;memory_fault=1;
    @(posedge clk);@(negedge clk);memory_fault=0;
    if(fault_code!=FAULT_ILLEGAL_INSTRUCTION||fault_pc!=illegal_pc)
      $fatal(1,"sticky fault was replaced");checks++;release_fault();
    $display("PASS tb_fatal_fault_controller checks=%0d",checks);$finish;
  end
endmodule
