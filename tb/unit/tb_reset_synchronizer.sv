/* verilator lint_off BLKSEQ */
module tb_reset_synchronizer;
  logic clk=0,async_reset,reset;int unsigned checks;
  always #5 clk=~clk;
  reset_synchronizer dut(.clk_i(clk),.async_reset_i(async_reset),.reset_o(reset));
  initial begin
    async_reset=0;checks=0;
    #2 async_reset=1;#1;checks++;if(!reset)$fatal(1,"async assertion delayed");
    #4 async_reset=0;
    @(posedge clk);#1;checks++;if(!reset)$fatal(1,"released after one stage");
    @(posedge clk);#1;checks++;if(reset)$fatal(1,"did not release after two stages");
    #2 async_reset=1;#1;checks++;if(!reset)$fatal(1,"reassertion delayed");
    $display("PASS tb_reset_synchronizer checks=%0d",checks);$finish;
  end
endmodule
/* verilator lint_on BLKSEQ */
