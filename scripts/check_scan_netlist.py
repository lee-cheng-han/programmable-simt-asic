#!/usr/bin/env python3
"""Prove that every inserted scan cell belongs to one complete scan chain."""

import argparse
import json
import re
from pathlib import Path


CELL_RE = re.compile(
    r"^\s*(sg13g2_sd\w+)\s+(\S+)\s+\((.*?)\);\s*$",
    re.MULTILINE | re.DOTALL,
)
PORT_RE = re.compile(r"\.(Q|SCD|SCE)\((.*?)\)(?:,|\)|$)", re.DOTALL)
OUTPUT_RE = re.compile(r"assign\s+(scan_out_\d+)\s*=\s*(.*?);", re.DOTALL)


def normalize(net: str) -> str:
    return " ".join(net.split())


def audit_scan_text(text: str, expected_chains: int = 4,
                    max_imbalance: int = 1) -> dict:
    cells = {}
    q_owner = {}
    for cell_type, instance, body in CELL_RE.findall(text):
        ports = {name: normalize(net) for name, net in PORT_RE.findall(body)}
        missing = {"Q", "SCD", "SCE"} - ports.keys()
        if missing:
            raise ValueError(f"{instance}: missing scan ports {sorted(missing)}")
        if ports["SCE"] != "scan_enable_i":
            raise ValueError(f"{instance}: SCE is {ports['SCE']!r}")
        if ports["Q"] in q_owner:
            raise ValueError(f"multiple scan cells drive {ports['Q']!r}")
        cells[instance] = {"type": cell_type, **ports}
        q_owner[ports["Q"]] = instance

    if not cells:
        raise ValueError("no scan cells found")
    outputs = {name: normalize(net) for name, net in OUTPUT_RE.findall(text)}
    required_outputs = {f"scan_out_{index}" for index in range(expected_chains)}
    if set(outputs) != required_outputs:
        raise ValueError(f"scan outputs {sorted(outputs)}; expected {sorted(required_outputs)}")

    visited = set()
    chain_lengths = []
    for index in range(expected_chains):
        net = outputs[f"scan_out_{index}"]
        length = 0
        local = set()
        while net in q_owner:
            instance = q_owner[net]
            if instance in local:
                raise ValueError(f"scan chain {index} contains a cycle at {instance}")
            if instance in visited:
                raise ValueError(f"scan cell {instance} is shared between chains")
            local.add(instance)
            visited.add(instance)
            length += 1
            net = cells[instance]["SCD"]
        expected_input = f"scan_in_{index}"
        if net != expected_input:
            raise ValueError(f"scan chain {index} terminates at {net!r}, "
                             f"expected {expected_input!r}")
        chain_lengths.append(length)

    unvisited = set(cells) - visited
    if unvisited:
        sample = ", ".join(sorted(unvisited)[:5])
        raise ValueError(f"{len(unvisited)} scan cells are outside the chains: {sample}")
    imbalance = max(chain_lengths) - min(chain_lengths)
    if imbalance > max_imbalance:
        raise ValueError(f"unbalanced scan chains: {chain_lengths}")
    return {
        "schema": "simt-scan-audit-v1",
        "status": "passed",
        "scan_cells": len(cells),
        "scan_chains": expected_chains,
        "chain_lengths": chain_lengths,
        "max_chain_imbalance": imbalance,
        "imbalance_limit": max_imbalance,
        "all_cells_reachable": True,
        "balanced": True,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("netlist", type=Path)
    parser.add_argument("--chains", type=int, default=4)
    parser.add_argument("--max-imbalance", type=int, default=1,
                        help="maximum allowed longest-minus-shortest chain length")
    parser.add_argument("--report", type=Path,
                        default=Path("build/dft/scan_audit.json"))
    args = parser.parse_args()
    try:
        result = audit_scan_text(args.netlist.read_text(encoding="utf-8"),
                                 args.chains, args.max_imbalance)
    except (OSError, ValueError) as exc:
        print(f"FAIL scan-netlist audit: {exc}")
        return 1
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print("PASS scan-netlist audit: "
          f"cells={result['scan_cells']} chains={result['scan_chains']} "
          f"lengths={result['chain_lengths']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
