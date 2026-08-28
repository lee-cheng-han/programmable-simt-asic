#!/usr/bin/env python3
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
rtl_files = sorted((ROOT / "rtl").rglob("*.sv"))
event_re = re.compile(r"always_ff\s*@\(([^)]*)\)")
allowed = {"posedge clk", "posedge clk_i", "posedge clk_i or posedge async_reset_i"}
events = []
for path in rtl_files:
    text = path.read_text()
    for match in event_re.finditer(text):
        event = " ".join(match.group(1).split())
        events.append((path.relative_to(ROOT).as_posix(), event))
        if event not in allowed:
            raise SystemExit(f"unreviewed sequential event in {path.relative_to(ROOT)}: {event}")

async_events = [(path, event) for path, event in events if "async_reset_i" in event]
if async_events != [("rtl/asic/reset_synchronizer.sv", "posedge clk_i or posedge async_reset_i")]:
    raise SystemExit(f"unexpected asynchronous state elements: {async_events}")

top = (ROOT / "rtl/asic/simt_asic_top.sv").read_text()
required_top = (
    "reset_synchronizer reset_u",
    "assign core_reset = reset_sync || test_mode_i",
    ".clk(clk_i)",
    ".clk_i",
)
for token in required_top:
    if token not in top:
        raise SystemExit(f"ASIC top missing reviewed clock/reset token: {token}")

functional = (ROOT / "physical/constraints/functional.sdc").read_text()
if functional.count("create_clock") != 1 or "core_clk" not in functional:
    raise SystemExit("functional SDC must define exactly one core clock")
if "set_false_path -from [get_ports reset_n_i]" not in functional:
    raise SystemExit("external asynchronous reset path is not declared")

print(f"PASS clock/reset inventory: {len(events)} state processes, one clock domain, one reviewed async reset synchronizer")
