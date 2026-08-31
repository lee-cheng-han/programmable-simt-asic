#!/usr/bin/env sh
set -eu
export ORFS_ROOT=${ORFS_ROOT:-/home/leech/OpenROAD-flow-scripts}
command -v openroad >/dev/null 2>&1||{ echo 'openroad not found' >&2;exit 2;}
mkdir -p build/dft
test -s build/synthesis/simt_core_ihp_mapped.v||scripts/run_mapped_synthesis.sh
openroad -no_init -exit physical/run_scan_insertion.tcl 2>&1|tee build/dft/scan_insertion.log
scan_cells=$(rg -c 'sg13g2_sd' build/dft/simt_core_scan.v||echo 0)
chains=$(sed -n 's/Number of chains: //p' build/dft/scan_insertion.log|tail -n 1)
test "$scan_cells" -gt 0||{ echo 'no scan cells inserted' >&2;exit 1;}
test "$chains" -eq 4||{ echo "expected four scan chains, found $chains" >&2;exit 1;}
python3 scripts/write_dft_report.py "$scan_cells" "$chains"
echo "PASS DFT scan insertion scan_cells=$scan_cells scan_chains=$chains"
