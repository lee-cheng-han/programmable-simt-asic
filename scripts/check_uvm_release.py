#!/usr/bin/env python3
"""Check the frozen differential matrix for one XSim release."""

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROCESSOR_TESTS = (
    "constrained_random_differential_test",
    "backpressure_differential_test",
    "fetch_backpressure_differential_test",
    "structured_control_differential_test",
    "isa_coverage_differential_test",
    "fault_clear_relaunch_differential_test",
    "midflight_clear_relaunch_differential_test",
)
MEMORY_TESTS = (
    "memory_differential_test",
    "constrained_random_memory_differential_test",
)


def expected_cases() -> list[tuple[str, int]]:
    cases = [(test, seed) for test in PROCESSOR_TESTS for seed in range(1, 4)]
    cases += [(test, seed) for test in MEMORY_TESTS for seed in range(1, 6)]
    return cases


def check_run(run_dir: Path, release: str, test: str, seed=None) -> list[str]:
    errors = []
    required = (
        "xvlog.log", "xelab.log", "xsim.log", "comparison.txt",
        "portable_coverage.txt", "program.hex", "program.bin",
        "model.trace", "uvm_four_warp.trace", "run.cfg",
    )
    for name in required:
        if not (run_dir / name).is_file() or (run_dir / name).stat().st_size == 0:
            errors.append(f"missing or empty {name}")
    if errors:
        return errors

    comparison = (run_dir / "comparison.txt").read_text(encoding="utf-8")
    simulator = (run_dir / "xsim.log").read_text(encoding="utf-8")
    elaborator = (run_dir / "xelab.log").read_text(encoding="utf-8")
    if not re.search(r"^PASS architectural trace comparison events=\d+$", comparison,
                     re.MULTILINE):
        errors.append("architectural trace did not match")
    if f"Vivado Simulator v{release}" not in elaborator:
        errors.append("wrong XSim elaboration release")
    if not re.search(rf"Running test {re.escape(test)}\.\.\.", simulator):
        errors.append("wrong UVM test ran")
    for severity in ("ERROR", "FATAL"):
        if not re.search(rf"^UVM_{severity}\s*:\s*0\s*$", simulator,
                         re.MULTILINE):
            errors.append(f"nonzero or absent UVM_{severity} summary")
    if "$finish called" not in simulator:
        errors.append("simulation did not finish")
    if test == "structured_control_differential_test" and seed in (1, 2, 3):
        expected_warps = {1: 1, 2: 3, 3: 2}[seed]
        actual_warps = (run_dir / "run.cfg").read_text(encoding="utf-8").split()[0]
        if actual_warps != str(expected_warps):
            errors.append(f"structured-control warp count {actual_warps}; "
                          f"expected {expected_warps}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", required=True,
                        help="exact XSim release, for example 2025.2")
    args = parser.parse_args()
    if not re.fullmatch(r"\d{4}\.\d+", args.release):
        parser.error("release must look like 2025.2")

    runs = ROOT / "build" / "uvm" / "runs" / args.release
    expected = expected_cases()
    failures = {}
    for test, seed in expected:
        identity = f"{test}_{seed}"
        errors = check_run(runs / identity, args.release, test, seed)
        if errors:
            failures[identity] = errors

    result = {
        "release": args.release,
        "expected": len(expected),
        "passed": len(expected) - len(failures),
        "failures": failures,
    }
    report = ROOT / "build" / "uvm" / f"release_{args.release}.json"
    report.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"XSim {args.release} differential matrix: {result['passed']}/"
          f"{result['expected']} passed")
    print(f"report: {report}")
    for identity, errors in failures.items():
        print(f"FAIL {identity}: {', '.join(errors)}")
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
