#!/usr/bin/env python3
"""Merge simulator-independent architectural coverage manifests."""

from pathlib import Path
import os

ROOT = Path(__file__).resolve().parents[1]
RUNS = ROOT / "build" / "uvm" / "runs"
RELEASE = os.environ.get("XSIM_RELEASE")
REPORT = ROOT / "build" / "uvm" / (
    f"portable_coverage_report_{RELEASE}.md" if RELEASE
    else "portable_coverage_report.md"
)

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
if RELEASE and os.environ.get("REQUIRE_COVERAGE_CLOSURE") == "1":
    from check_uvm_release import expected_cases

    manifests = [RUNS / RELEASE / f"{test}_{seed}" / "portable_coverage.txt"
                 for test, seed in expected_cases()]
    missing = [str(path) for path in manifests if not path.is_file()]
    if missing:
        raise SystemExit(f"missing approved release manifests: {', '.join(missing)}")
elif RELEASE:
    manifests = sorted((RUNS / RELEASE).glob("*/portable_coverage.txt"))
else:
    manifests = sorted(RUNS.rglob("portable_coverage.txt"))
if not manifests:
    raise SystemExit(f"no portable coverage manifests found for {RELEASE or 'any release'}")
if not RELEASE and os.environ.get("REQUIRE_COVERAGE_CLOSURE") == "1":
    releases = {manifest.relative_to(RUNS).parts[0]
                if len(manifest.relative_to(RUNS).parts) > 2 else "legacy"
                for manifest in manifests}
    if len(releases) > 1:
        raise SystemExit("multiple XSim releases found; set XSIM_RELEASE for closure")
for manifest in manifests:
    for line in manifest.read_text(encoding="utf-8").splitlines():
        name, value = line.split()
        if name in observed:
            observed[name].add(int(value))

lines = [
    "# Portable architectural coverage report", "",
    f"XSim release: {RELEASE or 'mixed/legacy'}.  ",
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
if os.environ.get("REQUIRE_COVERAGE_CLOSURE") == "1" and total_hit != total_bins:
    raise SystemExit(f"coverage closure failed: {total_hit}/{total_bins} bins hit")
