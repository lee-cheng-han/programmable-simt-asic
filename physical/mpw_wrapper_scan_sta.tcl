set platform "$::env(ORFS_ROOT)/flow/platforms/ihp-sg13g2"
set report_dir "build/dft"

define_corners slow typ fast
read_liberty -corner slow "$platform/lib/sg13g2_stdcell_slow_1p08V_125C.lib"
read_liberty -corner slow "$platform/lib/RM_IHPSG13_1P_64x64_c2_bm_bist_slow_1p08V_125C.lib"
read_liberty -corner typ "$platform/lib/sg13g2_stdcell_typ_1p20V_25C.lib"
read_liberty -corner typ "$platform/lib/RM_IHPSG13_1P_64x64_c2_bm_bist_typ_1p20V_25C.lib"
read_liberty -corner fast "$platform/lib/sg13g2_stdcell_fast_1p32V_m40C.lib"
read_liberty -corner fast "$platform/lib/RM_IHPSG13_1P_64x64_c2_bm_bist_fast_1p32V_m55C.lib"

read_verilog build/dft/simt_mpw_wrapper_scan.v
link_design simt_mpw_wrapper
read_sdc physical/constraints/mpw_wrapper_scan_shift.sdc

report_checks -path_delay max -corner slow -group_path_count 10 -endpoint_path_count 1 \
  -fields {slew cap input fanout} -digits 3 \
  > "$report_dir/mpw_wrapper_scan_timing.rpt"
report_checks -path_delay min -corner fast -group_path_count 10 -endpoint_path_count 1 \
  -fields {slew cap input fanout} -digits 3 \
  >> "$report_dir/mpw_wrapper_scan_timing.rpt"

set setup_slack [sta::time_sta_ui [sta::worst_slack_cmd "max"]]
set hold_slack [sta::time_sta_ui [sta::worst_slack_cmd "min"]]
if {$setup_slack > 1.0e20 || $hold_slack > 1.0e20} {
  puts stderr "ERROR: no constrained scan-shift setup/hold path found"
  exit 1
}
puts [format "MPW_SCAN_SETUP_SLACK_NS %.3f" $setup_slack]
puts [format "MPW_SCAN_HOLD_SLACK_NS %.3f" $hold_slack]
set summary [open "$report_dir/mpw_wrapper_scan_timing.txt" w]
puts $summary [format "setup_slack_ns=%.3f" $setup_slack]
puts $summary [format "hold_slack_ns=%.3f" $hold_slack]
puts $summary "setup_status=[expr {$setup_slack >= 0.0 ? "passed" : "open"}]"
puts $summary "hold_status=[expr {$hold_slack >= 0.0 ? "passed" : "open"}]"
close $summary
if {$setup_slack < 0.0} {
  puts stderr [format "ERROR: scan-shift setup slack is %.3f ns" $setup_slack]
  exit 1
}
puts "PASS pre-placement scan-shift setup timing"
