#!/usr/bin/env sh
set -eu

command -v yosys >/dev/null 2>&1 || {
  echo 'yosys not found; install Yosys with the slang plugin' >&2
  exit 2
}
if ! yosys -m slang -p 'help read_slang' >/dev/null 2>&1; then
  echo 'the Yosys slang plugin is required for this SystemVerilog source' >&2
  exit 2
fi

mkdir -p build/synthesis
python3 tools/gen_isa_sv.py isa/isa.json build/simt_isa_pkg.sv

SOURCES='build/simt_isa_pkg.sv rtl/simt_gpu_pkg.sv rtl/frontend/instruction_decoder.sv rtl/register_file/vector_register_file.sv rtl/register_file/predicate_register_file.sv rtl/execute/integer_lane.sv rtl/execute/vector_integer_alu.sv rtl/execute/completion_queue.sv rtl/execute/alu_completion_stage.sv rtl/execute/vector_multiplier_pipeline.sv rtl/control/round_robin_arbiter.sv rtl/execute/completion_arbiter.sv rtl/execute/architectural_writeback.sv rtl/control/dependency_scoreboard.sv rtl/control/fatal_fault_controller.sv rtl/frontend/instruction_sram_adapter.sv rtl/frontend/warp_instruction_frontend.sv rtl/core/simt_core.sv'

if [ "${SYNTH_ELAB_ONLY:-0}" = 1 ]; then
  PASSES='hierarchy -check -top simt_core; check; stat'
  REPORT=build/synthesis/elaboration.log
else
  # This deliberately preserves behavioral arrays. It is a feasibility baseline,
  # not a PPA result; macro-backed memories are qualified and mapped separately.
  PASSES='synth -top simt_core; check; stat'
  REPORT=build/synthesis/generic.log
fi

# Word splitting is intentional: SOURCES is a whitespace-separated source list.
# shellcheck disable=SC2086
yosys -m slang -l "$REPORT" -p \
  "read_slang --ignore-assertions --top simt_core $SOURCES; $PASSES"

echo "synthesis report: $REPORT"
