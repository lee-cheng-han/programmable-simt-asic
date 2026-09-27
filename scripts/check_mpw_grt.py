#!/usr/bin/env python3
"""Reject a full-wrapper global route with stale or incomplete evidence."""

import argparse
from check_balanced_grt import check_run
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


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
            print(f"FAIL MPW-wrapper global route: {error}")
        return 1
    print("PASS MPW-wrapper global route: no reported errors or congestion")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
