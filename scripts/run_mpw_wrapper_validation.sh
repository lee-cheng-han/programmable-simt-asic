#!/usr/bin/env sh
set -eu

mkdir -p build/verilator/mpw_wrapper
python3 tools/gen_isa_sv.py isa/isa.json build/simt_isa_pkg.sv
verilator --binary --timing --assert --Wall -Wno-UNUSEDPARAM \
  --Mdir build/verilator/mpw_wrapper --top-module tb_mpw_wrapper \
  build/simt_isa_pkg.sv rtl/simt_gpu_pkg.sv \
  rtl/frontend/instruction_decoder.sv rtl/register_file/vector_register_file.sv \
  rtl/register_file/predicate_register_file.sv rtl/execute/integer_lane.sv \
  rtl/execute/vector_integer_alu.sv rtl/execute/completion_queue.sv \
  rtl/execute/alu_completion_stage.sv rtl/execute/vector_multiplier_pipeline.sv \
  rtl/execute/completion_arbiter.sv rtl/execute/architectural_writeback.sv \
  rtl/control/dependency_scoreboard.sv rtl/control/round_robin_arbiter.sv \
  rtl/control/fatal_fault_controller.sv rtl/memory/data_sram_bank_adapter.sv \
  rtl/memory/banked_vector_memory.sv rtl/memory/memory_subsystem.sv \
  rtl/frontend/instruction_sram_adapter.sv rtl/frontend/warp_instruction_frontend.sv \
  rtl/core/simt_core.sv rtl/asic/reset_synchronizer.sv \
  rtl/asic/asic_host_controller.sv rtl/asic/sram_bist_controller.sv \
  rtl/asic/simt_asic_top.sv rtl/asic/simt_mpw_wrapper.sv \
  tb/integration/tb_mpw_wrapper.sv
build/verilator/mpw_wrapper/Vtb_mpw_wrapper
