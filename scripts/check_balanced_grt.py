#!/usr/bin/env python3
"""Reject a balanced global-route result with residual congestion or errors."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def check_run(base: Path) -> list[str]:
    required = (
        "logs/5_1_grt.log",
        "logs/5_1_grt.json",
        "results/5_1_grt.odb",
        "results/5_1_grt.sdc",
        "results/route.guide",
    )
    errors = [f"missing or empty {name}" for name in required
              if not (base / name).is_file() or (base / name).stat().st_size == 0]
    metrics_path = base / "logs/5_1_grt.json"
    if metrics_path.is_file():
        try:
            metrics = json.loads(metrics_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            errors.append(f"invalid route metrics: {exc}")
        else:
            count = metrics.get("globalroute__flow__errors__count")
            if count != 0:
                errors.append(f"global-route error count is {count!r}, expected 0")

    log_path = base / "logs/5_1_grt.log"
    if log_path.is_file() and "[ERROR GRT-" in log_path.read_text(
            encoding="utf-8"):
        errors.append("global router reported an error")
    congestion = base / "reports/congestion.rpt"
    if not congestion.is_file():
        errors.append("missing congestion report")
    elif "violation type:" in congestion.read_text(encoding="utf-8"):
        errors.append("global-route congestion violations remain")
    return errors


def main() -> int:
    base = ROOT / "build/physical/balanced"
    errors = check_run(base)
    if errors:
        for error in errors:
            print(f"FAIL balanced global route: {error}")
        return 1
    print("PASS balanced global route: no reported errors or congestion")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
