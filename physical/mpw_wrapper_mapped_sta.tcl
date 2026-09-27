set platform "$::env(ORFS_ROOT)/flow/platforms/ihp-sg13g2"
set netlist "build/synthesis/simt_mpw_wrapper_ihp_mapped.v"
set report_dir "build/synthesis"

define_corners slow typ fast
read_liberty -corner slow "$platform/lib/sg13g2_stdcell_slow_1p08V_125C.lib"
read_liberty -corner slow "$platform/lib/RM_IHPSG13_1P_64x64_c2_bm_bist_slow_1p08V_125C.lib"
read_liberty -corner typ "$platform/lib/sg13g2_stdcell_typ_1p20V_25C.lib"
read_liberty -corner typ "$platform/lib/RM_IHPSG13_1P_64x64_c2_bm_bist_typ_1p20V_25C.lib"
read_liberty -corner fast "$platform/lib/sg13g2_stdcell_fast_1p32V_m40C.lib"
read_liberty -corner fast "$platform/lib/RM_IHPSG13_1P_64x64_c2_bm_bist_fast_1p32V_m55C.lib"

read_verilog $netlist
link_design simt_mpw_wrapper
read_sdc physical/constraints/mpw_wrapper_functional.sdc

report_checks -path_delay max -corner slow -group_path_count 10 -endpoint_path_count 1 \
  -fields {slew cap input fanout} -digits 3 \
  > "$report_dir/mpw_wrapper_mapped_timing.rpt"
report_check_types -max_slew -max_capacitance -max_fanout -violators \
  >> "$report_dir/mpw_wrapper_mapped_timing.rpt"

set worst_slack [sta::time_sta_ui [sta::worst_slack_cmd "max"]]
if {$worst_slack > 1.0e20} {
  puts stderr "ERROR: no constrained maximum-delay path found"
  exit 1
}
puts [format "MPW_WRAPPER_MAPPED_WORST_SLACK_NS %.3f" $worst_slack]
if {$worst_slack < 0.0} {
  puts [format "OPEN mapped MPW wrapper pre-placement setup slack is %.3f ns" $worst_slack]
} else {
  puts "PASS mapped MPW wrapper pre-placement timing"
}
