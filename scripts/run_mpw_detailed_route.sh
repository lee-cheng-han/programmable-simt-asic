#!/usr/bin/env sh
set -eu

export ORFS_ROOT="${ORFS_ROOT:-/home/leech/OpenROAD-flow-scripts}"
command -v openroad >/dev/null 2>&1 || { echo 'openroad not found' >&2; exit 2; }
test -f "$ORFS_ROOT/flow/Makefile" || { echo "ORFS flow not found: $ORFS_ROOT" >&2; exit 2; }

base=$(pwd)/build/physical/mpw_balanced
grt_stale=0
for source in physical/mpw_balanced/config.mk physical/mpw_balanced/functional.sdc \
              physical/mpw_balanced/macros.tcl build/dft/simt_mpw_wrapper_scan.v; do
  if ! test -s "$base/results/5_1_grt.odb" || ! test "$base/results/5_1_grt.odb" -nt "$source"; then
    grt_stale=1
  fi
done
if ! test "$grt_stale" -eq 0 || ! test -s "$base/results/5_1_grt.sdc"; then
  scripts/run_mpw_global_route.sh
fi

# Do not allow failed detailed-route evidence from an earlier invocation to be
# mistaken for this run if OpenROAD exits before rewriting every artifact.
if test -s "$base/logs/5_2_route.tmp.log"; then
  cp "$base/logs/5_2_route.tmp.log" \
    "$base/reports/5_2_route_interrupted.log"
fi
rm -f "$base/logs/5_2_route.log" "$base/logs/5_2_route.json" \
      "$base/logs/5_2_route.tmp.log" \
      "$base/reports/5_route_drc.rpt" "$base/reports/drt_antennas.log" \
      "$base/results/5_2_route.odb" "$base/results/maze.log"

status=0
make -C "$ORFS_ROOT/flow" do-5_2_route \
  DESIGN_CONFIG="$(pwd)/physical/mpw_balanced/config.mk" \
  RESULTS_DIR="$base/results" LOG_DIR="$base/logs" \
  REPORTS_DIR="$base/reports" OBJECTS_DIR="$base/objects" || status=$?
python3 scripts/check_mpw_drt.py || status=$?
exit "$status"
