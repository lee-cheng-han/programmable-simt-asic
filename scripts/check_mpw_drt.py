#!/usr/bin/env python3
"""Reject stale, incomplete, unrouted, or DRC-dirty wrapper route evidence."""

import argparse
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]


def check_run(base: Path) -> list[str]:
    route_input = base / "results/5_1_grt.odb"
    required = (
        "logs/5_2_route.log",
        "logs/5_2_route.json",
        "results/5_2_route.odb",
        "results/maze.log",
        "reports/5_route_drc.rpt",
        "reports/drt_antennas.log",
    )
    errors = [
        f"missing {name}"
        for name in required
        if not (base / name).is_file()
    ]
    if not route_input.is_file() or route_input.stat().st_size == 0:
        errors.append("missing or empty results/5_1_grt.odb")
    else:
        input_mtime = route_input.stat().st_mtime_ns
        for name in required:
            path = base / name
            if path.is_file() and path.stat().st_mtime_ns < input_mtime:
                errors.append(f"stale detailed-route artifact {name}")

    metrics_path = base / "logs/5_2_route.json"
    if metrics_path.is_file():
        try:
            metrics = json.loads(metrics_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            errors.append(f"invalid route metrics: {exc}")
        else:
            count = metrics.get("detailedroute__flow__errors__count")
            if count != 0:
                errors.append(f"detailed-route error count is {count!r}, expected 0")

    log_path = base / "logs/5_2_route.log"
    log_text = log_path.read_text(encoding="utf-8") if log_path.is_file() else ""
    if "Design has unrouted nets." in log_text:
        errors.append("detailed router left unrouted nets")
    if re.search(r"\[ERROR (?:DRT|GRT)-", log_text):
        errors.append("detailed router reported an error")

    drc_path = base / "reports/5_route_drc.rpt"
    if drc_path.is_file():
        drc_text = drc_path.read_text(encoding="utf-8")
        if "violation type:" in drc_text:
            errors.append("detailed-route DRC violations remain")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--base",
        type=Path,
        default=ROOT / "build/physical/mpw_balanced",
        help="physical-run directory containing results/logs/reports",
    )
    args = parser.parse_args()
    errors = check_run(args.base)
    if errors:
        for error in errors:
            print(f"FAIL MPW-wrapper detailed route: {error}")
        return 1
    print("PASS MPW-wrapper detailed route: routed with no reported DRC errors")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
