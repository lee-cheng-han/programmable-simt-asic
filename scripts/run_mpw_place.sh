#!/usr/bin/env sh
set -eu

export ORFS_ROOT="${ORFS_ROOT:-/home/leech/OpenROAD-flow-scripts}"
command -v openroad >/dev/null 2>&1 || { echo 'openroad not found' >&2; exit 2; }
test -f "$ORFS_ROOT/flow/Makefile" || { echo "ORFS flow not found: $ORFS_ROOT" >&2; exit 2; }

test -s build/dft/simt_mpw_wrapper_scan.v || scripts/run_dft_release.sh
scripts/prepare_balanced_libs.sh

base=$(pwd)/build/physical/mpw_balanced
mkdir -p "$base"
make -C "$ORFS_ROOT/flow" place \
  DESIGN_CONFIG="$(pwd)/physical/mpw_balanced/config.mk" \
  RESULTS_DIR="$base/results" LOG_DIR="$base/logs" \
  REPORTS_DIR="$base/reports" OBJECTS_DIR="$base/objects"

test -s "$base/results/3_place.odb"
test -s "$base/results/3_place.sdc"
openroad -no_init -exit -db "$base/results/3_place.odb" \
  physical/check_mpw_floorplan.tcl
echo 'PASS MPW-wrapper standard-cell placement'
echo "placement database: $base/results/3_place.odb"
