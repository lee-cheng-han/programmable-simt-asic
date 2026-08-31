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
  logic[7:0][31:0]diagnostic_count;logic counter_saturated;
  logic quiescent;logic[KERNEL_EPOCH_WIDTH-1:0]epoch;
  logic[WARPS-1:0][31:0]debug_warp_pc;lane_mask_t debug_active_mask[WARPS];
  logic[WARPS-1:0][REGS_PER_THREAD-1:0]debug_gpr_pending;
  logic[WARPS-1:0][PREDS_PER_THREAD-1:0]debug_pred_pending;
  logic[WARPS-1:0][3:0]debug_stack_depth;
  logic[WARPS-1:0][31:0]debug_stack_top;logic[MAX_MEMORY_OPS-1:0][7:0]debug_tracker_summary;
  logic[WARPS-1:0]debug_resident,debug_barrier_wait,debug_memory_busy;
  logic[2:0]debug_tracker_occupancy;logic[1:0]debug_alu_occupancy,debug_mul_occupancy,debug_wb_occupancy;
  logic[1:0]debug_memory_completion_occupancy;
  logic watchdog_enable;logic[31:0]watchdog_limit;
  logic host_mem_valid,host_mem_shared,host_mem_write,host_mem_ready;
  logic host_mem_response_valid,host_mem_response_fault,bist_done;logic[31:0]host_mem_address,host_mem_write_data,host_mem_read_data;
  logic[4:0]inject_fault;
  always #5 clk=~clk;

  asic_host_controller dut(.clk_i(clk),.reset_i(reset),.test_mode_i(test_mode),
    .wb_cyc_i(wb_cyc),.wb_stb_i(wb_stb),.wb_we_i(wb_we),.wb_adr_i(wb_adr),
    .wb_dat_i(wb_wdata),.wb_sel_i(wb_sel),.wb_ack_o(wb_ack),.wb_err_o(wb_err),
    .wb_dat_o(wb_rdata),.clear_o(clear),.launch_valid_o(launch_valid),
    .launch_ready_i(launch_ready),.launch_pc_o(launch_pc),
    .launch_warp_count_o(warp_count),.prog_valid_o(prog_valid),
    .prog_addr_o(prog_addr),.prog_data_o(prog_data),.running_i(running),
    .done_i(done),.fault_i(fault),.fault_pc_i(fault_pc),.fault_code_i(fault_code),
    .cycle_count_i(cycles),.issue_count_i(issues),.commit_count_i(commits),
    .diagnostic_count_i(diagnostic_count),.counter_saturated_i(counter_saturated),
    .quiescent_i(quiescent),.epoch_i(epoch),.debug_warp_pc_i(debug_warp_pc),
    .debug_active_mask_i(debug_active_mask),.debug_gpr_pending_i(debug_gpr_pending),
    .debug_pred_pending_i(debug_pred_pending),.debug_stack_depth_i(debug_stack_depth),
    .debug_stack_top_i(debug_stack_top),.debug_tracker_summary_i(debug_tracker_summary),
    .debug_memory_completion_occupancy_i(debug_memory_completion_occupancy),
    .debug_resident_i(debug_resident),.debug_barrier_wait_i(debug_barrier_wait),
    .debug_memory_busy_i(debug_memory_busy),.debug_tracker_occupancy_i(debug_tracker_occupancy),
    .debug_alu_occupancy_i(debug_alu_occupancy),.debug_mul_occupancy_i(debug_mul_occupancy),
    .debug_wb_occupancy_i(debug_wb_occupancy),.watchdog_enable_o(watchdog_enable),
    .watchdog_limit_o(watchdog_limit),.host_mem_valid_o(host_mem_valid),
    .host_mem_shared_o(host_mem_shared),.host_mem_write_o(host_mem_write),
    .host_mem_address_o(host_mem_address),.host_mem_write_data_o(host_mem_write_data),
    .host_mem_ready_i(host_mem_ready),.host_mem_response_valid_i(host_mem_response_valid),
    .host_mem_response_fault_i(host_mem_response_fault),.host_mem_read_data_i(host_mem_read_data),
    .inject_fault_o(inject_fault),.bist_done_i(bist_done));

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
    diagnostic_count='0;counter_saturated=0;
    quiescent=1;epoch=3;debug_warp_pc='0;debug_gpr_pending='0;debug_pred_pending='0;
    debug_stack_depth='0;debug_resident='0;debug_barrier_wait='0;debug_memory_busy='0;
    debug_stack_top='0;debug_tracker_summary='0;debug_memory_completion_occupancy=0;
    debug_tracker_occupancy=0;debug_alu_occupancy=0;debug_mul_occupancy=0;debug_wb_occupancy=0;
    for(int w=0;w<WARPS;w++)debug_active_mask[w]='0;
    host_mem_ready=1;host_mem_response_valid=0;host_mem_response_fault=0;host_mem_read_data=0;bist_done=0;
    wb_cyc=1;wb_stb=1;wb_adr=8'h04;#1;checks++;
    if(wb_ack||wb_err)$fatal(1,"bus responded during reset");
    wb_cyc=0;wb_stb=0;
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
    running=0;done=0;fault=0;
    write_reg(8'h08,32'h0);
    write_reg(8'h00,32'h1);checks++;if(!launch_valid)$fatal(1,"launch not held");
    launch_ready=1;@(posedge clk);@(negedge clk);checks++;if(launch_valid)$fatal(1,"launch not consumed");
    launch_ready=0;write_reg(8'h00,32'h2);checks++;if(!clear)$fatal(1,"clear pulse missing");
    @(posedge clk);@(negedge clk);checks++;if(clear)$fatal(1,"clear pulse held");
    read_reg(8'h3c,32'h53494d54);read_reg(8'h40,32'h0000000d);
    write_reg(8'h38,32'd64|1);read_reg(8'h38,32'd65);
    debug_warp_pc[0]=32'h44;debug_active_mask[0]=8'h3f;debug_stack_depth[0]=2;
    debug_stack_top[0]=32'h88;debug_tracker_summary[0]=8'ha5;
    write_reg(8'h00,32'h4);read_reg(8'h50,32'h44);read_reg(8'h60,32'h0000023f);
    read_reg(8'ha0,32'h88);read_reg(8'hb0,32'ha5);
    diagnostic_count[0]=32'h12345678;diagnostic_count[7]=32'h87654321;
    read_reg(8'hc0,32'h12345678);read_reg(8'hdc,32'h87654321);
    counter_saturated=1;read_reg(8'he0,32'h1);
    write_reg(8'h84,32'h20);write_reg(8'h88,32'hc001cafe);write_reg(8'h8c,32'h3);
    checks++;if(!host_mem_valid||!host_mem_write||host_mem_address!=32'h20)$fatal(1,"maintenance request");
    @(posedge clk);@(negedge clk);host_mem_response_valid=1;host_mem_read_data=32'hc001cafe;
    @(posedge clk);@(negedge clk);host_mem_response_valid=0;read_reg(8'h90,32'hc001cafe);
    wb_cyc=1;wb_stb=1;wb_we=1;wb_adr=8'h94;wb_wdata=1;#1;checks++;
    if(wb_ack||!wb_err)$fatal(1,"production injection register accepted");
    @(negedge clk);wb_cyc=0;wb_stb=0;wb_we=0;
    wb_cyc=1;wb_stb=1;wb_we=0;wb_adr=8'h98;#1;checks++;
    if(wb_ack||!wb_err)$fatal(1,"invalid address not rejected ack=%b err=%b addr=%h",wb_ack,wb_err,wb_adr);
    wb_adr=8'h00;test_mode=1;#1;checks++;
    if(wb_ack||!wb_err)$fatal(1,"test ownership not enforced");
    $display("PASS tb_asic_host_controller checks=%0d",checks);$finish;
  end
endmodule
/* verilator lint_on BLKSEQ */
/* verilator lint_on UNUSEDSIGNAL */
