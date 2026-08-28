module memory_subsystem #(parameter bit USE_IHP_DATA_SRAM=1'b0)(
  input logic clk,input logic rst,input logic clear_i,input logic fatal_i,
  input logic request_valid_i,output logic request_ready_o,
  input logic request_shared_i,input logic request_store_i,
  input logic [simt_gpu_pkg::KERNEL_EPOCH_WIDTH-1:0] request_epoch_i,
  input logic [simt_gpu_pkg::WARP_ID_WIDTH-1:0] request_warp_i,
  input logic [simt_gpu_pkg::INSTRUCTION_SEQUENCE_WIDTH-1:0] request_sequence_i,
  input logic [31:0] request_pc_i,input logic [31:0] request_instruction_i,
  input simt_gpu_pkg::lane_mask_t request_active_mask_i,
  input simt_gpu_pkg::lane_mask_t request_mask_i,
  input logic [simt_gpu_pkg::REG_INDEX_WIDTH-1:0] request_gpr_dst_i,
  input simt_gpu_pkg::word_t [simt_gpu_pkg::LANES-1:0] request_address_i,
  input simt_gpu_pkg::word_t [simt_gpu_pkg::LANES-1:0] request_store_data_i,
  output logic completion_valid_o,input logic completion_ready_i,
  output simt_gpu_pkg::completion_record_t completion_o,
  output logic fault_valid_o,output simt_gpu_pkg::fault_code_t fault_code_o,
  output logic [31:0] fault_pc_o,
  output logic [simt_gpu_pkg::WARPS-1:0] warp_busy_o,
  output logic [2:0] tracker_occupancy_o,
  output logic [simt_gpu_pkg::MAX_MEMORY_OPS-1:0][7:0]debug_tracker_summary_o,
  output logic [1:0]debug_completion_occupancy_o,
  input logic host_valid_i,input logic host_shared_i,input logic host_write_i,
  input logic [31:0] host_address_i,input logic [31:0] host_write_data_i,
  output logic host_ready_o,output logic host_response_valid_o,
  output logic host_response_fault_o,output logic [31:0] host_read_data_o
);
  import simt_gpu_pkg::*;
  typedef enum logic[2:0]{T_FREE,T_WAIT,T_ENGINE,T_DONE,T_QUEUED} tracker_state_t;
  tracker_state_t state_q[MAX_MEMORY_OPS];
  logic shared_q[MAX_MEMORY_OPS],store_q[MAX_MEMORY_OPS];
  logic [KERNEL_EPOCH_WIDTH-1:0] epoch_q[MAX_MEMORY_OPS];
  logic [WARP_ID_WIDTH-1:0] warp_q[MAX_MEMORY_OPS];
  logic [INSTRUCTION_SEQUENCE_WIDTH-1:0] sequence_q[MAX_MEMORY_OPS];
  logic [31:0] pc_q[MAX_MEMORY_OPS],instruction_q[MAX_MEMORY_OPS];
  lane_mask_t active_q[MAX_MEMORY_OPS],mask_q[MAX_MEMORY_OPS];
  logic [REG_INDEX_WIDTH-1:0] dst_q[MAX_MEMORY_OPS];
  word_t [LANES-1:0] address_q[MAX_MEMORY_OPS],store_data_q[MAX_MEMORY_OPS];
  word_t [LANES-1:0] load_data_q[MAX_MEMORY_OPS];
  logic free_valid;logic[1:0]free_index;
  logic general_dispatch,shared_dispatch;logic[1:0]general_index,shared_index;
  logic general_active_q,shared_active_q;logic[1:0]general_tracker_q,shared_tracker_q;
  logic general_req_ready,shared_req_ready,general_resp_valid,shared_resp_valid;
  /* verilator lint_off UNUSEDSIGNAL */
  logic general_resp_fault,shared_resp_fault,general_misaligned,shared_misaligned;
  logic general_range,shared_range;
  lane_mask_t general_resp_mask,shared_resp_mask,general_pending,shared_pending;
  word_t [LANES-1:0] general_load,shared_load;logic general_busy,shared_busy;
  logic [1:0] completion_queue_occupancy;
  logic general_host_ready,shared_host_ready;
  logic general_host_response_valid,shared_host_response_valid;
  logic general_host_response_fault,shared_host_response_fault;
  logic [31:0] general_host_read_data,shared_host_read_data;
  /* verilator lint_on UNUSEDSIGNAL */
  logic queue_input_valid,queue_input_ready;completion_record_t queue_input;
  logic done_valid;logic[1:0]done_index;
  assign request_ready_o=free_valid&&!warp_busy_o[request_warp_i]&&!fatal_i;
  assign debug_completion_occupancy_o=completion_queue_occupancy;
  assign host_ready_o=tracker_occupancy_o==0&&!general_active_q&&!shared_active_q&&
    (host_shared_i?shared_host_ready:general_host_ready);
  assign host_response_valid_o=host_shared_i?shared_host_response_valid:
    general_host_response_valid;
  assign host_response_fault_o=host_shared_i?shared_host_response_fault:
    general_host_response_fault;
  assign host_read_data_o=host_shared_i?shared_host_read_data:general_host_read_data;

  always_comb begin
    warp_busy_o='0;tracker_occupancy_o='0;debug_tracker_summary_o='0;free_valid=0;free_index='0;
    general_dispatch=0;shared_dispatch=0;general_index='0;shared_index='0;
    done_valid=0;done_index='0;
    for(int i=0;i<MAX_MEMORY_OPS;i++)begin
      if(state_q[i]!=T_FREE)begin
        debug_tracker_summary_o[i]={state_q[i],shared_q[i],store_q[i],warp_q[i],1'b1};
        tracker_occupancy_o++;warp_busy_o[warp_q[i]]=1'b1;
      end else if(!free_valid)begin free_valid=1;free_index=2'(i);end
      if(state_q[i]==T_WAIT&&!shared_q[i]&&!general_dispatch&&!general_active_q)
        begin general_dispatch=1;general_index=2'(i);end
      if(state_q[i]==T_WAIT&&shared_q[i]&&!shared_dispatch&&!shared_active_q)
        begin shared_dispatch=1;shared_index=2'(i);end
      if(state_q[i]==T_DONE&&!done_valid)begin done_valid=1;done_index=2'(i);end
    end
    queue_input_valid=done_valid;queue_input='0;
    if(done_valid)begin
      queue_input.valid=1;queue_input.epoch=epoch_q[done_index];
      queue_input.warp_id=warp_q[done_index];queue_input.sequence_number=sequence_q[done_index];
      queue_input.pc=pc_q[done_index];queue_input.instruction=instruction_q[done_index];
      queue_input.active_mask=active_q[done_index];queue_input.write_mask=mask_q[done_index];
      queue_input.writes_gpr=!store_q[done_index];queue_input.gpr_dst=dst_q[done_index];
      queue_input.gpr_mask=store_q[done_index]?'0:mask_q[done_index];
      for(int lane=0;lane<LANES;lane++)
        queue_input.gpr_data[lane]=load_data_q[done_index][lane];
      queue_input.clear_gpr_pending=!store_q[done_index];
      queue_input.completion_class=COMPLETION_MEMORY;
      queue_input.status=COMPLETION_STATUS_OK;
    end
  end

  banked_vector_memory #(.MEMORY_BYTES(SCRATCHPAD_BYTES),
    .USE_IHP_MACRO(USE_IHP_DATA_SRAM)) general_u(
    .clk,.rst,.clear_i(clear_i||fatal_i),.request_valid_i(general_dispatch),
    .request_ready_o(general_req_ready),.request_store_i(store_q[general_index]),
    .request_mask_i(mask_q[general_index]),.request_address_i(address_q[general_index]),
    .request_store_data_i(store_data_q[general_index]),.response_valid_o(general_resp_valid),
    .response_ready_i(1'b1),.response_fault_o(general_resp_fault),
    .response_misaligned_o(general_misaligned),.response_out_of_range_o(general_range),
    .response_mask_o(general_resp_mask),.response_load_data_o(general_load),
    .pending_mask_o(general_pending),.busy_o(general_busy),
    .host_valid_i(host_valid_i&&!host_shared_i&&tracker_occupancy_o==0),
    .host_ready_o(general_host_ready),.host_write_i,.host_address_i,.host_write_data_i,
    .host_response_valid_o(general_host_response_valid),
    .host_response_fault_o(general_host_response_fault),
    .host_read_data_o(general_host_read_data));
  banked_vector_memory #(.MEMORY_BYTES(SHMEM_BYTES),
    .USE_IHP_MACRO(USE_IHP_DATA_SRAM)) shared_u(
    .clk,.rst,.clear_i(clear_i||fatal_i),.request_valid_i(shared_dispatch),
    .request_ready_o(shared_req_ready),.request_store_i(store_q[shared_index]),
    .request_mask_i(mask_q[shared_index]),.request_address_i(address_q[shared_index]),
    .request_store_data_i(store_data_q[shared_index]),.response_valid_o(shared_resp_valid),
    .response_ready_i(1'b1),.response_fault_o(shared_resp_fault),
    .response_misaligned_o(shared_misaligned),.response_out_of_range_o(shared_range),
    .response_mask_o(shared_resp_mask),.response_load_data_o(shared_load),
    .pending_mask_o(shared_pending),.busy_o(shared_busy),
    .host_valid_i(host_valid_i&&host_shared_i&&tracker_occupancy_o==0),
    .host_ready_o(shared_host_ready),.host_write_i,.host_address_i,.host_write_data_i,
    .host_response_valid_o(shared_host_response_valid),
    .host_response_fault_o(shared_host_response_fault),
    .host_read_data_o(shared_host_read_data));

  completion_queue queue_u(.clk,.rst,.flush_i(clear_i||fatal_i),
    .completion_valid_i(queue_input_valid),.completion_ready_o(queue_input_ready),
    .completion_i(queue_input),.completion_valid_o(completion_valid_o),
    .completion_ready_i(completion_ready_i),.completion_o(completion_o),
    .occupancy_o(completion_queue_occupancy));

  always_ff @(posedge clk)begin
    if(rst||clear_i||fatal_i)begin
      for(int i=0;i<MAX_MEMORY_OPS;i++)begin state_q[i]<=T_FREE;load_data_q[i]<='{default:'0};end
      general_active_q<=0;shared_active_q<=0;general_tracker_q<=0;shared_tracker_q<=0;
      fault_valid_o<=0;fault_code_o<=FAULT_NONE;fault_pc_o<=0;
    end else begin
      fault_valid_o<=0;
      if(request_valid_i&&request_ready_o)begin
        state_q[free_index]<=T_WAIT;shared_q[free_index]<=request_shared_i;
        store_q[free_index]<=request_store_i;epoch_q[free_index]<=request_epoch_i;
        warp_q[free_index]<=request_warp_i;sequence_q[free_index]<=request_sequence_i;
        pc_q[free_index]<=request_pc_i;instruction_q[free_index]<=request_instruction_i;
        active_q[free_index]<=request_active_mask_i;mask_q[free_index]<=request_mask_i;
        dst_q[free_index]<=request_gpr_dst_i;
        for(int lane=0;lane<LANES;lane++)begin
          address_q[free_index][lane]<=request_address_i[lane];
          store_data_q[free_index][lane]<=request_store_data_i[lane];
        end
      end
      if(general_dispatch&&general_req_ready)begin
        state_q[general_index]<=T_ENGINE;general_active_q<=1;general_tracker_q<=general_index;
      end
      if(shared_dispatch&&shared_req_ready)begin
        state_q[shared_index]<=T_ENGINE;shared_active_q<=1;shared_tracker_q<=shared_index;
      end
      if(general_resp_valid&&general_active_q)begin
        general_active_q<=0;
        if(general_resp_fault)begin state_q[general_tracker_q]<=T_FREE;fault_valid_o<=1;
          fault_code_o<=general_misaligned?FAULT_MEMORY_MISALIGNED:FAULT_MEMORY_OUT_OF_RANGE;
          fault_pc_o<=pc_q[general_tracker_q];end
        else begin state_q[general_tracker_q]<=T_DONE;
          load_data_q[general_tracker_q]<=general_load;end
      end
      if(shared_resp_valid&&shared_active_q)begin
        shared_active_q<=0;
        if(shared_resp_fault)begin state_q[shared_tracker_q]<=T_FREE;fault_valid_o<=1;
          fault_code_o<=shared_misaligned?FAULT_MEMORY_MISALIGNED:FAULT_MEMORY_OUT_OF_RANGE;
          fault_pc_o<=pc_q[shared_tracker_q];end
        else begin state_q[shared_tracker_q]<=T_DONE;
          load_data_q[shared_tracker_q]<=shared_load;end
      end
      if(queue_input_valid&&queue_input_ready)state_q[done_index]<=T_QUEUED;
      if(completion_valid_o&&completion_ready_i)
        for(int i=0;i<MAX_MEMORY_OPS;i++)
          if(state_q[i]==T_QUEUED&&epoch_q[i]==completion_o.epoch&&
             warp_q[i]==completion_o.warp_id&&sequence_q[i]==completion_o.sequence_number)
            state_q[i]<=T_FREE;
    end
  end
endmodule
