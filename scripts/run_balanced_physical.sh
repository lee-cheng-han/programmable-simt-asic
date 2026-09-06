#!/usr/bin/env sh
set -eu

export ORFS_ROOT=${ORFS_ROOT:-/home/leech/OpenROAD-flow-scripts}
command -v openroad >/dev/null 2>&1 || { echo 'openroad not found' >&2; exit 2; }
test -f "$ORFS_ROOT/flow/Makefile" || { echo "ORFS flow not found: $ORFS_ROOT" >&2; exit 2; }

mkdir -p build/physical/balanced
scripts/prepare_balanced_libs.sh
scripts/run_mapped_synthesis.sh
scripts/run_dft_release.sh

config=$(pwd)/physical/balanced/config.mk
results=$(pwd)/build/physical/balanced/results
logs=$(pwd)/build/physical/balanced/logs
reports=$(pwd)/build/physical/balanced/reports
objects=$(pwd)/build/physical/balanced/objects

make -C "$ORFS_ROOT/flow" \
  DESIGN_CONFIG="$config" \
  RESULTS_DIR="$results" LOG_DIR="$logs" \
  REPORTS_DIR="$reports" OBJECTS_DIR="$objects"

test -s "$results/6_final.gds"
test -s "$results/6_final.v"
test -s "$results/6_final.sdc"
echo "PASS balanced physical implementation"
echo "GDS: $results/6_final.gds"
echo "metrics: $logs/6_report.json"
