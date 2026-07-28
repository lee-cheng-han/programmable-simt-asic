#!/usr/bin/env sh
set -eu
command -v verilator >/dev/null 2>&1 || {
  echo 'verilator not found; install Verilator 5 or newer' >&2
  exit 2
}
mkdir -p build/verilator/decoder
python3 tools/gen_isa_sv.py isa/isa.json build/simt_isa_pkg.sv
verilator --binary --timing --assert --Wall \
  --Mdir build/verilator/decoder \
  --top-module tb_instruction_decoder \
  build/simt_isa_pkg.sv \
  rtl/frontend/instruction_decoder.sv \
  tb/unit/tb_instruction_decoder.sv
build/verilator/decoder/Vtb_instruction_decoder

mkdir -p build/verilator/vector_register_file
verilator --binary --timing --assert --Wall \
  --Mdir build/verilator/vector_register_file \
  --top-module tb_vector_register_file \
  rtl/register_file/vector_register_file.sv \
  tb/unit/tb_vector_register_file.sv
build/verilator/vector_register_file/Vtb_vector_register_file

mkdir -p build/verilator/predicate_register_file
verilator --binary --timing --assert --Wall \
  --Mdir build/verilator/predicate_register_file \
  --top-module tb_predicate_register_file \
  rtl/register_file/predicate_register_file.sv \
  tb/unit/tb_predicate_register_file.sv
build/verilator/predicate_register_file/Vtb_predicate_register_file

mkdir -p build/verilator/vector_integer_alu
verilator --binary --timing --assert --Wall \
  --Mdir build/verilator/vector_integer_alu \
  --top-module tb_vector_integer_alu \
  build/simt_isa_pkg.sv \
  rtl/execute/integer_lane.sv \
  rtl/execute/vector_integer_alu.sv \
  tb/unit/tb_vector_integer_alu.sv
build/verilator/vector_integer_alu/Vtb_vector_integer_alu

mkdir -p build/verilator/instruction_fetch
verilator --binary --timing --assert --Wall \
  --Mdir build/verilator/instruction_fetch \
  --top-module tb_instruction_fetch \
  rtl/frontend/instruction_memory.sv \
  rtl/frontend/instruction_fetch.sv \
  tb/unit/tb_instruction_fetch.sv
build/verilator/instruction_fetch/Vtb_instruction_fetch

mkdir -p build/verilator/writeback_unit
verilator --binary --timing --assert --Wall \
  --Mdir build/verilator/writeback_unit \
  --top-module tb_writeback_unit \
  rtl/execute/writeback_unit.sv \
  tb/unit/tb_writeback_unit.sv
build/verilator/writeback_unit/Vtb_writeback_unit

mkdir -p build/verilator/completion_queue
verilator --binary --timing --assert --Wall \
  --Mdir build/verilator/completion_queue \
  --top-module tb_completion_queue \
  rtl/simt_gpu_pkg.sv \
  rtl/execute/completion_queue.sv \
  tb/unit/tb_completion_queue.sv
build/verilator/completion_queue/Vtb_completion_queue

mkdir -p build/verilator/alu_completion_writeback
verilator --binary --timing --assert --Wall \
  --Mdir build/verilator/alu_completion_writeback \
  --top-module tb_alu_completion_writeback \
  rtl/simt_gpu_pkg.sv \
  rtl/execute/completion_queue.sv \
  rtl/execute/alu_completion_stage.sv \
  rtl/execute/architectural_writeback.sv \
  tb/unit/tb_alu_completion_writeback.sv
build/verilator/alu_completion_writeback/Vtb_alu_completion_writeback

mkdir -p build/verilator/dependency_scoreboard
verilator --binary --timing --assert --Wall \
  --Mdir build/verilator/dependency_scoreboard \
  --top-module tb_dependency_scoreboard \
  rtl/simt_gpu_pkg.sv \
  rtl/control/dependency_scoreboard.sv \
  tb/unit/tb_dependency_scoreboard.sv
build/verilator/dependency_scoreboard/Vtb_dependency_scoreboard

mkdir -p build/verilator/round_robin_arbiter
verilator --binary --timing --assert --Wall \
  --Mdir build/verilator/round_robin_arbiter \
  --top-module tb_round_robin_arbiter \
  rtl/control/round_robin_arbiter.sv \
  tb/unit/tb_round_robin_arbiter.sv
build/verilator/round_robin_arbiter/Vtb_round_robin_arbiter

mkdir -p build/verilator/vector_multiplier_pipeline
verilator --binary --timing --assert --Wall -Wno-UNUSEDPARAM \
  --Mdir build/verilator/vector_multiplier_pipeline \
  --top-module tb_vector_multiplier_pipeline \
  rtl/simt_gpu_pkg.sv rtl/execute/completion_queue.sv \
  rtl/execute/vector_multiplier_pipeline.sv \
  tb/unit/tb_vector_multiplier_pipeline.sv
build/verilator/vector_multiplier_pipeline/Vtb_vector_multiplier_pipeline

mkdir -p build/verilator/completion_arbiter
verilator --binary --timing --assert --Wall -Wno-UNUSEDPARAM \
  --Mdir build/verilator/completion_arbiter \
  --top-module tb_completion_arbiter \
  rtl/simt_gpu_pkg.sv rtl/control/round_robin_arbiter.sv \
  rtl/execute/completion_arbiter.sv \
  tb/unit/tb_completion_arbiter.sv
build/verilator/completion_arbiter/Vtb_completion_arbiter

mkdir -p build/verilator/single_warp_core
verilator --binary --timing --assert --Wall \
  --Mdir build/verilator/single_warp_core --top-module tb_single_warp_core \
  build/simt_isa_pkg.sv rtl/simt_gpu_pkg.sv \
  rtl/frontend/instruction_memory.sv rtl/frontend/instruction_fetch.sv \
  rtl/frontend/instruction_decoder.sv \
  rtl/register_file/vector_register_file.sv \
  rtl/register_file/predicate_register_file.sv \
  rtl/execute/integer_lane.sv rtl/execute/vector_integer_alu.sv \
  rtl/execute/completion_queue.sv rtl/execute/alu_completion_stage.sv \
  rtl/execute/vector_multiplier_pipeline.sv rtl/execute/completion_arbiter.sv \
  rtl/execute/architectural_writeback.sv \
  rtl/control/dependency_scoreboard.sv rtl/control/round_robin_arbiter.sv \
  rtl/control/fatal_fault_controller.sv \
  rtl/core/single_warp_core.sv \
  tb/integration/tb_single_warp_core.sv
build/verilator/single_warp_core/Vtb_single_warp_core
python3 tools/assembler/assembler.py tb/programs/single_warp_integer.s \
  -o build/single_warp_integer.bin
build/simt-emulator build/single_warp_integer.bin \
  --dump build/single_warp_integer.state --trace build/emulator_single_warp.trace
python3 scripts/compare_arch_traces.py \
  build/emulator_single_warp.trace build/rtl_single_warp.trace

mkdir -p build/verilator/single_warp_lifecycle
verilator --binary --timing --assert --Wall \
  --Mdir build/verilator/single_warp_lifecycle --top-module tb_single_warp_lifecycle \
  build/simt_isa_pkg.sv rtl/simt_gpu_pkg.sv \
  rtl/frontend/instruction_memory.sv rtl/frontend/instruction_fetch.sv \
  rtl/frontend/instruction_decoder.sv rtl/register_file/vector_register_file.sv \
  rtl/register_file/predicate_register_file.sv rtl/execute/integer_lane.sv \
  rtl/execute/vector_integer_alu.sv rtl/execute/completion_queue.sv \
  rtl/execute/alu_completion_stage.sv rtl/execute/vector_multiplier_pipeline.sv \
  rtl/execute/completion_arbiter.sv rtl/execute/architectural_writeback.sv \
  rtl/control/dependency_scoreboard.sv rtl/control/round_robin_arbiter.sv \
  rtl/control/fatal_fault_controller.sv \
  rtl/core/single_warp_core.sv tb/integration/tb_single_warp_lifecycle.sv
build/verilator/single_warp_lifecycle/Vtb_single_warp_lifecycle

mkdir -p build/verilator/four_warp_core
verilator --binary --timing --assert --Wall -Wno-UNUSEDPARAM \
  --Mdir build/verilator/four_warp_core --top-module tb_four_warp_core \
  build/simt_isa_pkg.sv rtl/simt_gpu_pkg.sv \
  rtl/frontend/instruction_decoder.sv rtl/register_file/vector_register_file.sv \
  rtl/register_file/predicate_register_file.sv rtl/execute/integer_lane.sv \
  rtl/execute/vector_integer_alu.sv rtl/execute/completion_queue.sv \
  rtl/execute/alu_completion_stage.sv rtl/execute/vector_multiplier_pipeline.sv \
  rtl/control/round_robin_arbiter.sv rtl/execute/completion_arbiter.sv \
  rtl/execute/architectural_writeback.sv \
  rtl/control/dependency_scoreboard.sv rtl/control/fatal_fault_controller.sv \
  rtl/core/four_warp_core.sv tb/integration/tb_four_warp_core.sv
build/verilator/four_warp_core/Vtb_four_warp_core
