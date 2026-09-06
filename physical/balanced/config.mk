PROJECT_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)

export DESIGN_NICKNAME = simt-balanced
export DESIGN_NAME = simt_core
export PLATFORM = ihp-sg13g2

# Physical implementation starts from the production, four-chain DFT netlist.
export SYNTH_NETLIST_FILES = $(PROJECT_ROOT)/build/dft/simt_core_scan.v
export SDC_FILE = $(PROJECT_ROOT)/physical/balanced/functional.sdc

export ADDITIONAL_LEFS = $(PLATFORM_DIR)/lef/RM_IHPSG13_1P_64x64_c2_bm_bist.lef
export ADDITIONAL_TYP_LIBS = $(PROJECT_ROOT)/build/physical/balanced/lib/RM_IHPSG13_1P_64x64_c2_bm_bist_typ_1p20V_25C.lib
export ADDITIONAL_SLOW_LIBS = $(PROJECT_ROOT)/build/physical/balanced/lib/RM_IHPSG13_1P_64x64_c2_bm_bist_slow_1p08V_125C.lib
export ADDITIONAL_FAST_LIBS = $(PROJECT_ROOT)/build/physical/balanced/lib/RM_IHPSG13_1P_64x64_c2_bm_bist_fast_1p32V_m55C.lib
export ADDITIONAL_GDS = $(PLATFORM_DIR)/gds/RM_IHPSG13_1P_64x64_c2_bm_bist.gds

export DIE_AREA = 0 0 3700 3000
export CORE_AREA = 30 30 3670 2970
export PLACE_DENSITY = 0.55
export TNS_END_PERCENT = 100
export TIE_SEPARATION = 0
export SKIP_REPAIR_TIE_FANOUT = 1
export MACRO_PLACE_HALO = 20 20
export MACRO_PLACEMENT_TCL = $(PROJECT_ROOT)/physical/balanced/macros.tcl
export PDN_TCL = $(PROJECT_ROOT)/physical/balanced/pdn.tcl
export POST_SYNTH_TCL = $(PROJECT_ROOT)/physical/balanced/post_synth.tcl
export POST_FLOORPLAN_TCL = $(PROJECT_ROOT)/physical/balanced/post_floorplan.tcl
export PRE_GLOBAL_ROUTE_TCL = $(PROJECT_ROOT)/physical/balanced/pre_global_route.tcl
export MAX_ROUTING_LAYER = TopMetal2
export CORNERS = slow typ fast
export REMOVE_ABC_BUFFERS = 1
export GPL_ROUTABILITY_DRIVEN = 1

# The default CTS non-default routing rule consumes scarce capacity around the
# SRAM pins and is deterministically disabled by FastRoute during congestion
# recovery.  Build the clock tree without that NDR up front so routing is both
# reproducible and does not require a second full negotiation pass.
export CTS_ARGS = -sink_clustering_enable -repair_clock_nets -apply_ndr none

# Preserve reproducibility and make expensive metrics explicit.
export DETAILED_METRICS = 1
export REPORT_CLOCK_SKEW = 1
export GENERATE_ARTIFACTS_ON_FAILURE = 1
export SKIP_REPORT_METRICS = 1
