#!/usr/bin/env sh
set -eu

export ORFS_ROOT="${ORFS_ROOT:-/home/leech/OpenROAD-flow-scripts}"
command -v openroad >/dev/null 2>&1 || { echo 'openroad not found' >&2; exit 2; }
test -f "$ORFS_ROOT/flow/Makefile" || { echo "ORFS flow not found: $ORFS_ROOT" >&2; exit 2; }

base=$(pwd)/build/physical/mpw_balanced
if ! python3 scripts/check_mpw_drt.py; then
  scripts/run_mpw_detailed_route.sh
fi

status=0
make -C "$ORFS_ROOT/flow" \
  do-5_3_fillcell do-5_route do-5_route.sdc do-finish \
  DESIGN_CONFIG="$(pwd)/physical/mpw_balanced/config.mk" \
  RESULTS_DIR="$base/results" LOG_DIR="$base/logs" \
  REPORTS_DIR="$base/reports" OBJECTS_DIR="$base/objects" || status=$?
python3 scripts/check_mpw_physical_close.py || status=$?
exit "$status"
