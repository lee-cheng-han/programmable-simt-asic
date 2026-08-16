#!/usr/bin/env python3
"""Merge simulator-independent architectural coverage manifests."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNS = ROOT / "build" / "uvm" / "runs"
REPORT = ROOT / "build" / "uvm" / "portable_coverage_report.md"

EXPECTED = {
    "opcode": set(range(1, 26)) | {26, 27, 29, 30, 31},
    "warp": set(range(4)),
    "source": {0, 1},
    "resident_warps": {1, 2, 3, 4},
    "mask_class": {1, 2, 3},
    "execute_stall": {0, 1},
    "writeback_stall": {0, 1},
    "memory_kind": {0, 1},
    "memory_space": {0, 1},
}

observed = {name: set() for name in EXPECTED}
manifests = sorted(RUNS.glob("*/portable_coverage.txt"))
if not manifests:
    raise SystemExit("no portable coverage manifests found")
for manifest in manifests:
    for line in manifest.read_text(encoding="utf-8").splitlines():
        name, value = line.split()
        if name in observed:
            observed[name].add(int(value))

lines = [
    "# Portable architectural coverage report", "",
    f"Merged manifests: {len(manifests)}.", "",
    "| Coverage point | Hit | Total | Percent | Missing bins |",
    "|---|---:|---:|---:|---|",
]
total_hit = total_bins = 0
for name, expected in EXPECTED.items():
    hit = expected & observed[name]
    missing = sorted(expected - hit)
    total_hit += len(hit)
    total_bins += len(expected)
    percent = 100.0 * len(hit) / len(expected)
    lines.append(
        f"| `{name}` | {len(hit)} | {len(expected)} | {percent:.1f}% | "
        f"{', '.join(map(str, missing)) or 'none'} |"
    )
overall = 100.0 * total_hit / total_bins
lines.extend(("", f"Aggregate risk-bin coverage: {total_hit}/{total_bins} "
              f"({overall:.1f}%)."))
REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"portable coverage {total_hit}/{total_bins} ({overall:.1f}%)")
print(f"report: {REPORT}")
