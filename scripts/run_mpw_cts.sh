#!/usr/bin/env sh
set -eu

export ORFS_ROOT="${ORFS_ROOT:-/home/leech/OpenROAD-flow-scripts}"
command -v openroad >/dev/null 2>&1 || { echo 'openroad not found' >&2; exit 2; }
test -f "$ORFS_ROOT/flow/Makefile" || { echo "ORFS flow not found: $ORFS_ROOT" >&2; exit 2; }

test -s build/dft/simt_mpw_wrapper_scan.v || scripts/run_dft_release.sh
for corner in fast_1p32V_m55C slow_1p08V_125C typ_1p20V_25C; do
  test -s "build/physical/balanced/lib/RM_IHPSG13_1P_64x64_c2_bm_bist_${corner}.lib" || {
    scripts/prepare_balanced_libs.sh
    break
  }
done

base=$(pwd)/build/physical/mpw_balanced
mkdir -p "$base"
placement_stale=0
for source in physical/mpw_balanced/config.mk physical/mpw_balanced/functional.sdc \
              physical/mpw_balanced/macros.tcl build/dft/simt_mpw_wrapper_scan.v; do
  if ! test -s "$base/results/3_place.odb" || ! test "$base/results/3_place.odb" -nt "$source"; then
    placement_stale=1
  fi
done
if ! test "$placement_stale" -eq 0 || ! test -s "$base/results/3_place.sdc"; then
  scripts/run_mpw_place.sh
fi

# Run only the CTS stage from the already audited placement checkpoint. The
# ordinary `cts` dependency graph may rebuild every earlier stage when generated
# SRAM Liberty timestamps change, even though the placed OpenDB is self-contained.
make -C "$ORFS_ROOT/flow" do-cts \
  DESIGN_CONFIG="$(pwd)/physical/mpw_balanced/config.mk" \
  RESULTS_DIR="$base/results" LOG_DIR="$base/logs" \
  REPORTS_DIR="$base/reports" OBJECTS_DIR="$base/objects"

test -s "$base/results/4_cts.odb"
test -s "$base/results/4_cts.sdc"
openroad -no_init -exit -db "$base/results/4_cts.odb" \
  physical/check_mpw_floorplan.tcl
echo 'PASS MPW-wrapper clock-tree synthesis'
echo "CTS database: $base/results/4_cts.odb"
