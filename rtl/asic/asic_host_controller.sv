module asic_host_controller #(parameter int unsigned IMEM_ADDR_W=6,
  parameter int unsigned BARRIER_TIMEOUT_CYCLES=256,
  parameter bit ENABLE_FAULT_INJECTION=1'b0,
  parameter logic[31:0]BUILD_ID=32'h53494d54)(
  input logic clk_i,reset_i,test_mode_i,input logic wb_cyc_i,wb_stb_i,wb_we_i,
  input logic[7:0]wb_adr_i,input logic[31:0]wb_dat_i,input logic[3:0]wb_sel_i,
  output logic wb_ack_o,wb_err_o,output logic[31:0]wb_dat_o,
  output logic clear_o,launch_valid_o,input logic launch_ready_i,
  output logic[31:0]launch_pc_o,output logic[2:0]launch_warp_count_o,
  output logic prog_valid_o,output logic[IMEM_ADDR_W-1:0]prog_addr_o,output logic[31:0]prog_data_o,
  input logic running_i,done_i,fault_i,input logic[31:0]fault_pc_i,
  input simt_gpu_pkg::fault_code_t fault_code_i,input logic[63:0]cycle_count_i,issue_count_i,commit_count_i,
  input logic quiescent_i,input logic[simt_gpu_pkg::KERNEL_EPOCH_WIDTH-1:0]epoch_i,
  input logic[simt_gpu_pkg::WARPS-1:0][31:0]debug_warp_pc_i,
  input simt_gpu_pkg::lane_mask_t debug_active_mask_i[simt_gpu_pkg::WARPS],
  input logic[simt_gpu_pkg::WARPS-1:0][simt_gpu_pkg::REGS_PER_THREAD-1:0]debug_gpr_pending_i,
  input logic[simt_gpu_pkg::WARPS-1:0][simt_gpu_pkg::PREDS_PER_THREAD-1:0]debug_pred_pending_i,
  input logic[simt_gpu_pkg::WARPS-1:0][3:0]debug_stack_depth_i,
  input logic[simt_gpu_pkg::WARPS-1:0][31:0]debug_stack_top_i,
  input logic[simt_gpu_pkg::WARPS-1:0]debug_resident_i,debug_barrier_wait_i,debug_memory_busy_i,
  input logic[2:0]debug_tracker_occupancy_i,
  input logic[simt_gpu_pkg::MAX_MEMORY_OPS-1:0][7:0]debug_tracker_summary_i,
  input logic[1:0]debug_memory_completion_occupancy_i,
  input logic[1:0]debug_alu_occupancy_i,debug_mul_occupancy_i,debug_wb_occupancy_i,
  output logic watchdog_enable_o,output logic[31:0]watchdog_limit_o,
  output logic host_mem_valid_o,host_mem_shared_o,host_mem_write_o,
  output logic[31:0]host_mem_address_o,host_mem_write_data_o,
  input logic host_mem_ready_i,host_mem_response_valid_i,host_mem_response_fault_i,
  input logic[31:0]host_mem_read_data_i,output logic[4:0]inject_fault_o,input logic bist_done_i);
  import simt_gpu_pkg::*;
  localparam logic[7:0] A_CONTROL=8'h00,A_STATUS=8'h04,A_LAUNCH_PC=8'h08,A_WARP_COUNT=8'h0c;
  localparam logic[7:0] A_IMEM_ADDR=8'h10,A_IMEM_DATA=8'h14,A_FAULT_CODE=8'h18,A_FAULT_PC=8'h1c;
  localparam logic[7:0] A_CYCLE_LO=8'h20,A_CYCLE_HI=8'h24,A_ISSUE_LO=8'h28,A_ISSUE_HI=8'h2c;
  localparam logic[7:0] A_COMMIT_LO=8'h30,A_COMMIT_HI=8'h34,A_WATCHDOG=8'h38,A_BUILD_ID=8'h3c;
  localparam logic[7:0] A_MACHINE=8'h40,A_BREADCRUMB=8'h44,A_SNAPSHOT=8'h48,A_SNAPSHOT_META=8'h4c;
  localparam logic[7:0] A_WARP_PC0=8'h50,A_WARP_STATE0=8'h60,A_WARP_HAZARD0=8'h70;
  localparam logic[7:0] A_PIPELINE=8'h80,A_MEM_ADDR=8'h84,A_MEM_WDATA=8'h88,A_MEM_COMMAND=8'h8c;
  localparam logic[7:0] A_MEM_RDATA=8'h90,A_INJECT=8'h94;
  localparam logic[7:0] A_STACK_TOP0=8'ha0,A_TRACKER0=8'hb0;
  logic request,address_valid,write_allowed,transaction_error;
  /* verilator lint_off UNUSEDSIGNAL */
  logic[31:0]merged_launch_pc,merged_prog_data,merged_watchdog,warp_count_word,imem_addr_word;
  /* verilator lint_on UNUSEDSIGNAL */
  logic[31:0]merged_mem_addr,merged_mem_wdata,snapshot_pc_q[WARPS],snapshot_state_q[WARPS];
  logic[31:0]snapshot_hazard_q[WARPS],snapshot_meta_q,snapshot_pipeline_q,mem_read_data_q;
  logic[31:0]snapshot_stack_top_q[WARPS],snapshot_tracker_q[MAX_MEMORY_OPS];
  logic[5:0]breadcrumb_q;logic fault_q,mem_busy_q,mem_fault_q;
  always_comb begin
    request=wb_cyc_i&&wb_stb_i;
    address_valid=wb_adr_i[1:0]==0&&(wb_adr_i<=A_SNAPSHOT_META||
      (wb_adr_i>=A_WARP_PC0&&wb_adr_i<=A_WARP_PC0+8'h0c)||
      (wb_adr_i>=A_WARP_STATE0&&wb_adr_i<=A_WARP_STATE0+8'h0c)||
      (wb_adr_i>=A_WARP_HAZARD0&&wb_adr_i<=A_WARP_HAZARD0+8'h0c)||
      (wb_adr_i>=A_PIPELINE&&wb_adr_i<=A_INJECT)||
      (wb_adr_i>=A_STACK_TOP0&&wb_adr_i<=A_STACK_TOP0+8'h0c)||
      (wb_adr_i>=A_TRACKER0&&wb_adr_i<=A_TRACKER0+8'h0c));
    write_allowed=wb_adr_i==A_CONTROL||wb_adr_i==A_LAUNCH_PC||wb_adr_i==A_WARP_COUNT||
      wb_adr_i==A_IMEM_ADDR||wb_adr_i==A_IMEM_DATA||wb_adr_i==A_WATCHDOG||
      wb_adr_i==A_MEM_ADDR||wb_adr_i==A_MEM_WDATA||wb_adr_i==A_MEM_COMMAND||
      (wb_adr_i==A_INJECT&&ENABLE_FAULT_INJECTION);
    transaction_error=test_mode_i||!address_valid||(wb_we_i&&!write_allowed);
    if(wb_we_i&&wb_adr_i==A_CONTROL&&wb_sel_i[0]&&wb_dat_i[0])
      transaction_error|=running_i||fault_i||!quiescent_i;
    if(wb_we_i&&wb_adr_i==A_CONTROL&&wb_sel_i[0]&&wb_dat_i[0])
      transaction_error|=launch_warp_count_o<1||32'(launch_warp_count_o)>32'(WARPS)||
        launch_pc_o>=(32'(1)<<IMEM_ADDR_W);
    if(wb_we_i&&wb_adr_i==A_IMEM_DATA)transaction_error|=running_i;
    if(wb_we_i&&wb_adr_i==A_MEM_COMMAND&&wb_sel_i[0]&&wb_dat_i[0])
      transaction_error|=!quiescent_i||mem_busy_q||!host_mem_ready_i;
    wb_ack_o=request&&!reset_i&&!transaction_error;wb_err_o=request&&!reset_i&&transaction_error;wb_dat_o=0;
    unique case(wb_adr_i)
      A_STATUS:wb_dat_o={27'b0,mem_fault_q,mem_busy_q,fault_i,done_i,running_i};
      A_LAUNCH_PC:wb_dat_o=launch_pc_o;A_WARP_COUNT:wb_dat_o={29'b0,launch_warp_count_o};
      A_IMEM_ADDR:wb_dat_o={{(32-IMEM_ADDR_W){1'b0}},prog_addr_o};A_IMEM_DATA:wb_dat_o=prog_data_o;
      A_FAULT_CODE:wb_dat_o=32'(fault_code_i);A_FAULT_PC:wb_dat_o=fault_pc_i;
      A_CYCLE_LO:wb_dat_o=cycle_count_i[31:0];A_CYCLE_HI:wb_dat_o=cycle_count_i[63:32];
      A_ISSUE_LO:wb_dat_o=issue_count_i[31:0];A_ISSUE_HI:wb_dat_o=issue_count_i[63:32];
      A_COMMIT_LO:wb_dat_o=commit_count_i[31:0];A_COMMIT_HI:wb_dat_o=commit_count_i[63:32];
      A_WATCHDOG:wb_dat_o={watchdog_limit_o[30:0],watchdog_enable_o};A_BUILD_ID:wb_dat_o=BUILD_ID;
      A_MACHINE:begin wb_dat_o=0;wb_dat_o[0]=quiescent_i;wb_dat_o[7:2]=epoch_i;end
      A_BREADCRUMB:wb_dat_o={26'b0,breadcrumb_q};
      A_SNAPSHOT:wb_dat_o=0;A_SNAPSHOT_META:wb_dat_o=snapshot_meta_q;A_PIPELINE:wb_dat_o=snapshot_pipeline_q;
      A_MEM_ADDR:wb_dat_o=host_mem_address_o;A_MEM_WDATA:wb_dat_o=host_mem_write_data_o;
      A_MEM_COMMAND:wb_dat_o={27'b0,mem_fault_q,mem_busy_q,host_mem_shared_o,host_mem_write_o,1'b0};
      A_MEM_RDATA:wb_dat_o=mem_read_data_q;
      A_INJECT:wb_dat_o=ENABLE_FAULT_INJECTION?{27'b0,inject_fault_o}:32'b0;
      default:begin
        for(int w=0;w<WARPS;w++)begin
          if(wb_adr_i==A_WARP_PC0+8'(4*w))wb_dat_o=snapshot_pc_q[w];
          if(wb_adr_i==A_WARP_STATE0+8'(4*w))wb_dat_o=snapshot_state_q[w];
          if(wb_adr_i==A_WARP_HAZARD0+8'(4*w))wb_dat_o=snapshot_hazard_q[w];end
        for(int w=0;w<WARPS;w++)if(wb_adr_i==A_STACK_TOP0+8'(4*w))wb_dat_o=snapshot_stack_top_q[w];
        for(int t=0;t<MAX_MEMORY_OPS;t++)if(wb_adr_i==A_TRACKER0+8'(4*t))wb_dat_o=snapshot_tracker_q[t];
      end
    endcase
    merged_launch_pc=launch_pc_o;merged_prog_data=prog_data_o;warp_count_word={29'b0,launch_warp_count_o};
    imem_addr_word={{(32-IMEM_ADDR_W){1'b0}},prog_addr_o};
    merged_watchdog={watchdog_limit_o[30:0],watchdog_enable_o};
    merged_mem_addr=host_mem_address_o;merged_mem_wdata=host_mem_write_data_o;
    for(int b=0;b<4;b++)if(wb_sel_i[b])begin
      merged_launch_pc[b*8+:8]=wb_dat_i[b*8+:8];merged_prog_data[b*8+:8]=wb_dat_i[b*8+:8];
      warp_count_word[b*8+:8]=wb_dat_i[b*8+:8];imem_addr_word[b*8+:8]=wb_dat_i[b*8+:8];
      merged_watchdog[b*8+:8]=wb_dat_i[b*8+:8];merged_mem_addr[b*8+:8]=wb_dat_i[b*8+:8];
      merged_mem_wdata[b*8+:8]=wb_dat_i[b*8+:8];end
  end
  task automatic capture_snapshot;
    for(int w=0;w<WARPS;w++)begin snapshot_pc_q[w]<=debug_warp_pc_i[w];
      snapshot_state_q[w]<={17'b0,debug_memory_busy_i[w],debug_barrier_wait_i[w],debug_resident_i[w],debug_stack_depth_i[w],debug_active_mask_i[w]};
      snapshot_hazard_q[w]<={12'b0,debug_pred_pending_i[w],debug_gpr_pending_i[w]};end
    for(int w=0;w<WARPS;w++)snapshot_stack_top_q[w]<=debug_stack_top_i[w];
    for(int t=0;t<MAX_MEMORY_OPS;t++)snapshot_tracker_q[t]<={24'b0,debug_tracker_summary_i[t]};
    snapshot_meta_q<=0;snapshot_meta_q[0]<=quiescent_i;snapshot_meta_q[1]<=fault_i;
    snapshot_meta_q[7:2]<=epoch_i;
    snapshot_pipeline_q<={21'b0,debug_memory_completion_occupancy_i,debug_tracker_occupancy_i,
      debug_wb_occupancy_i,debug_mul_occupancy_i,debug_alu_occupancy_i};
  endtask
  always_ff @(posedge clk_i)begin
    if(reset_i)begin clear_o<=0;launch_valid_o<=0;launch_pc_o<=0;launch_warp_count_o<=1;
      prog_valid_o<=0;prog_addr_o<=0;prog_data_o<=0;watchdog_enable_o<=1;
      watchdog_limit_o<=32'(BARRIER_TIMEOUT_CYCLES);
      host_mem_valid_o<=0;host_mem_shared_o<=0;host_mem_write_o<=0;host_mem_address_o<=0;host_mem_write_data_o<=0;
      mem_busy_q<=0;mem_fault_q<=0;mem_read_data_q<=0;inject_fault_o<=0;breadcrumb_q<=6'b000001;fault_q<=0;
      for(int w=0;w<WARPS;w++)begin snapshot_pc_q[w]<=0;snapshot_state_q[w]<=0;snapshot_hazard_q[w]<=0;end
      for(int w=0;w<WARPS;w++)snapshot_stack_top_q[w]<=0;
      for(int t=0;t<MAX_MEMORY_OPS;t++)snapshot_tracker_q[t]<=0;
      snapshot_meta_q<=0;snapshot_pipeline_q<=0;
    end else begin clear_o<=0;prog_valid_o<=0;host_mem_valid_o<=0;breadcrumb_q[1]<=1;
      if(launch_valid_o&&launch_ready_i)begin launch_valid_o<=0;breadcrumb_q[2]<=1;end
      if(issue_count_i!=0)breadcrumb_q[3]<=1;if(commit_count_i!=0)breadcrumb_q[4]<=1;if(bist_done_i)breadcrumb_q[5]<=1;
      if((fault_i&&!fault_q)||(request&&!transaction_error&&wb_we_i&&wb_adr_i==A_CONTROL&&wb_sel_i[0]&&wb_dat_i[2]))capture_snapshot();
      fault_q<=fault_i;
      if(host_mem_response_valid_i)begin mem_busy_q<=0;mem_fault_q<=host_mem_response_fault_i;mem_read_data_q<=host_mem_read_data_i;end
      if(request&&wb_we_i&&wb_adr_i==A_IMEM_DATA&&running_i&&!test_mode_i)begin
        prog_data_o<=merged_prog_data;prog_valid_o<=1;
      end
      if(request&&!transaction_error&&wb_we_i)unique case(wb_adr_i)
        A_CONTROL:begin if(wb_sel_i[0]&&wb_dat_i[1])begin clear_o<=1;mem_fault_q<=0;end
          if(wb_sel_i[0]&&wb_dat_i[0])launch_valid_o<=1;end
        A_LAUNCH_PC:launch_pc_o<=merged_launch_pc;A_WARP_COUNT:launch_warp_count_o<=warp_count_word[2:0];
        A_IMEM_ADDR:prog_addr_o<=imem_addr_word[IMEM_ADDR_W-1:0];
        A_IMEM_DATA:begin prog_data_o<=merged_prog_data;prog_valid_o<=1;end
        A_WATCHDOG:begin watchdog_enable_o<=merged_watchdog[0];watchdog_limit_o<={1'b0,merged_watchdog[31:1]};end
        A_MEM_ADDR:host_mem_address_o<=merged_mem_addr;A_MEM_WDATA:host_mem_write_data_o<=merged_mem_wdata;
        A_MEM_COMMAND:if(wb_sel_i[0]&&wb_dat_i[0])begin host_mem_shared_o<=wb_dat_i[2];host_mem_write_o<=wb_dat_i[1];
          host_mem_valid_o<=1;mem_busy_q<=1;mem_fault_q<=0;end
        A_INJECT:if(ENABLE_FAULT_INJECTION)inject_fault_o<=wb_dat_i[4:0];default:begin end endcase
    end
  end
`ifndef SYNTHESIS
  assert property(@(posedge clk_i)reset_i|->!wb_ack_o&&!wb_err_o&&!clear_o&&!launch_valid_o&&!prog_valid_o);
  assert property(@(posedge clk_i)disable iff(reset_i)test_mode_i|->!clear_o&&!launch_valid_o&&!prog_valid_o&&!host_mem_valid_o);
`endif
endmodule
