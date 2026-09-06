#!/usr/bin/env sh
set -eu

export ORFS_ROOT=${ORFS_ROOT:-/home/leech/OpenROAD-flow-scripts}
source_dir="$ORFS_ROOT/flow/platforms/ihp-sg13g2/lib"
output_dir=build/physical/balanced/lib
mkdir -p "$output_dir"

# The SRAM views use pF as their declared capacitance unit but encode the
# 64 fF output limit as 6.4e-14. Normalize only that known field to 0.064 pF;
# source PDK files remain untouched and checksums are retained for provenance.
for corner in fast_1p32V_m55C slow_1p08V_125C typ_1p20V_25C; do
  name="RM_IHPSG13_1P_64x64_c2_bm_bist_${corner}.lib"
  source="$source_dir/$name"
  test -s "$source"
  sed 's/max_capacitance  : "6.4e-14"/max_capacitance  : "0.064"/' \
    "$source" > "$output_dir/$name"
  test "$(rg -c 'max_capacitance  : "0.064"' "$output_dir/$name")" -eq 1
done
sha256sum "$source_dir"/RM_IHPSG13_1P_64x64_c2_bm_bist_*lib \
  > "$output_dir/source_sha256.txt"
sha256sum "$output_dir"/RM_IHPSG13_1P_64x64_c2_bm_bist_*lib \
  > "$output_dir/normalized_sha256.txt"
echo 'PASS normalized SRAM max capacitance to 0.064 pF'
