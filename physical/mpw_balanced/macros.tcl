set macros {}
set block [ord::get_db_block]
foreach inst [$block getInsts] {
  if {[[$inst getMaster] getName] eq "RM_IHPSG13_1P_64x64_c2_bm_bist"} {
    lappend macros $inst
  }
}
if {[llength $macros] != 17} {
  error "expected 17 SRAM macros, found [llength $macros]"
}

# Almost every SRAM signal is on the macro's 784 um bottom edge. R90 turns that
# pin row into a vertical edge and eliminates the horizontal pin-band overflow
# seen with R0 banks. Nine banks line the bottom and eight line the top, leaving
# a broad central region for the vector datapath and clock-tree standard cells.
set index 0
foreach macro $macros {
  if {$index < 9} {
    set x [expr {100 + 340 * $index}]
    set y 50
  } else {
    set x [expr {200 + 370 * ($index - 9)}]
    set y 2150
  }
  mpl::place_macro $macro $x $y R90 true false
  incr index
}
