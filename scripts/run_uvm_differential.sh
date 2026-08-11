#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
uvm_test="${UVM_TEST:-four_warp_differential_test}"
seed="${SEED:-1}"
run_dir="$repo_root/build/uvm/runs/${uvm_test}_${seed}"
sim_dir="${TMPDIR:-/tmp}/simt_uvm_xsim/${uvm_test}_${seed}"

if [[ -n "${XILINX_VIVADO:-}" ]]; then
  vivado_root="$XILINX_VIVADO"
elif command -v xvlog >/dev/null 2>&1; then
  vivado_root="$(cd "$(dirname "$(command -v xvlog)")/.." && pwd)"
else
  echo 'xvlog not found; source the Vivado environment first' >&2
  exit 2
fi
xvlog_bin="${XVLOG:-$vivado_root/bin/xvlog}"
xelab_bin="${XELAB:-$vivado_root/bin/xelab}"
xsim_bin="${XSIM:-$vivado_root/bin/xsim}"

for tool in "$xvlog_bin" "$xelab_bin" "$xsim_bin"; do
  [[ -x "$tool" ]] || { echo "required XSim tool not found: $tool" >&2; exit 2; }
done
[[ -f "$vivado_root/data/xsim/xsim.ini" ]] || {
  echo "XSim library map not found under $vivado_root" >&2
  exit 2
}

mkdir -p "$repo_root/build/uvm" "$run_dir"
python3 "$repo_root/tools/gen_isa_sv.py" \
  "$repo_root/isa/isa.json" "$repo_root/build/simt_isa_pkg.sv"

rm -rf "$sim_dir"
mkdir -p "$sim_dir"
cp "$vivado_root/data/xsim/xsim.ini" "$sim_dir/xsim.ini"
ln -s "$repo_root/build" "$sim_dir/build"
cd "$sim_dir"

sources=(
  "$repo_root/build/simt_isa_pkg.sv"
  "$repo_root/rtl/simt_gpu_pkg.sv"
  "$repo_root/rtl/frontend/instruction_decoder.sv"
  "$repo_root/rtl/register_file/vector_register_file.sv"
  "$repo_root/rtl/register_file/predicate_register_file.sv"
  "$repo_root/rtl/execute/integer_lane.sv"
  "$repo_root/rtl/execute/vector_integer_alu.sv"
  "$repo_root/rtl/execute/completion_queue.sv"
  "$repo_root/rtl/execute/alu_completion_stage.sv"
  "$repo_root/rtl/execute/vector_multiplier_pipeline.sv"
  "$repo_root/rtl/control/round_robin_arbiter.sv"
  "$repo_root/rtl/execute/completion_arbiter.sv"
  "$repo_root/rtl/execute/architectural_writeback.sv"
  "$repo_root/rtl/control/dependency_scoreboard.sv"
  "$repo_root/rtl/control/fatal_fault_controller.sv"
  "$repo_root/rtl/frontend/warp_instruction_frontend.sv"
  "$repo_root/rtl/core/simt_core.sv"
  "$repo_root/tb/uvm/simt_core_if.sv"
  "$repo_root/tb/uvm/simt_core_uvm_pkg.sv"
  "$repo_root/tb/uvm/tb_simt_core_uvm.sv"
)

"$xvlog_bin" --sv --uvm_version 1.2 -L uvm \
  --include "$vivado_root/data/xsim/system_verilog/uvm_include" \
  --log "$run_dir/xvlog.log" "${sources[@]}"
"$xelab_bin" --uvm_version 1.2 -L uvm --debug typical \
  --timescale 1ns/1ps tb_simt_core_uvm -s tb_simt_core_uvm_sim \
  --log "$run_dir/xelab.log"

if [[ "${UVM_ELAB_ONLY:-0}" == 1 ]]; then
  echo "[PASS] UVM compile/elaboration"
  exit 0
fi

rm -f "$repo_root/build/uvm_four_warp.trace"
"$xsim_bin" tb_simt_core_uvm_sim --runall --onfinish quit \
  --testplusarg "UVM_TESTNAME=$uvm_test" --sv_seed "$seed" \
  --cov_db_dir "$repo_root/build/uvm/coverage" \
  --cov_db_name "${uvm_test}_${seed}" --log "$run_dir/xsim.log"

trace="$repo_root/build/uvm_four_warp.trace"
[[ -s "$trace" ]] || {
  echo 'UVM simulation did not produce its architectural trace' >&2
  exit 1
}

python3 "$repo_root/tools/hex_words_to_bin.py" \
  "$repo_root/build/uvm/program.hex" "$repo_root/build/uvm/program.bin"
"$repo_root/build/simt-emulator" "$repo_root/build/uvm/program.bin" --warps 4 \
  --trace "$repo_root/build/uvm/model.trace"
python3 "$repo_root/scripts/compare_arch_traces.py" --keyed \
  "$repo_root/build/uvm/model.trace" "$trace" >"$run_dir/comparison.txt"
cp "$repo_root/build/uvm/program.hex" "$repo_root/build/uvm/program.bin" \
  "$repo_root/build/uvm/model.trace" "$trace" "$run_dir/"
sed -n '1,20p' "$run_dir/comparison.txt"
