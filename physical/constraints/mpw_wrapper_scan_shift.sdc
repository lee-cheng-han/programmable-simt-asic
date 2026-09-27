create_clock -name scan_clock -period 100.000 [get_ports user_clock_i]

set_case_analysis 1 [get_ports test_mode_i]
set_case_analysis 1 [get_ports scan_enable_i]
set_false_path -from [get_ports user_reset_n_i]

# The IHP scan-flop Liberty view has unconditional setup/hold arcs on both D
# and SCD. In shift mode D is functionally deselected, so exclude functional-D
# endpoints explicitly and time the stitched SCD path.
set scan_cells [get_cells -filter "ref_name =~ sg13g2_sd*" *]
set_false_path -to [get_pins -of_objects $scan_cells -filter "full_name =~ */D"]

set_input_delay 20.000 -clock scan_clock \
  [get_ports {scan_in_i scan_in_0 scan_in_1 scan_in_2 scan_in_3}]
set_output_delay 20.000 -clock scan_clock \
  [get_ports {scan_out_o scan_out_0 scan_out_1 scan_out_2 scan_out_3}]
