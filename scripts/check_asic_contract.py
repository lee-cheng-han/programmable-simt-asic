#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
required = {
    "rtl/asic/simt_asic_top.sv": ("test_mode_i", "scan_enable_i", "wb_cyc_i", "reset_synchronizer"),
    "physical/constraints/functional.sdc": ("create_clock", "set_case_analysis 0 [get_ports test_mode_i]"),
    "physical/constraints/scan_shift.sdc": ("create_clock", "set_case_analysis 1 [get_ports test_mode_i]"),
    "physical/simt_asic.upf": ("create_power_domain PD_CORE", "set_domain_supply_net"),
}
for relative, tokens in required.items():
    path = ROOT / relative
    if not path.is_file():
        raise SystemExit(f"missing ASIC contract file: {relative}")
    text = path.read_text()
    for token in tokens:
        if token not in text:
            raise SystemExit(f"{relative}: missing contract token {token!r}")

host = (ROOT / "rtl/asic/asic_host_controller.sv").read_text()
addresses = [f"8'h{value:02x}" for value in range(0, 0x38, 4)]
missing = [address for address in addresses if address not in host]
if missing:
    raise SystemExit("host map is not contiguous through counters: " + ", ".join(missing))
print("PASS ASIC host, reset, scan-boundary, SDC, and UPF contracts")
