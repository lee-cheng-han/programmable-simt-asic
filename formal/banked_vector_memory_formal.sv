module banked_vector_memory_formal;
  import simt_gpu_pkg::*;
  (* gclk *) logic clk;
  logic rst=1'b1;
  (* anyseq *) logic clear_i;
  (* anyseq *) logic request_valid_i,request_store_i,response_ready_i;
  (* anyseq *) lane_mask_t request_mask_i;
  (* anyseq *) word_t [LANES-1:0] request_address_i,request_store_data_i;
  logic request_ready_o,response_valid_o,response_fault_o;
  logic response_misaligned_o,response_out_of_range_o,busy_o;
  lane_mask_t response_mask_o,pending_mask_o;
  word_t [LANES-1:0] response_load_data_o;
  logic past_valid=1'b0;
  logic accepted_fault;
  logic previous_rst=1'b1,previous_clear=1'b1;
  logic previous_accepted_fault=1'b0;
  logic previous_stalled_response=1'b0,previous_response_fault=1'b0;
  lane_mask_t previous_response_mask='0;
  word_t [LANES-1:0] previous_response_load_data='0;

  banked_vector_memory #(.MEMORY_BYTES(64)) dut(.*);

  always_comb begin
    accepted_fault=1'b0;
    for(int unsigned lane=0;lane<LANES;lane++)
      if(request_mask_i[lane])
        accepted_fault|=request_address_i[lane][1:0]!=0||
                        request_address_i[lane]>=64;
  end

  always_ff @(posedge clk) begin
    past_valid<=1'b1;
    rst<=1'b0;
    previous_rst<=rst;
    previous_clear<=clear_i;
    previous_accepted_fault<=request_valid_i&&request_ready_o&&accepted_fault;
    previous_stalled_response<=response_valid_o&&!response_ready_i;
    previous_response_fault<=response_fault_o;
    previous_response_mask<=response_mask_o;
    previous_response_load_data<=response_load_data_o;
    if(past_valid&&!rst&&!clear_i)begin
      assert(request_ready_o==(!busy_o&&!response_valid_o));
      assert((pending_mask_o!='0)==busy_o);
      assert((pending_mask_o&~response_mask_o)=='0);
      if(response_valid_o&&response_fault_o)begin
        assert(!busy_o);
        assert(response_misaligned_o||response_out_of_range_o);
      end
    end
    if(past_valid&&!rst&&!clear_i&&!previous_rst&&!previous_clear&&
       previous_accepted_fault)begin
      assert(response_valid_o&&response_fault_o&&!busy_o);
    end
    if(past_valid&&!rst&&!clear_i&&!previous_rst&&!previous_clear&&
       previous_stalled_response)begin
      assert(response_valid_o);
      assert(response_fault_o==previous_response_fault);
      assert(response_mask_o==previous_response_mask);
      assert(response_load_data_o==previous_response_load_data);
    end
  end
endmodule
