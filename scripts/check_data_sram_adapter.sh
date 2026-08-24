#!/usr/bin/env sh
set -eu
command -v yosys >/dev/null 2>&1||{ echo 'yosys not found' >&2;exit 2;}
mkdir -p build/synthesis
for configuration in behavioral macro
do
  parameter=''
  sources='rtl/memory/data_sram_bank_adapter.sv'
  if [ "$configuration" = macro ];then
    parameter='-G USE_IHP_MACRO=1'
    sources="$sources physical/ihp_sram_blackbox.sv"
  fi
  # Source and parameter splitting are intentional and repository-controlled.
  # shellcheck disable=SC2086
  yosys -m slang -ql "build/synthesis/data_sram_${configuration}.log" -p \
    "read_slang --ignore-assertions --top data_sram_bank_adapter $parameter $sources; hierarchy -check -top data_sram_bank_adapter; check; stat"
  echo "PASS data SRAM adapter configuration=$configuration"
done
