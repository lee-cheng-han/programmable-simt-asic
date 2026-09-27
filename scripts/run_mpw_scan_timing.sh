#!/usr/bin/env sh
set -eu

export ORFS_ROOT="${ORFS_ROOT:-/home/leech/OpenROAD-flow-scripts}"
sta_bin="$ORFS_ROOT/tools/install/OpenROAD/bin/sta"
netlist=build/dft/simt_mpw_wrapper_scan.v

test -x "$sta_bin" || { echo "OpenSTA not found: $sta_bin" >&2; exit 2; }
test -f "$netlist" || {
  echo "wrapper scan netlist not found; run make dft-release first" >&2
  exit 2
}

"$sta_bin" -exit physical/mpw_wrapper_scan_sta.tcl
echo 'scan timing report: build/dft/mpw_wrapper_scan_timing.rpt'
