set orfs_root $::env(ORFS_ROOT)
set platform "$orfs_root/flow/platforms/ihp-sg13g2"
read_lef "$platform/lef/sg13g2_tech.lef"
read_lef "$platform/lef/sg13g2_stdcell.lef"
read_lef "$platform/lef/RM_IHPSG13_1P_64x64_c2_bm_bist.lef"
read_liberty "$platform/lib/sg13g2_stdcell_typ_1p20V_25C.lib"
read_liberty "$platform/lib/RM_IHPSG13_1P_64x64_c2_bm_bist_typ_1p20V_25C.lib"
read_verilog build/synthesis/simt_core_ihp_mapped.v
read_verilog physical/simt_integrated_trial.v
link_design simt_integrated_trial
initialize_floorplan -die_area {0 0 3200 2500} -core_area {30 30 3170 2470} \
  -site CoreSite

set macros {}
set block [ord::get_db_block]
foreach inst [$block getInsts] {
  if {[[$inst getMaster] getName] eq "RM_IHPSG13_1P_64x64_c2_bm_bist"} {
    lappend macros $inst
  }
}
if {[llength $macros] != 17} {
  error "expected 17 integrated SRAM macros, found [llength $macros]"
}
set index 0
foreach macro $macros {
  if {$index < 9} {
    set x 45
    set y [expr {45 + 120 * $index}]
  } else {
    set x 2370
    set y [expr {45 + 120 * ($index - 9)}]
  }
  mpl::place_macro $macro $x $y R0 true false
  incr index
}

cut_rows
global_placement -density 0.60 -skip_io
detailed_placement -max_displacement {1000 1000}
check_placement -report_file_name build/physical/integrated_placement.rpt
write_def build/physical/simt_integrated_trial.def
write_db build/physical/simt_integrated_trial.odb
