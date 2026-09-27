#!/usr/bin/env sh
set -eu

export ORFS_ROOT="${ORFS_ROOT:-/home/leech/OpenROAD-flow-scripts}"
command -v openroad >/dev/null 2>&1 || { echo 'openroad not found' >&2; exit 2; }
test -f "$ORFS_ROOT/flow/Makefile" || { echo "ORFS flow not found: $ORFS_ROOT" >&2; exit 2; }

base=$(pwd)/build/physical/mpw_balanced
cts_stale=0
for source in physical/mpw_balanced/config.mk physical/mpw_balanced/functional.sdc \
              physical/mpw_balanced/macros.tcl build/dft/simt_mpw_wrapper_scan.v; do
  if ! test -s "$base/results/4_cts.odb" || ! test "$base/results/4_cts.odb" -nt "$source"; then
    cts_stale=1
  fi
done
if ! test "$cts_stale" -eq 0 || ! test -s "$base/results/4_cts.sdc"; then
  scripts/run_mpw_cts.sh
fi

# FastRoute only writes congestion.rpt when violation boxes remain.  Remove a
# report from an earlier failed floorplan so a clean run cannot inherit it.
rm -f "$base/reports/congestion.rpt"

status=0
make -C "$ORFS_ROOT/flow" do-grt \
  DESIGN_CONFIG="$(pwd)/physical/mpw_balanced/config.mk" \
  RESULTS_DIR="$base/results" LOG_DIR="$base/logs" \
  REPORTS_DIR="$base/reports" OBJECTS_DIR="$base/objects" || status=$?
python3 scripts/check_mpw_grt.py || status=$?
exit "$status"
