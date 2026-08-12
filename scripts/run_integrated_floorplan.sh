#!/usr/bin/env sh
set -eu
command -v openroad >/dev/null 2>&1 || { echo 'openroad not found' >&2; exit 2; }
test -s build/synthesis/simt_core_ihp_mapped.v || {
  echo 'run make synth-mapped first' >&2; exit 2
}
export ORFS_ROOT=${ORFS_ROOT:-/home/leech/OpenROAD-flow-scripts}
mkdir -p build/physical
openroad -no_init -exit -log build/physical/integrated_openroad.log \
  physical/integrated_trial_floorplan.tcl
echo 'integrated trial: build/physical/simt_integrated_trial.def'
