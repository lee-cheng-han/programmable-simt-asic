module simt_core #(
  parameter int unsigned IMEM_WORDS = 64,
  parameter int unsigned IMEM_ADDR_W = $clog2(IMEM_WORDS),
  parameter bit USE_IHP_IMEM = 1'b0,
  parameter bit USE_IHP_DATA_SRAM = 1'b0,
  parameter int unsigned BARRIER_TIMEOUT_CYCLES = 256
) (
  input  logic clk,
  input  logic rst,
  input  logic clear_i,
  input  logic prog_valid_i,
  input  logic [IMEM_ADDR_W-1:0] prog_addr_i,
  input  logic [31:0] prog_data_i,
  input  logic launch_valid_i,
  output logic launch_ready_o,
  input  logic [31:0] launch_pc_i,
  input  logic [2:0] launch_warp_count_i,
  input  logic fetch_response_ready_i,
  input  logic execute_completion_ready_i,
  input  logic commit_ready_i,
  output logic running_o,
  output logic done_o,
  output logic fault_o,
  output logic [31:0] fault_pc_o,
  output simt_gpu_pkg::fault_code_t fault_code_o,
  output logic commit_valid_o,
  output simt_gpu_pkg::completion_record_t commit_o,
  output logic [63:0] cycle_count_o,
  output logic [63:0] issue_count_o,
  output logic [63:0] commit_count_o
);
  import simt_gpu_pkg::*;
  import simt_isa_pkg::*;

  logic [WARPS-1:0] warp_valid_q;
  logic [WARPS-1:0][31:0] warp_pc_q;
  logic [WARPS-1:0][INSTRUCTION_SEQUENCE_WIDTH-1:0] warp_sequence_q;
  lane_mask_t warp_active_mask_q [WARPS];
  /* verilator lint_off WIDTHTRUNC */
  logic [31:0] stack_reconv_q [WARPS][SIMT_STACK_DEPTH];
  logic [31:0] stack_deferred_pc_q [WARPS][SIMT_STACK_DEPTH];
  lane_mask_t stack_deferred_mask_q [WARPS][SIMT_STACK_DEPTH];
  lane_mask_t stack_union_mask_q [WARPS][SIMT_STACK_DEPTH];
  logic stack_deferred_q [WARPS][SIMT_STACK_DEPTH];
  logic [WARPS-1:0][$clog2(SIMT_STACK_DEPTH+1)-1:0] stack_depth_q;
  logic [WARPS-1:0] ssy_valid_q;
  logic [KERNEL_EPOCH_WIDTH-1:0] epoch_q;
  logic launched_q, done_q;
  logic[WARPS-1:0]resident_warps_q,barrier_wait_q;
  logic [WARPS-1:0][31:0] barrier_pc_q;
  localparam int unsigned BARRIER_TIMEOUT_WIDTH =
    BARRIER_TIMEOUT_CYCLES <= 1 ? 1 : $clog2(BARRIER_TIMEOUT_CYCLES);
  logic [BARRIER_TIMEOUT_WIDTH-1:0] barrier_timeout_q;
  logic barrier_release, barrier_arrival, barrier_release_with_arrival;
  logic barrier_timeout_fault;
  logic [31:0] barrier_fault_pc;
  logic barrier_fault_pc_found;

  logic [WARPS-1:0][31:0] warp_instruction;
  logic [WARPS-1:0][31:0] fetch_buffer_pc;
  logic [WARPS-1:0] fetch_buffer_valid;
  logic fetch_request_valid;
  logic [WARP_ID_WIDTH-1:0] fetch_request_warp;
  logic [IMEM_ADDR_W-1:0] fetch_request_addr;
  logic [WARPS-1:0] legal, pred_enable, pred_invert, guard_exec;
  opcode_t opcode [WARPS];
  logic [WARPS-1:0][1:0] pred_index;
  logic [WARPS-1:0][3:0] rd, ra, rb;
  logic signed [WARPS-1:0][9:0] imm;
  logic [WARPS-1:0] uses_ra, uses_rb, writes_gpr, writes_pred;
  logic [WARPS-1:0] is_load, is_store, is_branch, supported;
  logic [WARPS-1:0][REGS_PER_THREAD-1:0] warp_gpr_sources;
  logic [WARPS-1:0][PREDS_PER_THREAD-1:0] warp_pred_sources;
  logic [WARPS-1:0] scheduler_request, scheduler_grant;
  logic scheduler_valid;
  logic [WARP_ID_WIDTH-1:0] scheduler_warp;
  logic issue_fire, selected_is_multiply, selected_is_memory;
  logic selected_is_store,selected_is_shared,selected_result_ready;

  opcode_t selected_opcode;
  logic selected_pred_enable, selected_pred_invert, selected_guard_exec;
  logic selected_uses_ra, selected_uses_rb;
  logic [1:0] selected_pred_index;
  logic [3:0] selected_rd, selected_ra, selected_rb;
  logic signed [9:0] selected_imm;
  logic selected_writes_gpr, selected_writes_pred;
  logic [31:0] selected_pc, selected_instruction;
  lane_mask_t selected_active_mask;

  word_t [LANES-1:0] src_a, src_b, special, alu_result;
  lane_mask_t pred_mask, execute_mask, gpr_mask, pred_write_mask;
  lane_mask_t candidate_predicate, candidate_execute_mask;
  lane_mask_t alu_pred_result, branch_condition;
  word_t [LANES-1:0] memory_address, store_data;
  logic alu_unsupported, alu_result_ready, mul_issue_ready;

  logic [WARPS-1:0][REGS_PER_THREAD-1:0] gpr_pending;
  logic [WARPS-1:0][PREDS_PER_THREAD-1:0] pred_pending;
  logic scoreboard_ready;

  logic alu_completion_v, alu_completion_ready;
  completion_record_t alu_completion;
  logic [1:0] alu_occupancy;
  logic mul_completion_v, mul_completion_ready;
  completion_record_t mul_completion;
  logic [1:0] mul_occupancy;
  logic [MULTIPLIER_LATENCY-1:0] mul_stage_valid;
  logic [2:0] source_valid, source_ready;
  completion_record_t sources [3];
  logic completion_v, completion_accept, writeback_enqueue_ready;
  completion_record_t completion;
  logic writeback_completion_v, writeback_completion_ready;
  completion_record_t writeback_completion;
  logic [1:0] writeback_occupancy;
  logic [1:0] selected_completion_source;
  logic memory_completion_v,memory_completion_ready,memory_request_ready;
  completion_record_t memory_completion;
  logic memory_fault;fault_code_t memory_fault_code;logic[31:0]memory_fault_pc;
  logic[WARPS-1:0]memory_warp_busy;logic[2:0]memory_tracker_occupancy;

  logic wb_commit_v, wb_gpr_v, wb_pred_v;
  logic [WARP_ID_WIDTH-1:0] wb_gpr_warp, wb_pred_warp, clear_warp;
  logic [REG_INDEX_WIDTH-1:0] wb_gpr_reg, clear_gpr;
  logic [PRED_INDEX_WIDTH-1:0] wb_pred_index, clear_pred;
  lane_mask_t wb_gpr_mask, wb_pred_mask, wb_pred_data;
  word_t [LANES-1:0] wb_gpr_data;
  logic clear_gpr_v, clear_pred_v, stale_cancel;
  logic [KERNEL_EPOCH_WIDTH-1:0] clear_epoch;
  logic [INSTRUCTION_SEQUENCE_WIDTH-1:0] clear_sequence;

  logic fatal_now, fault_valid, busy_program_fault;
  logic fetch_range_fault, illegal_fault, unsupported_fault;
  logic control_fault;
  fault_code_t control_fault_code;
  lane_mask_t branch_taken_mask, branch_not_taken_mask;
  logic branch_divergent;
  logic [31:0] selected_fault_pc;
  logic [5:0] simultaneous_causes;

  warp_instruction_frontend #(
    .IMEM_WORDS(IMEM_WORDS),
    .IMEM_ADDR_W(IMEM_ADDR_W),
    .WARPS(WARPS),
    .WARP_ID_W(WARP_ID_WIDTH),
    .USE_IHP_IMEM(USE_IHP_IMEM)
  ) frontend_u (
    .clk(clk),
    .rst(rst),
    .clear_i(clear_i),
    .flush_i(fatal_now),
    .prog_valid_i(prog_valid_i && !launched_q),
    .prog_addr_i(prog_addr_i),
    .prog_data_i(prog_data_i),
    .warp_active_i(warp_valid_q),
    .warp_pc_i(warp_pc_q),
    .consume_valid_i(issue_fire),
    .consume_warp_i(scheduler_warp),
    .response_ready_i(fetch_response_ready_i),
    .buffer_valid_o(fetch_buffer_valid),
    .buffer_pc_o(fetch_buffer_pc),
    .buffer_instruction_o(warp_instruction),
    .request_valid_o(fetch_request_valid),
    .request_warp_o(fetch_request_warp),
    .request_addr_o(fetch_request_addr)
  );

  for (genvar warp = 0; warp < WARPS; warp++) begin : gen_decode
    instruction_decoder decoder_u (
      .instr_i(warp_instruction[warp]), .legal_o(legal[warp]),
      .opcode_o(opcode[warp]), .pred_enable_o(pred_enable[warp]),
      .pred_invert_o(pred_invert[warp]), .guard_exec_o(guard_exec[warp]),
      .pred_o(pred_index[warp]), .rd_o(rd[warp]), .ra_o(ra[warp]),
      .rb_o(rb[warp]), .imm_o(imm[warp]), .uses_ra_o(uses_ra[warp]),
      .uses_rb_o(uses_rb[warp]), .writes_gpr_o(writes_gpr[warp]),
      .writes_pred_o(writes_pred[warp]), .is_load_o(is_load[warp]),
      .is_store_o(is_store[warp]), .is_branch_o(is_branch[warp]));

    always_comb begin
      supported[warp] = legal[warp] &&
                        (!is_branch[warp] || opcode[warp] == OP_BRA ||
                         opcode[warp] == OP_SSY);
      warp_gpr_sources[warp] = '0;
      warp_pred_sources[warp] = '0;
      if (uses_ra[warp]) warp_gpr_sources[warp][ra[warp]] = 1'b1;
      if (uses_rb[warp]) warp_gpr_sources[warp][rb[warp]] = 1'b1;
      if (pred_enable[warp])
        warp_pred_sources[warp][pred_index[warp]] = 1'b1;
      scheduler_request[warp] =
        warp_valid_q[warp] && fetch_buffer_valid[warp] &&
        fetch_buffer_pc[warp] == warp_pc_q[warp] &&
        supported[warp] &&
        !memory_warp_busy[warp] &&
        !barrier_wait_q[warp] &&
        !(|(gpr_pending[warp] & warp_gpr_sources[warp])) &&
        !(writes_gpr[warp] && gpr_pending[warp][rd[warp]]) &&
        !(|(pred_pending[warp] & warp_pred_sources[warp])) &&
        !(writes_pred[warp] && pred_pending[warp][rd[warp][1:0]]);
    end
  end

  round_robin_arbiter #(.REQUESTERS(WARPS)) scheduler_u (
    .clk(clk), .rst(rst), .clear_i(clear_i || fatal_now),
    .request_i(scheduler_request), .grant_valid_o(scheduler_valid),
    .grant_index_o(scheduler_warp), .grant_onehot_o(scheduler_grant),
    .grant_accept_i(issue_fire));
  assign barrier_release=launched_q&&resident_warps_q!='0&&
                         (barrier_wait_q&resident_warps_q)==resident_warps_q;
  assign barrier_arrival=scheduler_valid&&selected_opcode==OP_BAR;
  assign barrier_release_with_arrival=launched_q&&resident_warps_q!='0&&
    ((barrier_wait_q|(barrier_arrival?(WARPS'(1'b1)<<scheduler_warp):'0))&
      resident_warps_q)==resident_warps_q;
  assign barrier_timeout_fault=BARRIER_TIMEOUT_CYCLES>0&&
    barrier_wait_q!='0&&!barrier_release_with_arrival&&
    barrier_timeout_q==BARRIER_TIMEOUT_WIDTH'(BARRIER_TIMEOUT_CYCLES-1);
  always_comb begin
    barrier_fault_pc='0;
    barrier_fault_pc_found=1'b0;
    for(int unsigned warp=0;warp<WARPS;warp++)
      if(barrier_wait_q[warp]&&!barrier_fault_pc_found)begin
        barrier_fault_pc=barrier_pc_q[warp];
        barrier_fault_pc_found=1'b1;
      end
  end

  always_comb begin
    selected_opcode = opcode[scheduler_warp];
    selected_pred_enable = pred_enable[scheduler_warp];
    selected_pred_invert = pred_invert[scheduler_warp];
    selected_guard_exec = guard_exec[scheduler_warp];
    selected_pred_index = pred_index[scheduler_warp];
    selected_uses_ra = uses_ra[scheduler_warp];
    selected_uses_rb = uses_rb[scheduler_warp];
    selected_rd = rd[scheduler_warp];
    selected_ra = ra[scheduler_warp];
    selected_rb = rb[scheduler_warp];
    selected_imm = imm[scheduler_warp];
    selected_writes_gpr = writes_gpr[scheduler_warp];
    selected_writes_pred = writes_pred[scheduler_warp];
    selected_pc = warp_pc_q[scheduler_warp];
    selected_instruction = warp_instruction[scheduler_warp];
    selected_active_mask = warp_active_mask_q[scheduler_warp];
    selected_is_multiply = selected_opcode == OP_MUL;
    selected_is_memory = is_load[scheduler_warp]||is_store[scheduler_warp];
    selected_is_store = is_store[scheduler_warp];
    selected_is_shared = selected_opcode==OP_LD_S||selected_opcode==OP_ST_S;
  end

  always_comb begin
    if(selected_is_memory) selected_result_ready=memory_request_ready;
    else if(selected_is_multiply) selected_result_ready=mul_issue_ready;
    else selected_result_ready=alu_result_ready;
    issue_fire = scheduler_valid && selected_result_ready &&
                 scoreboard_ready && !fatal_now;
  end

  vector_register_file gpr_u (
    .clk(clk), .rst(rst),
    .read_a_valid_i(scheduler_valid && selected_uses_ra),
    .read_b_valid_i(scheduler_valid && selected_uses_rb),
    .read_warp_i(scheduler_warp), .read_ra_i(selected_ra),
    .read_rb_i(selected_rb), .read_a_o(src_a), .read_b_o(src_b),
    .write_valid_i(wb_gpr_v), .write_warp_i(wb_gpr_warp),
    .write_reg_i(wb_gpr_reg), .write_lane_mask_i(wb_gpr_mask),
    .write_data_i(wb_gpr_data));
  predicate_register_file pred_u (
    .clk(clk), .rst(rst),
    .read_valid_i(scheduler_valid && selected_pred_enable),
    .read_warp_i(scheduler_warp), .read_pred_i(selected_pred_index),
    .read_mask_o(pred_mask), .write_valid_i(wb_pred_v),
    .write_warp_i(wb_pred_warp), .write_pred_i(wb_pred_index),
    .write_lane_mask_i(wb_pred_mask), .write_data_i(wb_pred_data));

  for (genvar lane = 0; lane < LANES; lane++) begin : gen_special
    always_comb begin
      special[lane] = '0;
      case (selected_imm)
        10'sd0, 10'sd3: special[lane] = word_t'(lane);
        10'sd1: special[lane] = word_t'(scheduler_warp);
        10'sd5: special[lane] = word_t'(LANES);
        default: special[lane] = '0;
      endcase
    end
  end

  vector_integer_alu alu_u (
    .valid_i(scheduler_valid), .opcode_i(selected_opcode),
    .active_mask_i(selected_active_mask), .predicate_mask_i(pred_mask),
    .predicate_invert_i(selected_pred_invert),
    .guard_exec_i(selected_guard_exec),
    .writes_gpr_i(selected_writes_gpr),
    .writes_pred_i(selected_writes_pred), .src_a_i(src_a), .src_b_i(src_b),
    .imm_i(selected_imm), .special_i(special),
    .execute_mask_o(execute_mask), .gpr_write_mask_o(gpr_mask),
    .pred_write_mask_o(pred_write_mask), .result_o(alu_result),
    .predicate_result_o(alu_pred_result),
    .branch_condition_o(branch_condition),
    .memory_address_o(memory_address), .store_data_o(store_data),
    .unsupported_operation_o(alu_unsupported));

  dependency_scoreboard scoreboard_u (
    .clk(clk), .rst(rst), .clear_i(clear_i),
    .issue_warp_i(scheduler_warp),
    .issue_gpr_sources_i(warp_gpr_sources[scheduler_warp]),
    .issue_gpr_dest_valid_i(selected_writes_gpr),
    .issue_gpr_dest_i(selected_rd),
    .issue_pred_sources_i(warp_pred_sources[scheduler_warp]),
    .issue_pred_dest_valid_i(selected_writes_pred),
    .issue_pred_dest_i(selected_rd[1:0]), .issue_epoch_i(epoch_q),
    .issue_sequence_i(warp_sequence_q[scheduler_warp]),
    .issue_ready_o(scoreboard_ready), .issue_accept_i(issue_fire),
    .clear_gpr_valid_i(clear_gpr_v), .clear_pred_valid_i(clear_pred_v),
    .clear_epoch_i(clear_epoch), .clear_warp_i(clear_warp),
    .clear_sequence_i(clear_sequence), .clear_gpr_i(clear_gpr),
    .clear_pred_i(clear_pred), .gpr_pending_o(gpr_pending),
    .pred_pending_o(pred_pending));

  alu_completion_stage alu_completion_u (
    .clk(clk), .rst(rst), .flush_i(clear_i || fatal_now),
    .result_valid_i(issue_fire && !selected_is_multiply&&!selected_is_memory),
    .result_ready_o(alu_result_ready), .epoch_i(epoch_q),
    .warp_id_i(scheduler_warp),
    .sequence_number_i(warp_sequence_q[scheduler_warp]),
    .pc_i(selected_pc), .instruction_i(selected_instruction),
    .active_mask_i(selected_active_mask), .write_mask_i(execute_mask),
    .writes_gpr_i(selected_writes_gpr), .gpr_dst_i(selected_rd),
    .gpr_mask_i(gpr_mask), .gpr_data_i(alu_result),
    .writes_pred_i(selected_writes_pred),
    .pred_dst_i(selected_rd[1:0]), .pred_mask_i(pred_write_mask),
    .pred_data_i(alu_pred_result), .completion_valid_o(alu_completion_v),
    .completion_ready_i(alu_completion_ready),
    .completion_o(alu_completion), .occupancy_o(alu_occupancy));

  vector_multiplier_pipeline multiplier_u (
    .clk(clk), .rst(rst), .flush_i(clear_i || fatal_now),
    .issue_valid_i(issue_fire && selected_is_multiply),
    .issue_ready_o(mul_issue_ready), .epoch_i(epoch_q),
    .warp_id_i(scheduler_warp),
    .sequence_number_i(warp_sequence_q[scheduler_warp]),
    .pc_i(selected_pc), .instruction_i(selected_instruction),
    .active_mask_i(selected_active_mask), .write_mask_i(execute_mask),
    .gpr_dst_i(selected_rd), .src_a_i(src_a), .src_b_i(src_b),
    .completion_valid_o(mul_completion_v),
    .completion_ready_i(mul_completion_ready),
    .completion_o(mul_completion), .queue_occupancy_o(mul_occupancy),
    .stage_valid_o(mul_stage_valid));

  memory_subsystem #(.USE_IHP_DATA_SRAM(USE_IHP_DATA_SRAM)) memory_u(
    .clk,.rst,.clear_i,.fatal_i(fatal_now),
    .request_valid_i(issue_fire&&selected_is_memory),
    .request_ready_o(memory_request_ready),.request_shared_i(selected_is_shared),
    .request_store_i(selected_is_store),.request_epoch_i(epoch_q),
    .request_warp_i(scheduler_warp),.request_sequence_i(warp_sequence_q[scheduler_warp]),
    .request_pc_i(selected_pc),.request_instruction_i(selected_instruction),
    .request_active_mask_i(selected_active_mask),.request_mask_i(execute_mask),
    .request_gpr_dst_i(selected_rd),.request_address_i(memory_address),
    .request_store_data_i(store_data),.completion_valid_o(memory_completion_v),
    .completion_ready_i(memory_completion_ready),.completion_o(memory_completion),
    .fault_valid_o(memory_fault),.fault_code_o(memory_fault_code),
    .fault_pc_o(memory_fault_pc),.warp_busy_o(memory_warp_busy),
    .tracker_occupancy_o(memory_tracker_occupancy));

  always_comb begin
    candidate_predicate = pred_mask ^ {LANES{selected_pred_invert}};
    candidate_execute_mask = '0;
    if (scheduler_valid)
      candidate_execute_mask = selected_active_mask &
        ({LANES{!selected_guard_exec}} | candidate_predicate);
    branch_taken_mask = candidate_execute_mask;
    branch_not_taken_mask = selected_active_mask & ~candidate_execute_mask;
    branch_divergent = selected_opcode == OP_BRA &&
                       branch_taken_mask != '0 &&
                       branch_not_taken_mask != '0;
    control_fault = 1'b0;
    control_fault_code = FAULT_NONE;
    if(barrier_timeout_fault)begin
      control_fault=1'b1;
      control_fault_code=FAULT_BARRIER_DEADLOCK;
    end else if (scheduler_valid) begin
      case (selected_opcode)
        OP_SSY: if (stack_depth_q[scheduler_warp] ==
                    $clog2(SIMT_STACK_DEPTH+1)'(SIMT_STACK_DEPTH)) begin
          control_fault = 1'b1;
          control_fault_code = FAULT_SIMT_STACK_OVERFLOW;
        end
        OP_SYNC: begin
          if (stack_depth_q[scheduler_warp] == 0) begin
            control_fault = 1'b1;
            control_fault_code = FAULT_SIMT_STACK_UNDERFLOW;
          end else if (stack_reconv_q[scheduler_warp]
                         [stack_depth_q[scheduler_warp]-1'b1] != selected_pc) begin
            control_fault = 1'b1;
            control_fault_code = FAULT_SIMT_CONTROL;
          end
        end
        OP_BRA: if (branch_divergent &&
                    (!ssy_valid_q[scheduler_warp] ||
                     stack_depth_q[scheduler_warp] == 0)) begin
          control_fault = 1'b1;
          control_fault_code = FAULT_SIMT_CONTROL;
        end
        OP_BAR: if(selected_pred_enable||selected_active_mask!={LANES{1'b1}})begin
          control_fault=1'b1;control_fault_code=FAULT_BARRIER_VIOLATION;
        end
        default: begin end
      endcase
    end
  end

  always_comb begin
    source_valid = '0;
    source_valid[0] = alu_completion_v;
    source_valid[1] = mul_completion_v;
    source_valid[2] = memory_completion_v;
    sources[0] = alu_completion;
    sources[1] = mul_completion;
    sources[2] = memory_completion;
    alu_completion_ready = source_ready[0];
    mul_completion_ready = source_ready[1];
    memory_completion_ready = source_ready[2];
  end
  completion_arbiter arbiter_u (
    .clk(clk), .rst(rst), .clear_i(clear_i || fatal_now),
    .source_valid_i(source_valid), .source_ready_o(source_ready),
    .source_completion_i(sources), .completion_valid_o(completion_v),
    .completion_ready_i(completion_accept), .completion_o(completion),
    .selected_source_o(selected_completion_source));
  completion_queue writeback_queue_u (
    .clk(clk), .rst(rst), .flush_i(clear_i || fatal_now),
    .completion_valid_i(completion_v && execute_completion_ready_i),
    .completion_ready_o(writeback_enqueue_ready),
    .completion_i(completion),
    .completion_valid_o(writeback_completion_v),
    .completion_ready_i(writeback_completion_ready),
    .completion_o(writeback_completion), .occupancy_o(writeback_occupancy));
  architectural_writeback wb_u (
    .clk(clk), .rst(rst), .fatal_i(fatal_now), .current_epoch_i(epoch_q),
    .completion_valid_i(writeback_completion_v),
    .completion_ready_o(writeback_completion_ready),
    .completion_i(writeback_completion),
    .commit_valid_o(wb_commit_v), .commit_ready_i(commit_ready_i),
    .commit_o(commit_o), .stale_cancel_o(stale_cancel),
    .gpr_write_valid_o(wb_gpr_v), .gpr_write_warp_o(wb_gpr_warp),
    .gpr_write_reg_o(wb_gpr_reg), .gpr_write_mask_o(wb_gpr_mask),
    .gpr_write_data_o(wb_gpr_data), .pred_write_valid_o(wb_pred_v),
    .pred_write_warp_o(wb_pred_warp),
    .pred_write_pred_o(wb_pred_index), .pred_write_mask_o(wb_pred_mask),
    .pred_write_data_o(wb_pred_data),
    .clear_gpr_valid_o(clear_gpr_v),
    .clear_pred_valid_o(clear_pred_v), .clear_epoch_o(clear_epoch),
    .clear_warp_o(clear_warp), .clear_sequence_o(clear_sequence),
    .clear_gpr_o(clear_gpr), .clear_pred_o(clear_pred));

  always_comb begin
    fetch_range_fault = 1'b0;
    illegal_fault = 1'b0;
    unsupported_fault = 1'b0;
    selected_fault_pc = '0;
    for (int unsigned warp = 0; warp < WARPS; warp++) begin
      if (!fetch_range_fault && warp_valid_q[warp] &&
          warp_pc_q[warp] >= IMEM_WORDS) begin
        fetch_range_fault = 1'b1;
        selected_fault_pc = warp_pc_q[warp];
      end
    end
    if (!fetch_range_fault) begin
      for (int unsigned warp = 0; warp < WARPS; warp++) begin
        if (!illegal_fault && warp_valid_q[warp] &&
            fetch_buffer_valid[warp] && !legal[warp]) begin
          illegal_fault = 1'b1;
          selected_fault_pc = warp_pc_q[warp];
        end
      end
    end
    if (!fetch_range_fault && !illegal_fault) begin
      for (int unsigned warp = 0; warp < WARPS; warp++) begin
        if (!unsupported_fault && warp_valid_q[warp] &&
            fetch_buffer_valid[warp] && legal[warp] && !supported[warp]) begin
          unsupported_fault = 1'b1;
          selected_fault_pc = warp_pc_q[warp];
        end
      end
    end
  end

  assign completion_accept = execute_completion_ready_i &&
                             writeback_enqueue_ready;
  assign busy_program_fault = prog_valid_i && launched_q;
  assign launch_ready_o = !launched_q && !fault_valid &&
                          launch_warp_count_i >= 3'd1 &&
                          launch_warp_count_i <= 3'(WARPS) &&
                          alu_occupancy == 0 && mul_occupancy == 0 &&
                          mul_stage_valid == 0 && !completion_v &&
                          writeback_occupancy == 0&&memory_tracker_occupancy==0;
  assign running_o = launched_q && !done_q && !fault_valid;
  assign done_o = done_q;
  assign fault_o = fault_valid;
  assign commit_valid_o = wb_commit_v;

  fatal_fault_controller fault_u (
    .clk(clk), .rst(rst), .clear_i(clear_i),
    .host_fault_i(busy_program_fault), .host_fault_pc_i(selected_fault_pc),
    .fetch_fault_i(fetch_range_fault), .fetch_fault_pc_i(selected_fault_pc),
    .illegal_fault_i(illegal_fault), .illegal_fault_pc_i(selected_fault_pc),
    .unsupported_fault_i(unsupported_fault),
    .unsupported_fault_pc_i(selected_fault_pc),
    .memory_fault_i(memory_fault),.memory_fault_code_i(memory_fault_code),
    .memory_fault_pc_i(memory_fault_pc),
    .control_fault_i(control_fault),
    .control_fault_code_i(control_fault_code),
    .control_fault_pc_i(barrier_timeout_fault?barrier_fault_pc:selected_pc),
    .fatal_now_o(fatal_now), .fault_valid_o(fault_valid),
    .fault_code_o(fault_code_o), .fault_pc_o(fault_pc_o),
    .simultaneous_causes_o(simultaneous_causes));

  always_ff @(posedge clk) begin
    if (rst) begin
      warp_valid_q <= '0;
      for (int unsigned warp = 0; warp < WARPS; warp++) begin
        warp_pc_q[warp] <= '0;
        warp_sequence_q[warp] <= '0;
        warp_active_mask_q[warp] <= '0;
        stack_depth_q[warp] <= '0;
        ssy_valid_q[warp] <= 1'b0;
        for (int unsigned entry = 0; entry < SIMT_STACK_DEPTH; entry++) begin
          stack_reconv_q[warp][entry] <= '0;
          stack_deferred_pc_q[warp][entry] <= '0;
          stack_deferred_mask_q[warp][entry] <= '0;
          stack_union_mask_q[warp][entry] <= '0;
          stack_deferred_q[warp][entry] <= 1'b0;
        end
      end
      epoch_q <= '0;
      resident_warps_q<='0;barrier_wait_q<='0;barrier_pc_q<='0;
      barrier_timeout_q<='0;
      launched_q <= 1'b0;
      done_q <= 1'b0;
      cycle_count_o <= '0;
      issue_count_o <= '0;
      commit_count_o <= '0;
    end else if (clear_i) begin
      warp_valid_q <= '0;
      for (int unsigned warp = 0; warp < WARPS; warp++) begin
        warp_pc_q[warp] <= '0;
        warp_sequence_q[warp] <= '0;
        warp_active_mask_q[warp] <= '0;
        stack_depth_q[warp] <= '0;
        ssy_valid_q[warp] <= 1'b0;
      end
      epoch_q <= epoch_q + 1'b1;
      resident_warps_q<='0;barrier_wait_q<='0;barrier_pc_q<='0;
      barrier_timeout_q<='0;
      launched_q <= 1'b0;
      done_q <= 1'b0;
      cycle_count_o <= '0;
      issue_count_o <= '0;
      commit_count_o <= '0;
    end else begin
      if (launch_valid_i && launch_ready_o) begin
        for (int unsigned warp = 0; warp < WARPS; warp++) begin
          warp_valid_q[warp] <= warp < launch_warp_count_i;
          warp_pc_q[warp] <= launch_pc_i;
          warp_sequence_q[warp] <= '0;
          warp_active_mask_q[warp] <= {LANES{1'b1}};
          stack_depth_q[warp] <= '0;
          ssy_valid_q[warp] <= 1'b0;
          resident_warps_q[warp]<=warp<launch_warp_count_i;
          barrier_wait_q[warp]<=1'b0;
          barrier_pc_q[warp]<='0;
        end
        launched_q <= 1'b1;
        done_q <= 1'b0;
        cycle_count_o <= '0;
        issue_count_o <= '0;
        commit_count_o <= '0;
        barrier_timeout_q<='0;
      end else if (launched_q && !done_q && !fault_valid) begin
        cycle_count_o <= cycle_count_o + 1'b1;
        if (issue_fire) issue_count_o <= issue_count_o + 1'b1;
        if (wb_commit_v && commit_ready_i)
          commit_count_o <= commit_count_o + 1'b1;
      end

      if(barrier_release)begin
        barrier_wait_q<='0;
        barrier_timeout_q<='0;
      end else if(barrier_wait_q=='0||barrier_release_with_arrival)
        barrier_timeout_q<='0;
      else if(BARRIER_TIMEOUT_CYCLES>0&&!barrier_timeout_fault)
        barrier_timeout_q<=barrier_timeout_q+1'b1;

      if (issue_fire) begin
        warp_sequence_q[scheduler_warp] <=
          warp_sequence_q[scheduler_warp] + 1'b1;
        if (selected_opcode == OP_SSY) begin
          stack_reconv_q[scheduler_warp][stack_depth_q[scheduler_warp]] <=
            selected_pc + 1'b1 + {{22{selected_imm[9]}}, selected_imm};
          stack_deferred_pc_q[scheduler_warp]
            [stack_depth_q[scheduler_warp]] <= '0;
          stack_deferred_mask_q[scheduler_warp]
            [stack_depth_q[scheduler_warp]] <= '0;
          stack_union_mask_q[scheduler_warp]
            [stack_depth_q[scheduler_warp]] <= selected_active_mask;
          stack_deferred_q[scheduler_warp]
            [stack_depth_q[scheduler_warp]] <= 1'b0;
          stack_depth_q[scheduler_warp] <=
            stack_depth_q[scheduler_warp] + 1'b1;
          ssy_valid_q[scheduler_warp] <= 1'b1;
          warp_pc_q[scheduler_warp] <= selected_pc + 1'b1;
        end else if (selected_opcode == OP_BRA) begin
          if (branch_divergent) begin
            stack_deferred_pc_q[scheduler_warp]
              [stack_depth_q[scheduler_warp]-1'b1] <= selected_pc + 1'b1;
            stack_deferred_mask_q[scheduler_warp]
              [stack_depth_q[scheduler_warp]-1'b1] <=
                branch_not_taken_mask;
            stack_union_mask_q[scheduler_warp]
              [stack_depth_q[scheduler_warp]-1'b1] <= selected_active_mask;
            stack_deferred_q[scheduler_warp]
              [stack_depth_q[scheduler_warp]-1'b1] <= 1'b1;
            warp_active_mask_q[scheduler_warp] <= branch_taken_mask;
            warp_pc_q[scheduler_warp] <=
              selected_pc + 1'b1 + {{22{selected_imm[9]}}, selected_imm};
            ssy_valid_q[scheduler_warp] <= 1'b0;
          end else if (branch_taken_mask != '0) begin
            warp_pc_q[scheduler_warp] <=
              selected_pc + 1'b1 + {{22{selected_imm[9]}}, selected_imm};
          end else begin
            warp_pc_q[scheduler_warp] <= selected_pc + 1'b1;
          end
        end else if (selected_opcode == OP_SYNC) begin
          if (stack_deferred_q[scheduler_warp]
                [stack_depth_q[scheduler_warp]-1'b1]) begin
            warp_pc_q[scheduler_warp] <=
              stack_deferred_pc_q[scheduler_warp]
                [stack_depth_q[scheduler_warp]-1'b1];
            warp_active_mask_q[scheduler_warp] <=
              stack_deferred_mask_q[scheduler_warp]
                [stack_depth_q[scheduler_warp]-1'b1];
            stack_deferred_q[scheduler_warp]
              [stack_depth_q[scheduler_warp]-1'b1] <= 1'b0;
          end else begin
            warp_pc_q[scheduler_warp] <= selected_pc + 1'b1;
            warp_active_mask_q[scheduler_warp] <=
              stack_union_mask_q[scheduler_warp]
                [stack_depth_q[scheduler_warp]-1'b1];
            stack_depth_q[scheduler_warp] <=
              stack_depth_q[scheduler_warp] - 1'b1;
            ssy_valid_q[scheduler_warp] <= 1'b0;
          end
        end else if(selected_opcode==OP_BAR)begin
          warp_pc_q[scheduler_warp]<=selected_pc+1'b1;
          barrier_wait_q[scheduler_warp]<=1'b1;
          barrier_pc_q[scheduler_warp]<=selected_pc;
        end else if (selected_opcode == OP_EXIT) begin
          warp_pc_q[scheduler_warp] <= selected_pc + 1'b1;
          warp_active_mask_q[scheduler_warp] <=
            selected_active_mask & ~execute_mask;
          if ((selected_active_mask & ~execute_mask) == '0 &&
              stack_depth_q[scheduler_warp] == 0)
            warp_valid_q[scheduler_warp] <= 1'b0;
        end else begin
          warp_pc_q[scheduler_warp] <= selected_pc + 1'b1;
        end
      end

      if (launched_q && warp_valid_q == '0 && alu_occupancy == 0 &&
          mul_occupancy == 0 && mul_stage_valid == '0 && !completion_v &&
          writeback_occupancy == 0 &&
          memory_tracker_occupancy == 0 &&
          gpr_pending == '0 && pred_pending == '0 && !fatal_now)
        done_q <= 1'b1;
    end
  end

`ifndef SYNTHESIS
  for (genvar warp = 0; warp < WARPS; warp++) begin : gen_stack_properties
    property p_stack_depth_in_range;
      @(posedge clk) disable iff (rst || clear_i)
        stack_depth_q[warp] <=
          $clog2(SIMT_STACK_DEPTH+1)'(SIMT_STACK_DEPTH);
    endproperty
    assert property (p_stack_depth_in_range);

    property p_stack_state_stable_without_selected_control;
      @(posedge clk) disable iff (rst || clear_i)
        !(issue_fire && scheduler_warp == WARP_ID_WIDTH'(warp) &&
          (selected_opcode == OP_SSY || selected_opcode == OP_BRA ||
           selected_opcode == OP_SYNC))
        |=> $stable(stack_depth_q[warp]);
    endproperty
    assert property (p_stack_state_stable_without_selected_control);
  end

  property p_control_fault_suppresses_issue;
    @(posedge clk) disable iff (rst || clear_i)
      control_fault |-> !issue_fire;
  endproperty
  assert property (p_control_fault_suppresses_issue);

  property p_barrier_release_requires_all_residents;
    @(posedge clk) disable iff (rst || clear_i)
      barrier_release |-> resident_warps_q != '0 &&
        (barrier_wait_q & resident_warps_q) == resident_warps_q;
  endproperty
  assert property (p_barrier_release_requires_all_residents);

  for (genvar warp = 0; warp < WARPS; warp++) begin : gen_barrier_properties
    property p_waiting_warp_cannot_request;
      @(posedge clk) disable iff (rst || clear_i)
        barrier_wait_q[warp] |-> !scheduler_request[warp];
    endproperty
    assert property (p_waiting_warp_cannot_request);
  end

  always_ff @(posedge clk) begin
    if (!rst && !clear_i && issue_fire) begin
      assert (scheduler_grant[scheduler_warp]);
      assert (scoreboard_ready);
      assert (!alu_unsupported);
      if (selected_opcode != OP_BRA) assert (branch_condition == '0);
      if(!selected_is_memory)
        assert (memory_address == '0 && store_data == '0);
    end
    if (!rst && !clear_i && fetch_request_valid) begin
      assert (32'(fetch_request_warp) < 32'(WARPS));
      assert (32'(fetch_request_addr) < 32'(IMEM_WORDS));
    end
    if (!rst && !clear_i && completion_v)
      assert (selected_completion_source < 3);
    if (!rst && !clear_i && fault_valid) assert (simultaneous_causes != 0);
    if (!rst && !clear_i) assert (!stale_cancel);
  end
`endif
  /* verilator lint_on WIDTHTRUNC */
endmodule
