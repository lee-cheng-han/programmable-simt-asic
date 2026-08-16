package simt_gpu_pkg;
  parameter int unsigned LANES = 8;
  parameter int unsigned WARPS = 4;
  parameter int unsigned REGS_PER_THREAD = 16;
  parameter int unsigned PREDS_PER_THREAD = 4;
  parameter int unsigned XLEN = 32;
  parameter int unsigned SIMT_STACK_DEPTH = 8;
  parameter int unsigned SCRATCHPAD_BYTES = 4096;
  parameter int unsigned SHMEM_BYTES = 2048;
  parameter int unsigned MAX_MEMORY_OPS = 4;
  parameter int unsigned COMPLETION_QUEUE_DEPTH = 2;
  parameter int unsigned KERNEL_EPOCH_WIDTH = 6;
  parameter int unsigned INSTRUCTION_SEQUENCE_WIDTH = 16;
  parameter int unsigned MULTIPLIER_LATENCY = 3;

  localparam int unsigned WARP_ID_WIDTH = $clog2(WARPS);
  localparam int unsigned REG_INDEX_WIDTH = $clog2(REGS_PER_THREAD);
  localparam int unsigned PRED_INDEX_WIDTH = $clog2(PREDS_PER_THREAD);

  typedef logic [LANES-1:0] lane_mask_t;
  typedef logic [XLEN-1:0] word_t;

  typedef enum logic [1:0] {
    COMPLETION_ALU        = 2'b00,
    COMPLETION_MULTIPLIER = 2'b01,
    COMPLETION_MEMORY     = 2'b10,
    COMPLETION_RESERVED   = 2'b11
  } completion_class_t;

  typedef enum logic [1:0] {
    COMPLETION_STATUS_OK        = 2'b00,
    COMPLETION_STATUS_RESERVED1 = 2'b01,
    COMPLETION_STATUS_RESERVED2 = 2'b10,
    COMPLETION_STATUS_RESERVED3 = 2'b11
  } completion_status_t;

  typedef enum logic [3:0] {
    FAULT_NONE                  = 4'd0,
    FAULT_IMEM_WRITE_WHILE_BUSY = 4'd1,
    FAULT_FETCH_PC_RANGE        = 4'd2,
    FAULT_ILLEGAL_INSTRUCTION   = 4'd3,
    FAULT_UNSUPPORTED_STAGE     = 4'd4,
    FAULT_SIMT_STACK_OVERFLOW   = 4'd5,
    FAULT_SIMT_STACK_UNDERFLOW  = 4'd6,
    FAULT_SIMT_CONTROL          = 4'd7,
    FAULT_MEMORY_MISALIGNED     = 4'd8,
    FAULT_MEMORY_OUT_OF_RANGE   = 4'd9,
    FAULT_BARRIER_VIOLATION     = 4'd10,
    FAULT_BARRIER_DEADLOCK      = 4'd11
  } fault_code_t;

  typedef struct packed {
    logic                                      valid;
    logic [KERNEL_EPOCH_WIDTH-1:0]             epoch;
    logic [WARP_ID_WIDTH-1:0]                  warp_id;
    logic [INSTRUCTION_SEQUENCE_WIDTH-1:0]     sequence_number;
    logic [31:0]                               pc;
    logic [31:0]                               instruction;
    lane_mask_t                                active_mask;
    lane_mask_t                                write_mask;
    logic                                      writes_gpr;
    logic [REG_INDEX_WIDTH-1:0]                gpr_dst;
    lane_mask_t                                gpr_mask;
    word_t [LANES-1:0]                         gpr_data;
    logic                                      writes_pred;
    logic [PRED_INDEX_WIDTH-1:0]               pred_dst;
    lane_mask_t                                pred_mask;
    lane_mask_t                                pred_data;
    logic                                      clear_gpr_pending;
    logic                                      clear_pred_pending;
    completion_class_t                         completion_class;
    completion_status_t                        status;
  } completion_record_t;
endpackage
