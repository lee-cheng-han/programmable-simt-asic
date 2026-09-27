set block [ord::get_db_block]
if {[$block getName] ne "simt_mpw_wrapper"} {
  error "unexpected floorplan design [$block getName]"
}

set macros 0
foreach inst [$block getInsts] {
  if {[[$inst getMaster] getName] eq "RM_IHPSG13_1P_64x64_c2_bm_bist"} {
    incr macros
    if {![$inst isPlaced]} {
      error "unplaced SRAM macro [$inst getName]"
    }
  }
}
if {$macros != 17} {
  error "expected 17 placed SRAM macros, found $macros"
}
puts "PASS MPW floorplan audit design=[$block getName] placed_sram_macros=$macros"
