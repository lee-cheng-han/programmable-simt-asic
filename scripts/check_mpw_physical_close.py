#!/usr/bin/env python3
"""Gate filled, extracted, timing-clean full-wrapper physical evidence."""

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def check_run(base: Path) -> list[str]:
    route_input = base / "results/5_2_route.odb"
    required = (
        "results/5_3_fillcell.odb",
        "results/5_route.odb",
        "results/5_route.sdc",
        "results/6_1_fill.odb",
        "results/6_1_fill.sdc",
        "logs/6_report.log",
        "logs/6_report.json",
        "results/6_final.odb",
        "results/6_final.def",
        "results/6_final.v",
        "results/6_final.sdc",
        "results/6_final.spef",
        "reports/VDD.rpt",
        "reports/VSS.rpt",
    )
    errors = [
        f"missing or empty {name}"
        for name in required
        if not (base / name).is_file() or (base / name).stat().st_size == 0
    ]
    if not route_input.is_file() or route_input.stat().st_size == 0:
        errors.append("missing or empty results/5_2_route.odb")
    else:
        input_mtime = route_input.stat().st_mtime_ns
        for name in required:
            path = base / name
            if path.is_file() and path.stat().st_mtime_ns < input_mtime:
                errors.append(f"stale physical-close artifact {name}")

    metrics_path = base / "logs/6_report.json"
    if metrics_path.is_file():
        try:
            metrics = json.loads(metrics_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            errors.append(f"invalid final metrics: {exc}")
        else:
            count = metrics.get("finish__flow__errors__count")
            if count != 0:
                errors.append(f"final flow error count is {count!r}, expected 0")
            for kind in ("setup", "hold"):
                key = f"finish__timing__{kind}__ws"
                slack = metrics.get(key)
                if not isinstance(slack, (int, float)):
                    errors.append(f"missing numeric {key}")
                elif slack < 0:
                    errors.append(f"negative extracted {kind} slack: {slack}")
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
            print(f"FAIL MPW-wrapper physical closure: {error}")
        return 1
    print("PASS MPW-wrapper physical closure: filled, extracted, and timing-clean")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
