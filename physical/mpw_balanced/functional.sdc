current_design simt_mpw_wrapper

create_clock -name user_clock -period 40.000 [get_ports user_clock_i]
set_clock_uncertainty -setup 0.500 [get_clocks user_clock]
set_clock_uncertainty -hold 0.100 [get_clocks user_clock]
set_clock_transition 0.200 [get_clocks user_clock]

set_input_delay 4.000 -clock user_clock [get_ports {
  wbs_cyc_i wbs_stb_i wbs_we_i wbs_adr_i[*] wbs_dat_i[*] wbs_sel_i[*]
  bist_start_i
}]
set_output_delay 4.000 -clock user_clock [get_ports {
  wbs_ack_o wbs_err_o wbs_dat_o[*]
  bist_active_o bist_done_o bist_fail_o bist_fail_shared_o bist_fail_address_o[*]
  irq_done_o irq_fault_o
}]

set_false_path -from [get_ports user_reset_n_i]
set_case_analysis 0 [get_ports test_mode_i]

# Preserve the scan-enable distribution electrically in functional mode while
# excluding scan-only launch/capture paths from the functional timing scenario.
set_false_path -from [get_ports scan_enable_i]
set_false_path -from [get_ports {scan_in_i scan_in_0 scan_in_1 scan_in_2 scan_in_3}]
set_false_path -to [get_ports {scan_out_o scan_out_0 scan_out_1 scan_out_2 scan_out_3}]
set_false_path -to [get_pins -hierarchical */SCD]
