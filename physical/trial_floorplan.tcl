set orfs_root $::env(ORFS_ROOT)
set platform "$orfs_root/flow/platforms/ihp-sg13g2"
read_lef "$platform/lef/sg13g2_tech.lef"
read_lef "$platform/lef/sg13g2_stdcell.lef"
read_lef "$platform/lef/RM_IHPSG13_1P_64x64_c2_bm_bist.lef"
read_liberty "$platform/lib/sg13g2_stdcell_typ_1p20V_25C.lib"
read_liberty "$platform/lib/RM_IHPSG13_1P_64x64_c2_bm_bist_typ_1p20V_25C.lib"
read_verilog physical/simt_macro_trial.v
link_design simt_macro_trial
initialize_floorplan -die_area {0 0 1700 800} -core_area {20 20 1680 780} \
  -site CoreSite

set left {imem scratch_0 scratch_1 scratch_2 scratch_3 scratch_4 scratch_5 scratch_6 scratch_7}
set right {shared_0 shared_1 shared_2 shared_3 shared_4 shared_5 shared_6 shared_7}
set y 35
foreach instance $left {
  place_macro -macro_name $instance -location [list 35 $y] -orientation R0 -exact
  set y [expr {$y + 78}]
}
set y 35
foreach instance $right {
  place_macro -macro_name $instance -location [list 850 $y] -orientation R0 -exact
  set y [expr {$y + 78}]
}

check_placement -verbose -report_file_name build/physical/placement.rpt
write_def build/physical/simt_macro_trial.def
write_db build/physical/simt_macro_trial.odb
