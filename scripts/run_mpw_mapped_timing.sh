#!/usr/bin/env sh
set -eu

export ORFS_ROOT="${ORFS_ROOT:-/home/leech/OpenROAD-flow-scripts}"
sta_bin="$ORFS_ROOT/tools/install/OpenROAD/bin/sta"
netlist=build/synthesis/simt_mpw_wrapper_ihp_mapped.v

test -x "$sta_bin" || { echo "OpenSTA not found: $sta_bin" >&2; exit 2; }
test -f "$netlist" || {
  echo "mapped MPW netlist not found; run make synth-mpw-mapped first" >&2
  exit 2
}

"$sta_bin" -exit physical/mpw_wrapper_mapped_sta.tcl
echo 'mapped wrapper timing report: build/synthesis/mpw_wrapper_mapped_timing.rpt'
