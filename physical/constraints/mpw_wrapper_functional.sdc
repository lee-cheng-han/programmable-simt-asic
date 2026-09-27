create_clock -name user_clock -period 40.000 [get_ports user_clock_i]

set_input_delay 8.000 -clock user_clock [get_ports {
  wbs_cyc_i wbs_stb_i wbs_we_i wbs_adr_i[*] wbs_dat_i[*] wbs_sel_i[*]
  bist_start_i
}]
set_output_delay 8.000 -clock user_clock [get_ports {
  wbs_ack_o wbs_err_o wbs_dat_o[*]
  bist_active_o bist_done_o bist_fail_o bist_fail_shared_o bist_fail_address_o[*]
  irq_done_o irq_fault_o
}]

set_false_path -from [get_ports user_reset_n_i]
set_case_analysis 0 [get_ports test_mode_i]
set_case_analysis 0 [get_ports scan_enable_i]
