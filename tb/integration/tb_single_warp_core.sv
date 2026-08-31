/* verilator lint_off PINCONNECTEMPTY */
module tb_single_warp_core;
  import simt_gpu_pkg::*;
  logic clk = 0, rst, clear, prog_valid, launch_valid;
  logic [5:0] prog_addr; logic [31:0] prog_data, launch_pc, fault_pc;
  logic launch_ready, running, done, fault, commit_valid;
  logic [2:0] launch_warp_count;
  logic [63:0] cycle_count, issue_count, commit_count;
  fault_code_t fault_code;
  completion_record_t commit;
  word_t shadow_gpr [REGS_PER_THREAD][LANES];
  lane_mask_t shadow_pred [PREDS_PER_THREAD];
  lane_mask_t shadow_active;
  integer trace_file;
  int unsigned commits;
  always #5 clk <= ~clk;
  simt_core dut (.*,.diagnostic_count_o(),.counter_saturated_o(),
    .clear_i(clear), .prog_valid_i(prog_valid), .prog_addr_i(prog_addr),
    .prog_data_i(prog_data), .launch_valid_i(launch_valid),
    .launch_ready_o(launch_ready), .launch_pc_i(launch_pc),
    .launch_warp_count_i(launch_warp_count),
    .fetch_response_ready_i(1'b1),
    .execute_completion_ready_i(1'b1), .commit_ready_i(1'b1),
    .running_o(running), .done_o(done), .fault_o(fault),
    .fault_pc_o(fault_pc), .fault_code_o(fault_code),
    .commit_valid_o(commit_valid), .commit_o(commit),
    .cycle_count_o(cycle_count), .issue_count_o(issue_count),
    .commit_count_o(commit_count),.watchdog_enable_i(1'b1),.watchdog_limit_i(32'd256),
    .host_mem_valid_i(1'b0),.host_mem_shared_i(1'b0),.host_mem_write_i(1'b0),
    .host_mem_address_i('0),.host_mem_write_data_i('0),.inject_fault_i('0),.host_mem_ready_o(),.host_mem_response_valid_o(),.host_mem_response_fault_o(),
    .host_mem_read_data_o(),.debug_warp_pc_o(),.debug_active_mask_o(),
    .debug_gpr_pending_o(),.debug_pred_pending_o(),.debug_stack_depth_o(),
    .debug_resident_o(),.debug_barrier_wait_o(),.debug_memory_busy_o(),
    .debug_tracker_occupancy_o(),.debug_alu_occupancy_o(),.debug_mul_occupancy_o(),
    .debug_wb_occupancy_o(),.debug_epoch_o(),.debug_quiescent_o(),
    .debug_stack_top_o(),.debug_tracker_summary_o(),.debug_memory_completion_occupancy_o());

  task automatic program_word(input logic [5:0] address, input logic [31:0] data);
    @(negedge clk); prog_addr = address; prog_data = data; prog_valid = 1;
    @(posedge clk); #1; prog_valid = 0;
  endtask
  initial begin
    rst=1; clear=0; prog_valid=0; prog_addr=0; prog_data=0;
    launch_valid=0; launch_pc=0; launch_warp_count=1; commits=0;
    shadow_active='1; for(int r=0;r<REGS_PER_THREAD;r++)for(int l=0;l<LANES;l++)shadow_gpr[r][l]=0;
    for(int p=0;p<PREDS_PER_THREAD;p++)shadow_pred[p]=0;
    trace_file=$fopen("build/rtl_single_warp.trace","w");
    repeat(2) @(posedge clk); @(negedge clk); rst=0;
    program_word(0,32'h38040007); program_word(1,32'h38080003);
    program_word(2,32'h040c4800); program_word(3,32'h4000cc00);
    program_word(4,32'h0610c400); program_word(5,32'h78000000);
    @(negedge clk); if(!launch_ready) $fatal(1,"launch not ready");
    launch_valid=1; @(posedge clk); #1; launch_valid=0;
    repeat (80) begin
      @(negedge clk); #1;
      if (fault) $fatal(1,"core fault pc=%0d",fault_pc);
      if (commit_valid) begin
        if ($isunknown(commit)) $fatal(1,"unknown bit in completion record");
        if (commit.sequence_number != INSTRUCTION_SEQUENCE_WIDTH'(commits))
          $fatal(1,"commit sequence mismatch got=%0d expected=%0d",
                 commit.sequence_number, commits);
        case (commits)
          0: if (!commit.writes_gpr || commit.gpr_dst != 1 ||
                 commit.gpr_data[0] != 7) $fatal(1,"MOVI R1 mismatch");
          1: if (!commit.writes_gpr || commit.gpr_dst != 2 ||
                 commit.gpr_data[7] != 3) $fatal(1,"MOVI R2 mismatch");
          2: if (!commit.writes_gpr || commit.gpr_dst != 3 ||
                 commit.gpr_data[3] != 10) $fatal(1,"dependent ADD mismatch");
          3: if (!commit.writes_pred || commit.pred_dst != 0 ||
                 commit.pred_data != 8'hff) $fatal(1,"SETP mismatch");
          4: if (!commit.writes_gpr || commit.gpr_dst != 4 ||
                 commit.gpr_data[5] != 17) $fatal(1,"predicated ADD mismatch");
          5: if (commit.writes_gpr || commit.writes_pred ||
                 commit.active_mask != 8'hff) $fatal(1,"EXIT mismatch");
          default: $fatal(1,"unexpected extra commit");
        endcase
        if(commit.writes_gpr)for(int l=0;l<LANES;l++)if(commit.gpr_mask[l])shadow_gpr[commit.gpr_dst][l]=commit.gpr_data[l];
        if(commit.writes_pred)for(int l=0;l<LANES;l++)if(commit.pred_mask[l])shadow_pred[commit.pred_dst][l]=commit.pred_data[l];
        if(commit.instruction[31:26]==6'd30)shadow_active&=~commit.write_mask;
        $fwrite(trace_file,"E %0d %08x %08x %02x\nR",commits,commit.pc,commit.instruction,shadow_active);
        for(int r=0;r<REGS_PER_THREAD;r++)for(int l=0;l<LANES;l++)$fwrite(trace_file," %08x",shadow_gpr[r][l]);
        $fwrite(trace_file,"\nP");for(int p=0;p<PREDS_PER_THREAD;p++)$fwrite(trace_file," %02x",shadow_pred[p]);$fwrite(trace_file,"\n");
        commits++;
      end
      if (done) begin
        if (commits != 6 || running || fault_code != FAULT_NONE ||
            cycle_count == 0 || issue_count != 6 || commit_count != 6)
          $fatal(1,"completion state mismatch");
        $display("PASS tb_single_warp_core commits=%0d", commits);
        $fclose(trace_file);
        $finish;
      end
    end
    $fatal(1,"single-warp program timed out commits=%0d", commits);
  end
endmodule
