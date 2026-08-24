module banked_vector_memory #(
  parameter int unsigned MEMORY_BYTES = simt_gpu_pkg::SCRATCHPAD_BYTES,
  parameter int unsigned BANKS = simt_gpu_pkg::LANES,
  parameter int unsigned ROWS = MEMORY_BYTES / (BANKS * 4),
  parameter int unsigned ROW_WIDTH = (ROWS <= 1) ? 1 : $clog2(ROWS),
  parameter bit USE_IHP_MACRO = 1'b0
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

  localparam int unsigned BANK_WORD_ADDR_W=(ROWS<=1)?1:$clog2(ROWS);
  logic store_q;
  lane_mask_t participation_q,pending_q;
  word_t [LANES-1:0] address_q,store_data_q,load_data_q;
  logic response_valid_q,response_fault_q,misaligned_q,out_of_range_q;
  logic request_fault,request_misaligned,request_out_of_range;
  lane_mask_t completed_mask;
  lane_mask_t [BANKS-1:0] bank_issue_mask,bank_response_lane_q;
  logic [BANKS-1:0] bank_used;
  logic [BANKS-1:0] bank_request_valid,bank_request_ready,bank_response_valid;
  logic [BANKS-1:0][BANK_WORD_ADDR_W-1:0] bank_request_addr;
  logic [BANKS-1:0][31:0] bank_write_data,bank_read_data;
  logic [BANKS-1:0][$clog2(LANES)-1:0] bank_selected_lane;

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

    bank_used='0;bank_issue_mask='0;completed_mask='0;
    bank_request_valid='0;bank_request_addr='0;bank_write_data='0;
    bank_selected_lane='0;
    if(store_q)
      for(int unsigned bank=0;bank<BANKS;bank++)completed_mask|=bank_issue_mask[bank];
    else
      for(int unsigned bank=0;bank<BANKS;bank++)
        if(bank_response_valid[bank])completed_mask|=bank_response_lane_q[bank];
    // Loads broadcast one physical read to identical addresses. Other same-bank
    // addresses replay. Stores always select the lowest pending lane per bank,
    // which makes same-address final state deterministic by ascending lane.
    for(int unsigned lane=0;lane<LANES;lane++) begin
      if(pending_q[lane]) begin
        if(!bank_used[address_q[lane][4:2]]&&
           bank_request_ready[address_q[lane][4:2]]&&
           !bank_response_valid[address_q[lane][4:2]]) begin
          bank_used[address_q[lane][4:2]]=1'b1;
          bank_issue_mask[address_q[lane][4:2]][lane]=1'b1;
          bank_selected_lane[address_q[lane][4:2]]=$clog2(LANES)'(lane);
          if(!store_q)
            for(int unsigned other=lane+1;other<LANES;other++)
              if(pending_q[other]&&address_q[other]==address_q[lane])
                bank_issue_mask[address_q[lane][4:2]][other]=1'b1;
        end
      end
    end
    for(int unsigned bank=0;bank<BANKS;bank++)begin
      bank_request_valid[bank]=bank_issue_mask[bank]!='0;
      bank_request_addr[bank]=address_q[bank_selected_lane[bank]][ROW_WIDTH+4:5];
      bank_write_data[bank]=store_data_q[bank_selected_lane[bank]];
      if(store_q)completed_mask|=bank_issue_mask[bank];
    end
  end

  for(genvar bank=0;bank<BANKS;bank++)begin:gen_data_banks
    data_sram_bank_adapter #(.WORDS(ROWS),.WORD_ADDR_W(BANK_WORD_ADDR_W),
      .LOW_HALF_ONLY(ROWS==64),.USE_IHP_MACRO(USE_IHP_MACRO)) bank_u(
      .clk,.rst,.clear_i,.request_valid_i(bank_request_valid[bank]),
      .request_ready_o(bank_request_ready[bank]),.request_write_i(store_q),
      .request_addr_i(bank_request_addr[bank]),.request_write_data_i(bank_write_data[bank]),
      .request_byte_enable_i(4'hf),.response_valid_o(bank_response_valid[bank]),
      .response_ready_i(1'b1),.response_read_data_o(bank_read_data[bank]),
      .bist_enable_i(1'b0),.bist_clk_i(1'b0),.bist_mem_enable_i(1'b0),
      .bist_write_enable_i(1'b0),.bist_read_enable_i(1'b0),.bist_addr_i('0),
      .bist_write_data_i('0),.bist_bit_mask_i('0));
  end

  always_ff @(posedge clk) begin
    if(rst||clear_i) begin
      store_q<=1'b0;participation_q<='0;pending_q<='0;
      response_valid_q<=1'b0;response_fault_q<=1'b0;
      misaligned_q<=1'b0;out_of_range_q<=1'b0;
      for(int unsigned lane=0;lane<LANES;lane++) begin
        address_q[lane]<='0;store_data_q[lane]<='0;load_data_q[lane]<='0;
      end
      bank_response_lane_q<='0;
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
        for(int unsigned bank=0;bank<BANKS;bank++)begin
          if(bank_request_valid[bank]&&!store_q)
            bank_response_lane_q[bank]<=bank_issue_mask[bank];
          if(bank_response_valid[bank]&&!store_q)
            for(int unsigned lane=0;lane<LANES;lane++)
              if(bank_response_lane_q[bank][lane])load_data_q[lane]<=bank_read_data[bank];
        end
        pending_q<=pending_q&~completed_mask;
        if((pending_q&~completed_mask)=='0) response_valid_q<=1'b1;
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
