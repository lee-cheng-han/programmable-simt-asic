current_design simt_core

create_clock -name core_clk -period 40.000 [get_ports clk]
set_clock_uncertainty -setup 0.500 [get_clocks core_clk]
set_clock_uncertainty -hold 0.100 [get_clocks core_clk]
set_clock_transition 0.200 [get_clocks core_clk]

set non_clock_inputs [all_inputs -no_clocks]
set_input_delay 4.000 -clock core_clk $non_clock_inputs
set_output_delay 4.000 -clock core_clk [all_outputs]

set_false_path -from [get_ports rst]
set_false_path -from [get_ports scan_enable_i]

# Scan enable is a static functional-mode control.  Do not case-collapse the
# port here: leaving its electrical load visible lets physical optimization
# build a real distribution tree for all scan cells.  Scan data is functionally
# unobservable, so exclude SCD endpoints from this scenario.  Scan-shift timing
# is constrained and checked separately by the DFT release flow.
set_false_path -to [get_pins -hierarchical */SCD]
