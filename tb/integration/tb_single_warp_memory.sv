/* verilator lint_off PINCONNECTEMPTY */
module tb_single_warp_memory;
  import simt_gpu_pkg::*;import simt_isa_pkg::*;
  logic clk=0,rst,clear,prog_valid,launch_valid,launch_ready;
  logic[5:0]prog_addr;logic[31:0]prog_data,launch_pc;
  logic[2:0]launch_warp_count;logic running,done,fault,commit_valid;
  logic[31:0]fault_pc;fault_code_t fault_code;
  /* verilator lint_off UNUSEDSIGNAL */ completion_record_t commit;
  /* verilator lint_on UNUSEDSIGNAL */
  logic[63:0]cycle_count,issue_count,commit_count;int commits,checks;
  /* verilator lint_off UNUSEDSIGNAL */ logic unused_running=running;
  logic[63:0]unused_cycles=cycle_count; /* verilator lint_on UNUSEDSIGNAL */
  /* verilator lint_off BLKSEQ */ always #5 clk=~clk; /* verilator lint_on BLKSEQ */
  simt_core dut(.clk,.rst,.clear_i(clear),.prog_valid_i(prog_valid),.prog_addr_i(prog_addr),
    .prog_data_i(prog_data),.launch_valid_i(launch_valid),.launch_ready_o(launch_ready),
    .launch_pc_i(launch_pc),.launch_warp_count_i(launch_warp_count),
    .fetch_response_ready_i(1'b1),.execute_completion_ready_i(1'b1),.commit_ready_i(1'b1),
    .running_o(running),.done_o(done),.fault_o(fault),.fault_pc_o(fault_pc),
    .fault_code_o(fault_code),.commit_valid_o(commit_valid),.commit_o(commit),
    .cycle_count_o(cycle_count),.issue_count_o(issue_count),.commit_count_o(commit_count),
    .watchdog_enable_i(1'b1),.watchdog_limit_i(32'd256),.host_mem_valid_i(1'b0),
    .host_mem_shared_i(1'b0),.host_mem_write_i(1'b0),.host_mem_address_i('0),
    .host_mem_write_data_i('0),.inject_fault_i('0),.host_mem_ready_o(),.host_mem_response_valid_o(),.host_mem_response_fault_o(),
    .host_mem_read_data_o(),.debug_warp_pc_o(),.debug_active_mask_o(),
    .debug_gpr_pending_o(),.debug_pred_pending_o(),.debug_stack_depth_o(),
    .debug_resident_o(),.debug_barrier_wait_o(),.debug_memory_busy_o(),
    .debug_tracker_occupancy_o(),.debug_alu_occupancy_o(),.debug_mul_occupancy_o(),
    .debug_wb_occupancy_o(),.debug_epoch_o(),.debug_quiescent_o(),
    .debug_stack_top_o(),.debug_tracker_summary_o(),.debug_memory_completion_occupancy_o());
  function automatic logic[31:0]enc(input opcode_t op,input logic[3:0]rd,
    input logic[3:0]ra,input logic[3:0]rb,input logic[9:0]imm);
    return {op,4'b0,rd,ra,rb,imm};
  endfunction
  task automatic program_word(input logic[5:0]addr,input logic[31:0]word);
    @(negedge clk);prog_addr=addr;prog_data=word;prog_valid=1;
    @(posedge clk);@(negedge clk);prog_valid=0;
  endtask
  initial begin
    rst=1;clear=0;prog_valid=0;prog_addr=0;prog_data=0;launch_valid=0;
    launch_pc=0;launch_warp_count=1;commits=0;checks=0;
    repeat(2)@(posedge clk);@(negedge clk);rst=0;
    program_word(0,enc(OP_MOVI,1,0,0,0));
    program_word(1,enc(OP_S2R,2,0,0,3));
    program_word(2,enc(OP_ST_G,0,1,2,0));
    program_word(3,enc(OP_LD_G,3,1,0,0));
    program_word(4,enc(OP_ADD,4,3,2,0));
    program_word(5,enc(OP_EXIT,0,0,0,0));
    @(negedge clk);if(!launch_ready)$fatal(1,"launch not ready");launch_valid=1;
    @(posedge clk);@(negedge clk);launch_valid=0;
    repeat(500)begin
      @(negedge clk);
      if(commit_valid)begin
        if(commit.sequence_number!=INSTRUCTION_SEQUENCE_WIDTH'(commits))
          $fatal(1,"sequence mismatch got=%0d expected=%0d",commit.sequence_number,commits);
        if(commits==3)for(int lane=0;lane<LANES;lane++)
          if(commit.gpr_data[lane]!==32'd7)$fatal(1,"broadcast load lane=%0d",lane);
        if(commits==4)for(int lane=0;lane<LANES;lane++)
          if(commit.gpr_data[lane]!==word_t'(7+lane))$fatal(1,"dependent add lane=%0d",lane);
        commits++;checks++;
      end
      if(done||fault)break;
    end
    if(fault)$fatal(1,"memory kernel fault code=%0d pc=%0d",fault_code,fault_pc);
    if(!done||commits!=6||issue_count!=6||commit_count!=6)
      $fatal(1,"kernel drain mismatch done=%0d commits=%0d issue=%0d count=%0d",
        done,commits,issue_count,commit_count);
    $display("PASS tb_single_warp_memory commits=%0d checks=%0d",commits,checks);$finish;
  end
endmodule
