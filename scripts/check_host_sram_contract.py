#!/usr/bin/env python3
import json
from pathlib import Path

root=Path(__file__).resolve().parents[1]
manifest=json.loads((root/"config/asic_build_manifest.json").read_text())
assert manifest["build"]=="production"
assert manifest["fault_injection_enabled"] is False
assert len(manifest["fault_injection_bits"])==5
assert manifest["host_maintenance_requires_quiescence"] is True
assert manifest["host_clear_preserves_memory"] is True
assert manifest["fault_preserves_memory"] is True

host=(root/"rtl/asic/asic_host_controller.sv").read_text()
for token in ("A_WATCHDOG","A_BUILD_ID","A_MACHINE","A_BREADCRUMB","A_SNAPSHOT",
              "A_WARP_PC0","A_STACK_TOP0","A_TRACKER0","A_MEM_COMMAND","A_INJECT",
              "quiescent_i||mem_busy_q||!host_mem_ready_i"):
    if token not in host: raise SystemExit(f"host contract missing {token}")
core=(root/"rtl/core/simt_core.sv").read_text()
for token in ("inject_fault_i[0]","inject_fault_i[1]","inject_fault_i[2]",
              "inject_fault_i[3]","inject_fault_i[4]","debug_stack_top_o",
              "debug_tracker_summary_o","debug_quiescent_o"):
    if token not in core: raise SystemExit(f"core integration missing {token}")
memory=(root/"rtl/memory/banked_vector_memory.sv").read_text()
for token in ("host_valid_i","host_ready_o","host_response_valid_o","host_q"):
    if token not in memory: raise SystemExit(f"memory maintenance port missing {token}")
if not (root/"tb/programs/asic_diagnostic.s").is_file():
    raise SystemExit("missing ASIC diagnostic program")
print("PASS host/SRAM release contract: production injection disabled, 5 hooks inventoried")
