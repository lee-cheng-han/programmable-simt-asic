module asic_host_controller #(
  parameter int unsigned IMEM_ADDR_W = 6
) (
  input logic clk_i, reset_i, test_mode_i,
  input logic wb_cyc_i, wb_stb_i, wb_we_i,
  input logic [7:0] wb_adr_i,
  input logic [31:0] wb_dat_i,
  input logic [3:0] wb_sel_i,
  output logic wb_ack_o, wb_err_o,
  output logic [31:0] wb_dat_o,
  output logic clear_o, launch_valid_o,
  input logic launch_ready_i,
  output logic [31:0] launch_pc_o,
  output logic [2:0] launch_warp_count_o,
  output logic prog_valid_o,
  output logic [IMEM_ADDR_W-1:0] prog_addr_o,
  output logic [31:0] prog_data_o,
  input logic running_i, done_i, fault_i,
  input logic [31:0] fault_pc_i,
  input simt_gpu_pkg::fault_code_t fault_code_i,
  input logic [63:0] cycle_count_i, issue_count_i, commit_count_i
);
  localparam logic [7:0] ADDR_CONTROL    = 8'h00;
  localparam logic [7:0] ADDR_STATUS     = 8'h04;
  localparam logic [7:0] ADDR_LAUNCH_PC  = 8'h08;
  localparam logic [7:0] ADDR_WARP_COUNT = 8'h0c;
  localparam logic [7:0] ADDR_IMEM_ADDR  = 8'h10;
  localparam logic [7:0] ADDR_IMEM_DATA  = 8'h14;
  localparam logic [7:0] ADDR_FAULT_CODE = 8'h18;
  localparam logic [7:0] ADDR_FAULT_PC   = 8'h1c;
  localparam logic [7:0] ADDR_CYCLE_LO   = 8'h20;
  localparam logic [7:0] ADDR_CYCLE_HI   = 8'h24;
  localparam logic [7:0] ADDR_ISSUE_LO   = 8'h28;
  localparam logic [7:0] ADDR_ISSUE_HI   = 8'h2c;
  localparam logic [7:0] ADDR_COMMIT_LO  = 8'h30;
  localparam logic [7:0] ADDR_COMMIT_HI  = 8'h34;

  logic request, address_valid;
  logic [31:0] merged_launch_pc, merged_prog_data;
  /* verilator lint_off UNUSEDSIGNAL */
  logic [31:0] warp_count_word, imem_addr_word;
  /* verilator lint_on UNUSEDSIGNAL */

  always_comb begin
    request = wb_cyc_i && wb_stb_i;
    address_valid = wb_adr_i[1:0] == 2'b00 && wb_adr_i <= ADDR_COMMIT_HI;
    wb_ack_o = request && !test_mode_i && address_valid;
    wb_err_o = request && (test_mode_i || !address_valid);
    wb_dat_o = '0;
    unique case (wb_adr_i)
      ADDR_STATUS: wb_dat_o = {29'b0, fault_i, done_i, running_i};
      ADDR_LAUNCH_PC: wb_dat_o = launch_pc_o;
      ADDR_WARP_COUNT: wb_dat_o = {29'b0, launch_warp_count_o};
      ADDR_IMEM_ADDR: wb_dat_o = {{(32-IMEM_ADDR_W){1'b0}}, prog_addr_o};
      ADDR_IMEM_DATA: wb_dat_o = prog_data_o;
      ADDR_FAULT_CODE: wb_dat_o = 32'(fault_code_i);
      ADDR_FAULT_PC: wb_dat_o = fault_pc_i;
      ADDR_CYCLE_LO: wb_dat_o = cycle_count_i[31:0];
      ADDR_CYCLE_HI: wb_dat_o = cycle_count_i[63:32];
      ADDR_ISSUE_LO: wb_dat_o = issue_count_i[31:0];
      ADDR_ISSUE_HI: wb_dat_o = issue_count_i[63:32];
      ADDR_COMMIT_LO: wb_dat_o = commit_count_i[31:0];
      ADDR_COMMIT_HI: wb_dat_o = commit_count_i[63:32];
      default: wb_dat_o = '0;
    endcase
    merged_launch_pc = launch_pc_o;
    merged_prog_data = prog_data_o;
    warp_count_word = {29'b0, launch_warp_count_o};
    imem_addr_word = {{(32-IMEM_ADDR_W){1'b0}}, prog_addr_o};
    for (int byte_index = 0; byte_index < 4; byte_index++) begin
      if (wb_sel_i[byte_index]) begin
        merged_launch_pc[byte_index*8+:8] = wb_dat_i[byte_index*8+:8];
        merged_prog_data[byte_index*8+:8] = wb_dat_i[byte_index*8+:8];
        warp_count_word[byte_index*8+:8] = wb_dat_i[byte_index*8+:8];
        imem_addr_word[byte_index*8+:8] = wb_dat_i[byte_index*8+:8];
      end
    end
  end

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      clear_o <= 1'b0;
      launch_valid_o <= 1'b0;
      launch_pc_o <= '0;
      launch_warp_count_o <= 3'd1;
      prog_valid_o <= 1'b0;
      prog_addr_o <= '0;
      prog_data_o <= '0;
    end else begin
      clear_o <= 1'b0;
      prog_valid_o <= 1'b0;
      if (launch_valid_o && launch_ready_i)
        launch_valid_o <= 1'b0;
      if (request && !test_mode_i && wb_we_i && address_valid) begin
        unique case (wb_adr_i)
          ADDR_CONTROL: begin
            if (wb_sel_i[0] && wb_dat_i[1]) clear_o <= 1'b1;
            if (wb_sel_i[0] && wb_dat_i[0]) launch_valid_o <= 1'b1;
          end
          ADDR_LAUNCH_PC: launch_pc_o <= merged_launch_pc;
          ADDR_WARP_COUNT: launch_warp_count_o <= warp_count_word[2:0];
          ADDR_IMEM_ADDR: prog_addr_o <= imem_addr_word[IMEM_ADDR_W-1:0];
          ADDR_IMEM_DATA: begin
            prog_data_o <= merged_prog_data;
            prog_valid_o <= 1'b1;
          end
          default: begin end
        endcase
      end
    end
  end

`ifndef SYNTHESIS
  property p_test_mode_owns_interface;
    @(posedge clk_i) disable iff (reset_i) test_mode_i |->
      (!clear_o && !launch_valid_o && !prog_valid_o);
  endproperty
  assert property (p_test_mode_owns_interface);
`endif
endmodule
