include $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../balanced/config.mk)

export DESIGN_NICKNAME = simt-mpw-balanced
export DESIGN_NAME = simt_mpw_wrapper
export SYNTH_NETLIST_FILES = $(PROJECT_ROOT)/build/dft/simt_mpw_wrapper_scan.v
export SDC_FILE = $(PROJECT_ROOT)/physical/mpw_balanced/functional.sdc
export MACRO_PLACEMENT_TCL = $(PROJECT_ROOT)/physical/mpw_balanced/macros.tcl

# Right-angle SRAM orientation is legal but OpenROAD's optional DPO polish can
# corrupt site alignment beside the rotated macro edges. Initial detailed
# placement and its full legality check remain enabled.
export ENABLE_DPO = 0
