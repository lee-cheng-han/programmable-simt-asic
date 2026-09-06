set platform "$::env(ORFS_ROOT)/flow/platforms/ihp-sg13g2"
define_corners slow typ fast
read_liberty -corner slow "$platform/lib/sg13g2_stdcell_slow_1p08V_125C.lib"
read_liberty -corner slow "$platform/lib/RM_IHPSG13_1P_64x64_c2_bm_bist_slow_1p08V_125C.lib"
read_liberty -corner typ "$platform/lib/sg13g2_stdcell_typ_1p20V_25C.lib"
read_liberty -corner typ "$platform/lib/RM_IHPSG13_1P_64x64_c2_bm_bist_typ_1p20V_25C.lib"
read_liberty -corner fast "$platform/lib/sg13g2_stdcell_fast_1p32V_m40C.lib"
read_liberty -corner fast "$platform/lib/RM_IHPSG13_1P_64x64_c2_bm_bist_fast_1p32V_m55C.lib"
read_db build/physical/balanced/results/1_synth.odb
read_sdc build/physical/balanced/results/1_synth.sdc
source "$platform/setRC.tcl"
report_checks -path_delay max -corner slow -group_count 5 -endpoint_count 1 \
  -fields {slew cap input nets fanout} -digits 3
report_check_types -max_slew -max_capacitance -max_fanout -violators
