/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off BLKSEQ */
module tb_asic_host_controller;
  import simt_gpu_pkg::*;
  logic clk=0,reset,test_mode,wb_cyc,wb_stb,wb_we,wb_ack,wb_err;
  logic[7:0]wb_adr;logic[31:0]wb_wdata,wb_rdata;logic[3:0]wb_sel;
  logic clear,launch_valid,launch_ready,prog_valid,running,done,fault;
  logic[31:0]launch_pc,prog_data,fault_pc;logic[2:0]warp_count;
  logic[5:0]prog_addr;fault_code_t fault_code;
  logic[63:0]cycles,issues,commits;int unsigned checks;
  always #5 clk=~clk;

  asic_host_controller dut(.clk_i(clk),.reset_i(reset),.test_mode_i(test_mode),
    .wb_cyc_i(wb_cyc),.wb_stb_i(wb_stb),.wb_we_i(wb_we),.wb_adr_i(wb_adr),
    .wb_dat_i(wb_wdata),.wb_sel_i(wb_sel),.wb_ack_o(wb_ack),.wb_err_o(wb_err),
    .wb_dat_o(wb_rdata),.clear_o(clear),.launch_valid_o(launch_valid),
    .launch_ready_i(launch_ready),.launch_pc_o(launch_pc),
    .launch_warp_count_o(warp_count),.prog_valid_o(prog_valid),
    .prog_addr_o(prog_addr),.prog_data_o(prog_data),.running_i(running),
    .done_i(done),.fault_i(fault),.fault_pc_i(fault_pc),.fault_code_i(fault_code),
    .cycle_count_i(cycles),.issue_count_i(issues),.commit_count_i(commits));

  task automatic write_reg(input logic[7:0]addr,input logic[31:0]data,input logic[3:0]sel=4'hf);
    @(negedge clk);wb_cyc=1;wb_stb=1;wb_we=1;wb_adr=addr;wb_wdata=data;wb_sel=sel;
    #1;checks++;if(!wb_ack||wb_err)$fatal(1,"write response addr=%h",addr);
    @(negedge clk);wb_cyc=0;wb_stb=0;wb_we=0;
  endtask
  task automatic read_reg(input logic[7:0]addr,input logic[31:0]expected);
    @(negedge clk);wb_cyc=1;wb_stb=1;wb_we=0;wb_adr=addr;wb_sel=4'hf;
    #1;checks++;if(!wb_ack||wb_err||wb_rdata!==expected)
      $fatal(1,"read addr=%h got=%h expected=%h",addr,wb_rdata,expected);
    @(negedge clk);wb_cyc=0;wb_stb=0;
  endtask

  initial begin
    reset=1;test_mode=0;wb_cyc=0;wb_stb=0;wb_we=0;wb_adr=0;wb_wdata=0;wb_sel=0;
    launch_ready=0;running=0;done=0;fault=0;fault_pc=32'h1234;
    fault_code=FAULT_MEMORY_MISALIGNED;cycles=64'h11223344_55667788;
    issues=64'h01020304_05060708;commits=64'haabbccdd_eeff0011;checks=0;
    repeat(2)@(posedge clk);@(negedge clk);reset=0;
    write_reg(8'h08,32'h12345678);read_reg(8'h08,32'h12345678);
    write_reg(8'h08,32'haaaa0000,4'b1100);read_reg(8'h08,32'haaaa5678);
    write_reg(8'h0c,32'd4);read_reg(8'h0c,32'd4);
    write_reg(8'h10,32'd19);read_reg(8'h10,32'd19);
    write_reg(8'h14,32'hdeadbeef);
    checks++;if(!prog_valid||prog_addr!=19||prog_data!=32'hdeadbeef)$fatal(1,"program pulse");
    @(posedge clk);@(negedge clk);checks++;if(prog_valid)$fatal(1,"program pulse held");
    running=1;done=1;fault=1;read_reg(8'h04,32'h7);
    read_reg(8'h1c,32'h1234);read_reg(8'h20,32'h55667788);read_reg(8'h24,32'h11223344);
    write_reg(8'h00,32'h1);checks++;if(!launch_valid)$fatal(1,"launch not held");
    launch_ready=1;@(posedge clk);@(negedge clk);checks++;if(launch_valid)$fatal(1,"launch not consumed");
    launch_ready=0;write_reg(8'h00,32'h2);checks++;if(!clear)$fatal(1,"clear pulse missing");
    @(posedge clk);@(negedge clk);checks++;if(clear)$fatal(1,"clear pulse held");
    wb_cyc=1;wb_stb=1;wb_we=0;wb_adr=8'h38;#1;checks++;
    if(wb_ack||!wb_err)$fatal(1,"invalid address not rejected ack=%b err=%b addr=%h",wb_ack,wb_err,wb_adr);
    wb_adr=8'h00;test_mode=1;#1;checks++;
    if(wb_ack||!wb_err)$fatal(1,"test ownership not enforced");
    $display("PASS tb_asic_host_controller checks=%0d",checks);$finish;
  end
endmodule
/* verilator lint_on BLKSEQ */
/* verilator lint_on UNUSEDSIGNAL */
