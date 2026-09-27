#!/usr/bin/env python3
"""Reject a balanced global-route result with residual congestion or errors."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def check_run(base: Path) -> list[str]:
    route_input = base / "results/4_cts.odb"
    required = (
        "logs/5_1_grt.log",
        "logs/5_1_grt.json",
        "results/5_1_grt.odb",
        "results/5_1_grt.sdc",
        "results/route.guide",
    )
    errors = [f"missing or empty {name}" for name in required
              if not (base / name).is_file() or (base / name).stat().st_size == 0]
    if not route_input.is_file() or route_input.stat().st_size == 0:
        errors.append("missing or empty results/4_cts.odb")
    else:
        input_mtime = route_input.stat().st_mtime_ns
        freshness_outputs = required
        for name in freshness_outputs:
            path = base / name
            if path.is_file() and path.stat().st_mtime_ns < input_mtime:
                errors.append(f"stale global-route artifact {name}")
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
    log_text = ""
    if log_path.is_file():
        log_text = log_path.read_text(encoding="utf-8")
        if "[ERROR GRT-" in log_text:
            errors.append("global router reported an error")
    congestion = base / "reports/congestion.rpt"
    congestion_is_current = (
        congestion.is_file()
        and route_input.is_file()
        and congestion.stat().st_mtime_ns >= route_input.stat().st_mtime_ns
    )
    if not congestion_is_current:
        # FastRoute omits the final report when there are no violation boxes.
        # A stale report belongs to an earlier run and is equivalent to no
        # report. Require the current log's final summary to prove all values
        # are zero rather than accepting a missing/stale file alone.
        final_zero = any(
            line.strip().startswith("Total") and line.rstrip().endswith("0 /  0 /  0")
            for line in log_text.splitlines()
        )
        if not final_zero:
            errors.append("missing congestion report and zero-congestion summary")
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
