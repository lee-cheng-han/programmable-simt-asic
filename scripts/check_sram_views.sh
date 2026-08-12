#!/usr/bin/env sh
set -eu

orfs_root=${ORFS_ROOT:-/home/leech/OpenROAD-flow-scripts}
platform="$orfs_root/flow/platforms/ihp-sg13g2"

check_macro() {
  macro=$1
  for view in \
    "lef/$macro.lef" \
    "gds/$macro.gds" \
    "cdl/$macro.cdl" \
    "verilog/$macro.v" \
    "lib/${macro}_typ_1p20V_25C.lib" \
    "lib/${macro}_slow_1p08V_125C.lib" \
    "lib/${macro}_fast_1p32V_m55C.lib"
  do
    test -s "$platform/$view" || {
      echo "missing SRAM view: $platform/$view" >&2
      exit 1
    }
  done

  lef="$platform/lef/$macro.lef"
  model="$platform/verilog/$macro.v"
  rg -q "MACRO $macro" "$lef"
  rg -q 'CLASS BLOCK' "$lef"
  rg -q 'PIN VDD!' "$lef"
  rg -q 'PIN VDDARRAY!' "$lef"
  rg -q 'PIN VSS!' "$lef"
  rg -q 'A_BIST_EN' "$model"
  rg -q 'A_BM' "$model"
  rg -q 'A_DOUT' "$model"
  size=$(awk '/^[[:space:]]*SIZE / { print $2 "x" $4; exit }' "$lef")
  echo "PASS $macro views=7 size_um=$size"
}

command -v rg >/dev/null 2>&1 || {
  echo 'rg not found' >&2
  exit 2
}

check_macro RM_IHPSG13_1P_64x64_c2_bm_bist
check_macro RM_IHPSG13_1P_256x64_c2_bm_bist
