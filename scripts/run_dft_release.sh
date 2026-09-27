#!/usr/bin/env sh
set -eu
export ORFS_ROOT="${ORFS_ROOT:-/home/leech/OpenROAD-flow-scripts}"
command -v openroad >/dev/null 2>&1||{ echo 'openroad not found' >&2;exit 2;}
mkdir -p build/dft
test -s build/synthesis/simt_core_ihp_mapped.v||scripts/run_mapped_synthesis.sh
test -s build/synthesis/simt_mpw_wrapper_ihp_mapped.v||scripts/run_mpw_mapped_synthesis.sh
openroad -no_init -exit -log build/dft/core_scan_insertion.log \
  physical/run_scan_insertion.tcl
core_scan_cells=$(rg -c 'sg13g2_sd' build/dft/simt_core_scan.v||echo 0)
core_chains=$(sed -n 's/Number of chains: //p' build/dft/core_scan_insertion.log|tail -n 1)
test "$core_scan_cells" -gt 0||{ echo 'no core scan cells inserted' >&2;exit 1;}
test "$core_chains" -eq 4||{ echo "expected four core scan chains, found $core_chains" >&2;exit 1;}
python3 scripts/check_scan_netlist.py build/dft/simt_core_scan.v --chains 4 \
  --report build/dft/core_scan_audit.json
openroad -no_init -exit -log build/dft/scan_insertion.log \
  physical/run_mpw_scan_insertion.tcl
scan_cells=$(rg -c 'sg13g2_sd' build/dft/simt_mpw_wrapper_scan.v||echo 0)
chains=$(sed -n 's/Number of chains: //p' build/dft/scan_insertion.log|tail -n 1)
test "$scan_cells" -gt 0||{ echo 'no scan cells inserted' >&2;exit 1;}
test "$chains" -eq 4||{ echo "expected four scan chains, found $chains" >&2;exit 1;}
python3 scripts/check_scan_netlist.py build/dft/simt_mpw_wrapper_scan.v \
  --chains 4 --max-imbalance 4
scripts/run_mpw_scan_timing.sh
python3 scripts/write_dft_report.py "$scan_cells" "$chains"
echo "PASS core P&R scan artifact scan_cells=$core_scan_cells scan_chains=$core_chains"
echo "PASS MPW-wrapper DFT scan insertion scan_cells=$scan_cells scan_chains=$chains"
