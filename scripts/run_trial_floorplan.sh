#!/usr/bin/env sh
set -eu

command -v openroad >/dev/null 2>&1 || {
  echo 'openroad not found' >&2
  exit 2
}
export ORFS_ROOT=${ORFS_ROOT:-/home/leech/OpenROAD-flow-scripts}
scripts/check_sram_views.sh
mkdir -p build/physical
openroad -no_init -exit -log build/physical/openroad.log \
  physical/trial_floorplan.tcl
echo 'trial floorplan: build/physical/simt_macro_trial.def'
