module vector_register_file #(
  parameter int unsigned LANES = 8,
  parameter int unsigned WARPS = 4,
  parameter int unsigned REGS  = 16,
  parameter int unsigned XLEN  = 32,
  parameter int unsigned WARP_W = $clog2(WARPS),
  parameter int unsigned REG_W  = $clog2(REGS),
  parameter int unsigned ADDR_W = $clog2(WARPS * REGS)
) (
  input  logic clk,
  input  logic rst,

  input  logic              read_valid_i,
  input  logic [WARP_W-1:0] read_warp_i,
  input  logic [REG_W-1:0]  read_ra_i,
  input  logic [REG_W-1:0]  read_rb_i,
  output logic [LANES-1:0][XLEN-1:0] read_a_o,
  output logic [LANES-1:0][XLEN-1:0] read_b_o,

  input  logic              write_valid_i,
  input  logic [WARP_W-1:0] write_warp_i,
  input  logic [REG_W-1:0]  write_reg_i,
  input  logic [LANES-1:0]  write_lane_mask_i,
  input  logic [LANES-1:0][XLEN-1:0] write_data_i
);
  localparam int unsigned DEPTH = WARPS * REGS;

  // Each lane owns a bank. The two arrays are physical replicas: replica A
  // supplies source A and replica B supplies source B. Accepted writes update
  // both arrays from the same registered interface.
  logic [XLEN-1:0] replica_a [LANES][DEPTH];
  logic [XLEN-1:0] replica_b [LANES][DEPTH];

  logic [ADDR_W-1:0] read_addr_a;
  logic [ADDR_W-1:0] read_addr_b;
  logic [ADDR_W-1:0] write_addr;

  always_comb begin
    read_addr_a = ADDR_W'(int'(read_warp_i) * REGS + int'(read_ra_i));
    read_addr_b = ADDR_W'(int'(read_warp_i) * REGS + int'(read_rb_i));
    write_addr  = ADDR_W'(int'(write_warp_i) * REGS + int'(write_reg_i));

    read_a_o = '0;
    read_b_o = '0;
    if (read_valid_i && !rst) begin
      for (int unsigned lane = 0; lane < LANES; lane++) begin
        read_a_o[lane] = replica_a[lane][read_addr_a];
        read_b_o[lane] = replica_b[lane][read_addr_b];

        // Forward only lanes written by a valid same-warp, same-register
        // writeback. Unwritten lanes retain the value held in their bank.
        if (write_valid_i && write_lane_mask_i[lane] &&
            write_warp_i == read_warp_i && write_reg_i == read_ra_i)
          read_a_o[lane] = write_data_i[lane];
        if (write_valid_i && write_lane_mask_i[lane] &&
            write_warp_i == read_warp_i && write_reg_i == read_rb_i)
          read_b_o[lane] = write_data_i[lane];
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst && write_valid_i) begin
      for (int unsigned lane = 0; lane < LANES; lane++) begin
        if (write_lane_mask_i[lane]) begin
          replica_a[lane][write_addr] <= write_data_i[lane];
          replica_b[lane][write_addr] <= write_data_i[lane];
        end
      end
    end
  end

`ifndef SYNTHESIS
  // A write accepted in the preceding cycle must be visible identically from
  // both replicas. Sampling occurs before any current-cycle nonblocking update,
  // so this remains valid for consecutive writes to the same address.
  for (genvar lane = 0; lane < LANES; lane++) begin : gen_replica_assertions
    property p_replicated_write;
      @(posedge clk) disable iff (rst)
        (write_valid_i && write_lane_mask_i[lane])
        |=> (replica_a[lane][$past(write_addr)] == $past(write_data_i[lane]) &&
             replica_b[lane][$past(write_addr)] == $past(write_data_i[lane]) &&
             replica_a[lane][$past(write_addr)] ==
             replica_b[lane][$past(write_addr)]);
    endproperty
    assert property (p_replicated_write)
      else $error("vector register-file replica mismatch on lane %0d", lane);
  end
`endif
endmodule
