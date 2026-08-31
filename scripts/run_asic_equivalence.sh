#!/usr/bin/env sh
set -eu
command -v yosys >/dev/null 2>&1 || { echo 'yosys not found' >&2; exit 2; }
if ! yosys -m slang -p 'help read_slang' >/dev/null 2>&1; then
  echo 'the Yosys slang plugin is required' >&2; exit 2
fi
mkdir -p build/signoff
python3 tools/gen_isa_sv.py isa/isa.json build/simt_isa_pkg.sv
sources='build/simt_isa_pkg.sv rtl/simt_gpu_pkg.sv formal/simt_core_equiv_model.sv rtl/asic/reset_synchronizer.sv rtl/asic/asic_host_controller.sv rtl/asic/sram_bist_controller.sv rtl/asic/simt_asic_top.sv'
# shellcheck disable=SC2086
yosys -Q -q -m slang -l build/signoff/rtl_to_synth_equivalence.log -p "
  read_slang --ignore-assertions --top simt_asic_top -G USE_IHP_IMEM=1 -G USE_IHP_DATA_SRAM=1 $sources;
  hierarchy -top simt_asic_top;
  proc; memory_map; opt; clean;
  equiv_opt -assert -async2sync synth -top simt_asic_top -flatten -noabc;
  write_verilog -noattr build/signoff/simt_asic_preopt.v
"
echo 'PASS ASIC RTL-to-synthesis equivalence'
echo 'report: build/signoff/rtl_to_synth_equivalence.log'
