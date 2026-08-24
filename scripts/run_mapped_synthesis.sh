#!/usr/bin/env sh
set -eu

command -v yosys >/dev/null 2>&1 || { echo 'yosys not found' >&2; exit 2; }
if ! yosys -m slang -p 'help read_slang' >/dev/null 2>&1; then
  echo 'the Yosys slang plugin is required' >&2; exit 2
fi
export ORFS_ROOT=${ORFS_ROOT:-/home/leech/OpenROAD-flow-scripts}
platform="$ORFS_ROOT/flow/platforms/ihp-sg13g2"
liberty="$platform/lib/sg13g2_stdcell_typ_1p20V_25C.lib"
mkdir -p build/synthesis
python3 tools/gen_isa_sv.py isa/isa.json build/simt_isa_pkg.sv
sources='build/simt_isa_pkg.sv rtl/simt_gpu_pkg.sv rtl/frontend/instruction_decoder.sv rtl/register_file/vector_register_file.sv rtl/register_file/predicate_register_file.sv rtl/execute/integer_lane.sv rtl/execute/vector_integer_alu.sv rtl/execute/completion_queue.sv rtl/execute/alu_completion_stage.sv rtl/execute/vector_multiplier_pipeline.sv rtl/control/round_robin_arbiter.sv rtl/execute/completion_arbiter.sv rtl/execute/architectural_writeback.sv rtl/control/dependency_scoreboard.sv rtl/control/fatal_fault_controller.sv rtl/memory/data_sram_bank_adapter.sv rtl/memory/banked_vector_memory.sv rtl/memory/memory_subsystem.sv physical/ihp_sram_blackbox.sv rtl/frontend/instruction_sram_adapter.sv rtl/frontend/warp_instruction_frontend.sv rtl/core/simt_core.sv'
# Source splitting is intentional: the list is repository-controlled.
# shellcheck disable=SC2086
yosys -m slang -l build/synthesis/ihp_mapped.log -p \
  "read_slang --ignore-assertions --top simt_core -G USE_IHP_IMEM=1 -G USE_IHP_DATA_SRAM=1 $sources; synth -top simt_core; dfflibmap -liberty $liberty; abc -liberty $liberty; clean; stat -liberty $liberty; write_verilog -noattr build/synthesis/simt_core_ihp_mapped.v"
macro_count=$(rg -c '^[[:space:]]+RM_IHPSG13_1P_64x64_c2_bm_bist ' build/synthesis/simt_core_ihp_mapped.v)
test "$macro_count" -eq 17||{ echo "expected 17 SRAM macros, found $macro_count" >&2;exit 1;}
echo "PASS mapped SRAM macro count=$macro_count"
echo 'mapped synthesis report: build/synthesis/ihp_mapped.log'
