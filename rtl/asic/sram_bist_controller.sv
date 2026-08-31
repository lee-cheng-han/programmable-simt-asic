module sram_bist_controller #(
  parameter int unsigned GENERAL_WORDS=1024,
  parameter int unsigned SHARED_WORDS=512
) (
  input logic clk_i,reset_i,test_mode_i,start_i,
  output logic active_o,done_o,fail_o,
  output logic fail_shared_o,output logic[31:0]fail_address_o,
  output logic host_valid_o,host_shared_o,host_write_o,
  output logic[31:0]host_address_o,host_write_data_o,
  input logic host_ready_i,host_response_valid_i,host_response_fault_i,
  input logic[31:0]host_read_data_i
);
  typedef enum logic[2:0]{WRITE_ZERO,READ_ZERO,WRITE_ONE,READ_ONE,
    WRITE_CHECKER,READ_CHECKER}phase_t;
  phase_t phase_q;
  logic shared_q,waiting_q;
  logic[10:0]word_q;
  logic[31:0]expected;

  always_comb begin
    host_valid_o=active_o&&!waiting_q;
    host_shared_o=shared_q;
    host_write_o=phase_q==WRITE_ZERO||phase_q==WRITE_ONE||phase_q==WRITE_CHECKER;
    host_address_o={19'b0,word_q,2'b0};
    unique case(phase_q)
      WRITE_ONE,READ_ONE:expected=32'hffff_ffff;
      WRITE_CHECKER,READ_CHECKER:expected=word_q[0]?32'h5555_5555:32'haaaa_aaaa;
      default:expected=32'h0000_0000;
    endcase
    host_write_data_o=expected;
  end

  task automatic record_failure;
    if(!fail_o)begin
      fail_shared_o<=shared_q;
      fail_address_o<={19'b0,word_q,2'b0};
    end
    fail_o<=1'b1;
  endtask

  task automatic advance_operation;
    logic last_word;
    last_word=shared_q?(word_q==11'(SHARED_WORDS-1)):(word_q==11'(GENERAL_WORDS-1));
    if(last_word)begin
      word_q<=0;
      if(!shared_q)shared_q<=1'b1;
      else begin
        shared_q<=1'b0;
        if(phase_q==READ_CHECKER)begin active_o<=1'b0;done_o<=1'b1;end
        else phase_q<=phase_t'(phase_q+1'b1);
      end
    end else word_q<=word_q+1'b1;
  endtask

  always_ff @(posedge clk_i)begin
    if(reset_i||!test_mode_i)begin
      active_o<=1'b0;done_o<=1'b0;fail_o<=1'b0;fail_shared_o<=1'b0;
      fail_address_o<=0;phase_q<=WRITE_ZERO;shared_q<=1'b0;word_q<=0;waiting_q<=1'b0;
    end else begin
      if(start_i&&!active_o)begin
        active_o<=1'b1;done_o<=1'b0;fail_o<=1'b0;fail_shared_o<=1'b0;
        fail_address_o<=0;phase_q<=WRITE_ZERO;shared_q<=1'b0;word_q<=0;waiting_q<=1'b0;
      end
      if(active_o&&!waiting_q&&host_ready_i)waiting_q<=1'b1;
      if(active_o&&waiting_q&&host_response_valid_i)begin
        waiting_q<=1'b0;
        if(host_response_fault_i||(!host_write_o&&host_read_data_i!==expected))record_failure();
        advance_operation();
      end
    end
  end
`ifndef SYNTHESIS
  assert property(@(posedge clk_i)active_o|->test_mode_i);
  assert property(@(posedge clk_i)host_valid_o|->active_o&&!waiting_q);
  assert property(@(posedge clk_i)done_o|->!active_o);
`endif
endmodule
