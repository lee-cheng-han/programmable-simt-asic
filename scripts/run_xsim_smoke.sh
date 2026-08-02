#!/usr/bin/env sh
set -eu
command -v xvlog >/dev/null 2>&1 || { echo 'xvlog not found; install/source Vivado 2025.2' >&2; exit 2; }
mkdir -p build/xsim
python3 tools/gen_isa_sv.py isa/isa.json build/simt_isa_pkg.sv
xvlog -sv build/simt_isa_pkg.sv rtl/simt_gpu_pkg.sv \
  rtl/frontend/instruction_decoder.sv \
  rtl/frontend/instruction_memory.sv rtl/frontend/instruction_fetch.sv \
  rtl/frontend/warp_instruction_frontend.sv \
  rtl/register_file/vector_register_file.sv \
  rtl/register_file/predicate_register_file.sv \
  rtl/execute/integer_lane.sv rtl/execute/vector_integer_alu.sv \
  rtl/execute/writeback_unit.sv \
  rtl/execute/completion_queue.sv \
  rtl/execute/alu_completion_stage.sv \
  rtl/execute/architectural_writeback.sv \
  rtl/control/dependency_scoreboard.sv \
  rtl/control/round_robin_arbiter.sv \
  rtl/control/fatal_fault_controller.sv \
  rtl/execute/vector_multiplier_pipeline.sv \
  rtl/execute/completion_arbiter.sv \
  rtl/core/simt_core.sv \
  tb/unit/tb_package_smoke.sv tb/unit/tb_instruction_decoder.sv \
  tb/unit/tb_vector_register_file.sv tb/unit/tb_predicate_register_file.sv \
  tb/unit/tb_vector_integer_alu.sv tb/unit/tb_instruction_fetch.sv \
  tb/unit/tb_warp_instruction_frontend.sv \
  tb/unit/tb_writeback_unit.sv tb/unit/tb_completion_queue.sv \
  tb/unit/tb_alu_completion_writeback.sv \
  tb/unit/tb_dependency_scoreboard.sv \
  tb/unit/tb_round_robin_arbiter.sv \
  tb/unit/tb_vector_multiplier_pipeline.sv \
  tb/unit/tb_completion_arbiter.sv \
  tb/integration/tb_single_warp_core.sv \
  tb/integration/tb_single_warp_lifecycle.sv \
  tb/integration/tb_four_warp_core.sv \
  tb/integration/tb_four_warp_divergence.sv
xelab tb_package_smoke -s tb_package_smoke_sim
xelab tb_instruction_decoder -s tb_instruction_decoder_sim
xelab tb_vector_register_file -s tb_vector_register_file_sim
xelab tb_predicate_register_file -s tb_predicate_register_file_sim
xelab tb_vector_integer_alu -s tb_vector_integer_alu_sim
xelab tb_instruction_fetch -s tb_instruction_fetch_sim
xelab tb_warp_instruction_frontend -s tb_warp_instruction_frontend_sim
xelab tb_writeback_unit -s tb_writeback_unit_sim
xelab tb_completion_queue -s tb_completion_queue_sim
xelab tb_alu_completion_writeback -s tb_alu_completion_writeback_sim
xelab tb_dependency_scoreboard -s tb_dependency_scoreboard_sim
xelab tb_round_robin_arbiter -s tb_round_robin_arbiter_sim
xelab tb_vector_multiplier_pipeline -s tb_vector_multiplier_pipeline_sim
xelab tb_completion_arbiter -s tb_completion_arbiter_sim
xelab tb_single_warp_core -s tb_single_warp_core_sim
xelab tb_single_warp_lifecycle -s tb_single_warp_lifecycle_sim
xelab tb_four_warp_core -s tb_four_warp_core_sim
xelab tb_four_warp_divergence -s tb_four_warp_divergence_sim
