module banked_vector_memory #(
  parameter int unsigned MEMORY_BYTES = simt_gpu_pkg::SCRATCHPAD_BYTES,
  parameter int unsigned BANKS = simt_gpu_pkg::LANES,
  parameter int unsigned ROWS = MEMORY_BYTES / (BANKS * 4),
  parameter int unsigned ROW_WIDTH = (ROWS <= 1) ? 1 : $clog2(ROWS)
) (
  input logic clk,
  input logic rst,
  input logic clear_i,

  input logic request_valid_i,
  output logic request_ready_o,
  input logic request_store_i,
  input simt_gpu_pkg::lane_mask_t request_mask_i,
  input simt_gpu_pkg::word_t [simt_gpu_pkg::LANES-1:0] request_address_i,
  input simt_gpu_pkg::word_t [simt_gpu_pkg::LANES-1:0] request_store_data_i,

  output logic response_valid_o,
  input logic response_ready_i,
  output logic response_fault_o,
  output logic response_misaligned_o,
  output logic response_out_of_range_o,
  output simt_gpu_pkg::lane_mask_t response_mask_o,
  output simt_gpu_pkg::word_t [simt_gpu_pkg::LANES-1:0] response_load_data_o,
  output simt_gpu_pkg::lane_mask_t pending_mask_o,
  output logic busy_o
);
  import simt_gpu_pkg::*;

  word_t storage_q [BANKS][ROWS];
  logic store_q;
  lane_mask_t participation_q,pending_q;
  word_t [LANES-1:0] address_q,store_data_q,load_data_q;
  logic response_valid_q,response_fault_q,misaligned_q,out_of_range_q;
  logic request_fault,request_misaligned,request_out_of_range;
  lane_mask_t served_mask;
  logic [BANKS-1:0] bank_used;

  always_comb begin
    request_misaligned=1'b0;request_out_of_range=1'b0;
    for(int unsigned lane=0;lane<LANES;lane++) begin
      if(request_mask_i[lane]) begin
        request_misaligned|=(request_address_i[lane][1:0]!=2'b00);
        request_out_of_range|=(request_address_i[lane]>=MEMORY_BYTES);
      end
    end
    request_fault=request_misaligned||request_out_of_range;
    busy_o=(pending_q!='0);
    request_ready_o=(pending_q=='0)&&!response_valid_q;
    response_valid_o=response_valid_q;
    response_fault_o=response_fault_q;
    response_misaligned_o=misaligned_q;
    response_out_of_range_o=out_of_range_q;
    response_mask_o=participation_q;
    response_load_data_o=load_data_q;
    pending_mask_o=pending_q;

    bank_used='0;served_mask='0;
    // Loads broadcast one physical read to identical addresses. Other same-bank
    // addresses replay. Stores always select the lowest pending lane per bank,
    // which makes same-address final state deterministic by ascending lane.
    for(int unsigned lane=0;lane<LANES;lane++) begin
      if(pending_q[lane]) begin
        if(!bank_used[address_q[lane][4:2]]) begin
          bank_used[address_q[lane][4:2]]=1'b1;served_mask[lane]=1'b1;
          if(!store_q)
            for(int unsigned other=lane+1;other<LANES;other++)
              if(pending_q[other]&&address_q[other]==address_q[lane])
                served_mask[other]=1'b1;
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    if(rst||clear_i) begin
      store_q<=1'b0;participation_q<='0;pending_q<='0;
      response_valid_q<=1'b0;response_fault_q<=1'b0;
      misaligned_q<=1'b0;out_of_range_q<=1'b0;
      for(int unsigned lane=0;lane<LANES;lane++) begin
        address_q[lane]<='0;store_data_q[lane]<='0;load_data_q[lane]<='0;
      end
    end else begin
      if(response_valid_q&&response_ready_i) response_valid_q<=1'b0;
      if(request_valid_i&&request_ready_o) begin
        store_q<=request_store_i;participation_q<=request_mask_i;
        response_fault_q<=request_fault;misaligned_q<=request_misaligned;
        out_of_range_q<=request_out_of_range;
        for(int unsigned lane=0;lane<LANES;lane++) begin
          address_q[lane]<=request_address_i[lane];
          store_data_q[lane]<=request_store_data_i[lane];
          load_data_q[lane]<='0;
        end
        if(request_fault||request_mask_i=='0) begin
          pending_q<='0;response_valid_q<=1'b1;
        end else pending_q<=request_mask_i;
      end else if(pending_q!='0) begin
        for(int unsigned lane=0;lane<LANES;lane++) begin
          if(served_mask[lane]) begin
            if(store_q)
              storage_q[address_q[lane][4:2]]
                       [address_q[lane][ROW_WIDTH+4:5]]<=store_data_q[lane];
            else
              load_data_q[lane]<=storage_q[address_q[lane][4:2]]
                                          [address_q[lane][ROW_WIDTH+4:5]];
          end
        end
        pending_q<=pending_q&~served_mask;
        if((pending_q&~served_mask)=='0) response_valid_q<=1'b1;
      end
    end
  end

`ifndef SYNTHESIS
  initial begin
    assert(BANKS==LANES);
    assert(MEMORY_BYTES==(BANKS*ROWS*4));
  end
  property p_response_control_stable_while_stalled;
    @(posedge clk) disable iff(rst||clear_i)
      response_valid_o&&!response_ready_i |=> response_valid_o&&
      $stable(response_fault_o)&&$stable(response_mask_o);
  endproperty
  assert property(p_response_control_stable_while_stalled);
  for(genvar lane=0;lane<LANES;lane++) begin : gen_response_stability
    property p_response_lane_stable_while_stalled;
      @(posedge clk) disable iff(rst||clear_i)
        response_valid_o&&!response_ready_i |=>
          $stable(response_load_data_o[lane]);
    endproperty
    assert property(p_response_lane_stable_while_stalled);
  end
  property p_fault_is_atomic;
    @(posedge clk) disable iff(rst||clear_i)
      request_valid_i&&request_ready_o&&request_fault |=> pending_mask_o=='0;
  endproperty
  assert property(p_fault_is_atomic);
`endif
endmodule
