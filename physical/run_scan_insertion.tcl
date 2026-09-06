set platform "$::env(ORFS_ROOT)/flow/platforms/ihp-sg13g2"
read_lef "$platform/lef/sg13g2_tech.lef"
read_lef "$platform/lef/sg13g2_stdcell.lef"
read_lef "$platform/lef/RM_IHPSG13_1P_64x64_c2_bm_bist.lef"
read_liberty "$platform/lib/sg13g2_stdcell_typ_1p20V_25C.lib"
read_liberty "$platform/lib/RM_IHPSG13_1P_64x64_c2_bm_bist_typ_1p20V_25C.lib"
read_verilog build/synthesis/simt_core_ihp_mapped.v
link_design simt_core
create_clock -name core_clk -period 40.0 [get_ports clk]
set_dft_config -max_chains 4 -clock_mixing no_mix \
  -scan_enable_name_pattern scan_enable_i \
  -scan_in_name_pattern scan_in_{} -scan_out_name_pattern scan_out_{}
report_dft_config
scan_replace
report_dft_plan
execute_dft_plan

# Materialize constants introduced by scan replacement as real tie cells.
# Without this step OpenROAD writes implicit one_/zero_ nets with tens of
# thousands of sinks, which cannot be buffered or routed like ordinary logic.
insert_tiecells sg13g2_tiehi/L_HI -prefix dft_tiehi
insert_tiecells sg13g2_tielo/L_LO -prefix dft_tielo
write_verilog build/dft/simt_core_scan.v
write_db build/dft/simt_core_scan.odb
