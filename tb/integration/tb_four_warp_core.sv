/* verilator lint_off PINCONNECTEMPTY */
module tb_four_warp_core;
  import simt_gpu_pkg::*;
  logic clk = 0;
  logic rst, clear, prog_valid, launch_valid;
  logic [5:0] prog_addr;
  logic [31:0] prog_data, launch_pc, fault_pc;
  logic [2:0] launch_warp_count;
  logic launch_ready, running, done, fault, commit_valid;
  fault_code_t fault_code;
  /* verilator lint_off UNUSEDSIGNAL */
  completion_record_t commit;
  /* verilator lint_on UNUSEDSIGNAL */
  logic [63:0] cycle_count, issue_count, commit_count;
  /* verilator lint_off UNUSEDSIGNAL */logic[7:0][31:0]diagnostic_count;/* verilator lint_on UNUSEDSIGNAL */
  logic counter_saturated;
  int unsigned expected_sequence [WARPS];
  int unsigned observed_commits [WARPS];
  logic [63:0] one_warp_cycles, four_warp_cycles, relaunch_cycles;
  integer trace_file;

  /* verilator lint_off BLKSEQ */
  always #5 clk = ~clk;
  /* verilator lint_on BLKSEQ */

  simt_core #(.DIAGNOSTIC_COUNTER_MAX(32'd3))dut (
    .clk(clk), .rst(rst), .clear_i(clear),
    .prog_valid_i(prog_valid), .prog_addr_i(prog_addr),
    .prog_data_i(prog_data), .launch_valid_i(launch_valid),
    .launch_ready_o(launch_ready), .launch_pc_i(launch_pc),
    .launch_warp_count_i(launch_warp_count), .running_o(running),
    .fetch_response_ready_i(1'b1),
    .execute_completion_ready_i(1'b1), .commit_ready_i(1'b1),
    .done_o(done), .fault_o(fault), .fault_pc_o(fault_pc),
    .fault_code_o(fault_code), .commit_valid_o(commit_valid),
    .commit_o(commit), .cycle_count_o(cycle_count),
    .issue_count_o(issue_count), .commit_count_o(commit_count),.diagnostic_count_o(diagnostic_count),.counter_saturated_o(counter_saturated),
    .watchdog_enable_i(1'b1),.watchdog_limit_i(32'd256),.host_mem_valid_i(1'b0),
    .host_mem_shared_i(1'b0),.host_mem_write_i(1'b0),.host_mem_address_i('0),
    .host_mem_write_data_i('0),.inject_fault_i('0),.host_mem_ready_o(),.host_mem_response_valid_o(),.host_mem_response_fault_o(),
    .host_mem_read_data_o(),.debug_warp_pc_o(),.debug_active_mask_o(),
    .debug_gpr_pending_o(),.debug_pred_pending_o(),.debug_stack_depth_o(),
    .debug_resident_o(),.debug_barrier_wait_o(),.debug_memory_busy_o(),
    .debug_tracker_occupancy_o(),.debug_alu_occupancy_o(),.debug_mul_occupancy_o(),
    .debug_wb_occupancy_o(),.debug_epoch_o(),.debug_quiescent_o(),
    .debug_stack_top_o(),.debug_tracker_summary_o(),.debug_memory_completion_occupancy_o());

  task automatic program_word(input logic [5:0] address,
                              input logic [31:0] data);
    @(negedge clk);
    prog_addr = address;
    prog_data = data;
    prog_valid = 1;
    @(posedge clk);
    @(negedge clk);
    prog_valid = 0;
  endtask

  task automatic pulse_clear;
    @(negedge clk);
    clear = 1;
    @(posedge clk);
    @(negedge clk);
    clear = 0;
  endtask

  task automatic start_kernel(input int unsigned warps);
    if (warps < 1 || warps > WARPS) $fatal(1, "invalid warp count");
    for (int warp = 0; warp < WARPS; warp++) begin
      expected_sequence[warp] = 0;
      observed_commits[warp] = 0;
    end
    @(negedge clk);
    launch_warp_count = 3'(warps);
    #1;
    if (!launch_ready) $fatal(1, "launch was not ready");
    launch_valid = 1;
    @(posedge clk);
    @(negedge clk);
    launch_valid = 0;
  endtask

  task automatic check_commit(input int unsigned launched_warps);
    int unsigned warp;
    warp = int'(commit.warp_id);
    if (warp >= launched_warps)
      $fatal(1, "inactive warp committed warp=%0d", warp);
    if (commit.sequence_number != 16'(expected_sequence[warp]))
      $fatal(1, "warp=%0d sequence=%0d expected=%0d", warp,
             commit.sequence_number, expected_sequence[warp]);
    case (expected_sequence[warp])
      0: if (commit.gpr_dst != 1 || commit.gpr_data[7] != warp)
           $fatal(1, "S2R WID mismatch warp=%0d", warp);
      1: if (commit.gpr_dst != 2 || commit.gpr_data[0] != 3)
           $fatal(1, "MOVI mismatch warp=%0d", warp);
      2: if (commit.gpr_dst != 3 || commit.gpr_data[4] != warp + 3)
           $fatal(1, "ADD mismatch warp=%0d", warp);
      3: if (commit.completion_class != COMPLETION_MULTIPLIER ||
             commit.gpr_dst != 4 ||
             commit.gpr_data[2] != (warp + 3) * 3)
           $fatal(1, "MUL mismatch warp=%0d", warp);
      4: if (commit.gpr_dst != 5 ||
             commit.gpr_data[6] != (warp + 3) * 4)
           $fatal(1, "dependent ADD mismatch warp=%0d", warp);
      5: if (commit.writes_gpr || commit.writes_pred)
           $fatal(1, "EXIT produced a write warp=%0d", warp);
      default: $fatal(1, "extra commit warp=%0d", warp);
    endcase
    expected_sequence[warp]++;
    observed_commits[warp]++;
    if (launched_warps == WARPS) begin
      $fwrite(trace_file,
              "C %0d %0d %0d %08x %08x %02x %02x %0d %0x %02x",
              commit.epoch, commit.warp_id, commit.sequence_number, commit.pc,
              commit.instruction, commit.active_mask, commit.write_mask,
              commit.writes_gpr,
              commit.writes_gpr ? commit.gpr_dst : 0, commit.gpr_mask);
      for (int lane = 0; lane < LANES; lane++)
        $fwrite(trace_file, " %08x", commit.gpr_data[lane]);
      $fwrite(trace_file, " %0d %0d %02x %02x\n",
              commit.writes_pred,
              commit.writes_pred ? commit.pred_dst : 0,
              commit.pred_mask, commit.pred_data);
    end
  endtask

  task automatic run_kernel(input int unsigned warps,
                            output logic [63:0] measured_cycles);
    start_kernel(warps);
    repeat (300) begin
      @(negedge clk);
      #1;
      if (fault)
        $fatal(1, "kernel fault code=%0d pc=%0d", fault_code, fault_pc);
      if (commit_valid) check_commit(warps);
      if (done) begin
        if (running || issue_count != 64'(warps * 6) ||
            commit_count != 64'(warps * 6))
          $fatal(1, "drain/counter mismatch warps=%0d issue=%0d commit=%0d",
                 warps, issue_count, commit_count);
        for (int warp = 0; warp < warps; warp++)
          if (observed_commits[warp] != 6)
            $fatal(1, "warp=%0d commit count=%0d",
                   warp, observed_commits[warp]);
        measured_cycles = cycle_count;
        return;
      end
    end
    $fatal(1, "kernel timed out warps=%0d", warps);
  endtask

  initial begin
    rst = 1;
    clear = 0;
    prog_valid = 0;
    prog_addr = 0;
    prog_data = 0;
    launch_valid = 0;
    launch_pc = 0;
    launch_warp_count = 0;
    trace_file = $fopen("build/rtl_four_warp.trace", "w");
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst = 0;

    program_word(0, 32'h74040001);
    program_word(1, 32'h38080003);
    program_word(2, 32'h040c4800);
    program_word(3, 32'h0c10c800);
    program_word(4, 32'h04150c00);
    program_word(5, 32'h78000000);

    run_kernel(1, one_warp_cycles);
    pulse_clear();
    run_kernel(4, four_warp_cycles);
    pulse_clear();
    run_kernel(4, relaunch_cycles);

    if (relaunch_cycles != four_warp_cycles)
      $fatal(1, "relaunch timing changed first=%0d second=%0d",
             four_warp_cycles, relaunch_cycles);

    if ((24 * one_warp_cycles) <= (6 * four_warp_cycles))
      $fatal(1, "four warps did not improve IPC one_cycles=%0d four_cycles=%0d",
             one_warp_cycles, four_warp_cycles);
    if(!counter_saturated||diagnostic_count[0]!=3)
      $fatal(1,"diagnostic counter did not saturate count=%0d sticky=%b",diagnostic_count[0],counter_saturated);

    $display("PASS tb_four_warp_core one_cycles=%0d four_cycles=%0d relaunch_cycles=%0d one_ipc_x1000=%0d four_ipc_x1000=%0d",
             one_warp_cycles, four_warp_cycles, relaunch_cycles,
             6000 / one_warp_cycles, 24000 / four_warp_cycles);
    $fclose(trace_file);
    $finish;
  end
endmodule
