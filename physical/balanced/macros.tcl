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

# Keep memory banks at the core edges and leave the center for the wide vector
# datapath, register files, completion network, and clock distribution.  The
# eight shared-memory banks on the right are distributed over the core height;
# packing them at the bottom creates a narrow, macro-pin-limited routing band
# even when overall core utilization is low.
set index 0
foreach macro $macros {
  if {$index < 9} {
    set x 50
    set y [expr {50 + 120 * $index}]
  } else {
    set x 2870
    set y [expr {100 + 350 * ($index - 9)}]
  }
  mpl::place_macro $macro $x $y R0 true false
  incr index
}

# Keep standard cells out of the narrow region immediately west of the shared
# SRAM column.  The strip remains available to the signal router and gives the
# wide bank buses room to fan out before entering the macro-edge pin field.
create_blockage -region {2670 50 2870 2665}
