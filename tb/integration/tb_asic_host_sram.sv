/* verilator lint_off UNUSEDSIGNAL */
module tb_asic_host_sram;
  import simt_gpu_pkg::*;import simt_isa_pkg::*;
  logic clk=0,reset_n=0,cyc,stb,we,ack,err,test_mode=0,scan_enable=0,scan_in=0;
  logic[7:0]adr;logic[31:0]wdata,rdata;logic[3:0]sel;logic scan_out,running,done,fault;
  logic bist_start=0,bist_active,bist_done,bist_fail,bist_fail_shared;logic[31:0]bist_fail_address;
  int checks;
  /* verilator lint_off BLKSEQ */always #5 clk=~clk;/* verilator lint_on BLKSEQ */
  simt_asic_top #(.USE_IHP_IMEM(0),.USE_IHP_DATA_SRAM(0))dut(
    .clk_i(clk),.reset_n_i(reset_n),.wb_cyc_i(cyc),.wb_stb_i(stb),.wb_we_i(we),
    .wb_adr_i(adr),.wb_dat_i(wdata),.wb_sel_i(sel),.wb_ack_o(ack),.wb_err_o(err),
    .wb_dat_o(rdata),.test_mode_i(test_mode),.scan_enable_i(scan_enable),
    .scan_in_i(scan_in),.scan_out_o(scan_out),.bist_start_i(bist_start),
    .bist_active_o(bist_active),.bist_done_o(bist_done),.bist_fail_o(bist_fail),
    .bist_fail_shared_o(bist_fail_shared),.bist_fail_address_o(bist_fail_address),
    .running_o(running),.done_o(done),.fault_o(fault));
  function automatic logic[31:0]enc(input opcode_t op,input logic[3:0]rd,
    input logic[3:0]ra,input logic[3:0]rb,input logic[9:0]imm);
    return {op,4'b0,rd,ra,rb,imm};endfunction
  task automatic wr(input logic[7:0]a,input logic[31:0]d,input logic expect_error=0);
    @(negedge clk);cyc=1;stb=1;we=1;adr=a;wdata=d;sel=4'hf;#1;
    if(expect_error?!err:(!ack||err))$fatal(1,"Wishbone write a=%h ack=%b err=%b",a,ack,err);
    @(negedge clk);cyc=0;stb=0;we=0;checks++;
  endtask
  task automatic rd(input logic[7:0]a,output logic[31:0]d);
    @(negedge clk);cyc=1;stb=1;we=0;adr=a;sel=4'hf;#1;
    if(!ack||err)$fatal(1,"Wishbone read a=%h",a);d=rdata;
    @(negedge clk);cyc=0;stb=0;checks++;
  endtask
  task automatic put_instruction(input logic[5:0]a,input logic[31:0]d);
    wr(8'h10,32'(a));wr(8'h14,d);
  endtask
  task automatic host_mem(input logic shared,input logic write,input logic[31:0]address,
    input logic[31:0]data,output logic[31:0]result);
    logic[31:0]status;wr(8'h84,address);if(write)wr(8'h88,data);
    wr(8'h8c,{29'b0,shared,write,1'b1});
    status=32'h8;while(status[3])rd(8'h8c,status);
    if(status[4])$fatal(1,"host memory fault shared=%b address=%h",shared,address);
    rd(8'h90,result);
  endtask
  initial begin
    logic[31:0]value,status,breadcrumb,commits;
    cyc=0;stb=0;we=0;adr=0;wdata=0;sel=0;checks=0;
    repeat(3)@(posedge clk);reset_n=1;repeat(3)@(posedge clk);
    rd(8'h3c,value);if(value!=32'h53494d54)$fatal(1,"build ID");
    host_mem(0,1,32'h100,32'h11223344,value);host_mem(0,0,32'h100,0,value);
    if(value!=32'h11223344)$fatal(1,"general maintenance readback");
    host_mem(1,1,32'h40,32'h55667788,value);host_mem(1,0,32'h40,0,value);
    if(value!=32'h55667788)$fatal(1,"shared maintenance readback");
    put_instruction(0,enc(OP_MOVI,1,0,0,128));put_instruction(1,enc(OP_MOVI,2,0,0,42));
    put_instruction(2,enc(OP_ST_G,0,1,2,0));put_instruction(3,enc(OP_LD_G,3,1,0,0));
    put_instruction(4,enc(OP_MOVI,4,0,0,16));put_instruction(5,enc(OP_ST_S,0,4,3,0));
    put_instruction(6,enc(OP_LD_S,5,4,0,0));put_instruction(7,enc(OP_BAR,0,0,0,0));
    put_instruction(8,enc(OP_ADD,6,5,2,0));put_instruction(9,enc(OP_EXIT,0,0,0,0));
    wr(8'h0c,4);wr(8'h00,1);
    repeat(2000)begin rd(8'h04,status);if(status[2]||status[1])break;end
    if(fault||!done)$fatal(1,"diagnostic did not complete status=%h",status);
    wr(8'h00,4);rd(8'h30,commits);if(commits!=40)$fatal(1,"commit count=%0d",commits);
    rd(8'h44,breadcrumb);if((breadcrumb&32'h1f)!=32'h1f)$fatal(1,"breadcrumbs=%h",breadcrumb);
    rd(8'h4c,value);if(!value[0])$fatal(1,"snapshot not quiescent");
    test_mode=1;repeat(2)@(posedge clk);bist_start=1;@(posedge clk);bist_start=0;
    repeat(100000)begin @(posedge clk);if(bist_done)break;end
    if(!bist_done||bist_active||bist_fail)$fatal(1,"SRAM BIST failed done=%b active=%b fail=%b space=%b address=%h",bist_done,bist_active,bist_fail,bist_fail_shared,bist_fail_address);
    $display("PASS tb_asic_host_sram checks=%0d commits=%0d breadcrumbs=%h",checks,commits,breadcrumb);
    $finish;
  end
endmodule
