#!/usr/bin/env python3
"""Minimal transport-independent runtime for the SIMT ASIC host register map."""
from __future__ import annotations

import argparse
import json
import pathlib
import struct
from dataclasses import dataclass
from typing import Protocol


class Transport(Protocol):
    def read32(self, address: int) -> int: ...
    def write32(self, address: int, value: int) -> None: ...


CONTROL, STATUS, LAUNCH_PC, WARP_COUNT = 0x00, 0x04, 0x08, 0x0C
IMEM_ADDR, IMEM_DATA, FAULT_CODE, FAULT_PC = 0x10, 0x14, 0x18, 0x1C
CYCLE_LO, CYCLE_HI, ISSUE_LO, ISSUE_HI = 0x20, 0x24, 0x28, 0x2C
COMMIT_LO, COMMIT_HI, BUILD_ID, MACHINE = 0x30, 0x34, 0x3C, 0x40
MEM_ADDR, MEM_WDATA, MEM_COMMAND, MEM_RDATA = 0x84, 0x88, 0x8C, 0x90
DIAGNOSTIC_BASE, COUNTER_STATUS = 0xC0, 0xE0

DIAGNOSTIC_NAMES = (
    "empty_eligibility_cycles", "dependency_stall_cycles",
    "execution_backpressure_cycles", "memory_active_cycles",
    "completion_stall_cycles", "barrier_wait_cycles",
    "divergent_branches", "fatal_fault_events",
)


@dataclass(frozen=True)
class Result:
    status: int
    fault_code: int
    fault_pc: int
    cycles: int
    issues: int
    commits: int
    diagnostics: dict[str, int]
    counter_saturated: bool


class SimtRuntime:
    def __init__(self, transport: Transport):
        self.bus = transport

    def identity(self) -> dict[str, int]:
        return {"build_id": self.bus.read32(BUILD_ID),
                "machine": self.bus.read32(MACHINE)}

    def clear(self) -> None:
        self.bus.write32(CONTROL, 1 << 1)

    def load_program(self, words: list[int]) -> None:
        for address, word in enumerate(words):
            self.bus.write32(IMEM_ADDR, address)
            self.bus.write32(IMEM_DATA, word)

    def memory_write(self, address: int, value: int, shared: bool = False) -> None:
        self.bus.write32(MEM_ADDR, address)
        self.bus.write32(MEM_WDATA, value)
        self.bus.write32(MEM_COMMAND, 1 | (1 << 1) | (int(shared) << 2))
        self._wait_memory()

    def memory_read(self, address: int, shared: bool = False) -> int:
        self.bus.write32(MEM_ADDR, address)
        self.bus.write32(MEM_COMMAND, 1 | (int(shared) << 2))
        self._wait_memory()
        return self.bus.read32(MEM_RDATA)

    def _wait_memory(self, polls: int = 10000) -> None:
        for _ in range(polls):
            status = self.bus.read32(STATUS)
            if not (status & (1 << 3)):
                if status & (1 << 4):
                    raise RuntimeError("SRAM maintenance operation faulted")
                return
        raise TimeoutError("SRAM maintenance operation did not complete")

    def launch(self, pc: int = 0, warps: int = 4) -> None:
        if not 1 <= warps <= 4:
            raise ValueError("resident warp count must be in [1, 4]")
        self.bus.write32(LAUNCH_PC, pc)
        self.bus.write32(WARP_COUNT, warps)
        self.bus.write32(CONTROL, 1)

    def wait(self, polls: int = 1_000_000) -> Result:
        for _ in range(polls):
            status = self.bus.read32(STATUS)
            if status & 0x6:
                return self.result(status)
        raise TimeoutError("kernel did not complete")

    def _read64(self, low: int, high: int) -> int:
        # Counters stop at done/fault; high-low-high avoids torn live reads.
        while True:
            hi0 = self.bus.read32(high)
            lo = self.bus.read32(low)
            hi1 = self.bus.read32(high)
            if hi0 == hi1:
                return (hi0 << 32) | lo

    def result(self, status: int | None = None) -> Result:
        status = self.bus.read32(STATUS) if status is None else status
        diagnostics = {name: self.bus.read32(DIAGNOSTIC_BASE + 4 * index)
                       for index, name in enumerate(DIAGNOSTIC_NAMES)}
        return Result(status, self.bus.read32(FAULT_CODE), self.bus.read32(FAULT_PC),
                      self._read64(CYCLE_LO, CYCLE_HI),
                      self._read64(ISSUE_LO, ISSUE_HI),
                      self._read64(COMMIT_LO, COMMIT_HI), diagnostics,
                      bool(self.bus.read32(COUNTER_STATUS) & 1))


class PlanTransport:
    """Records bus operations for board/harness transport implementation."""
    def __init__(self): self.operations: list[dict[str, int | str]] = []
    def read32(self, address: int) -> int:
        self.operations.append({"operation": "read32", "address": address})
        return 0
    def write32(self, address: int, value: int) -> None:
        self.operations.append({"operation": "write32", "address": address,
                                "value": value & 0xFFFF_FFFF})


def read_program(path: pathlib.Path) -> list[int]:
    data = path.read_bytes()
    if len(data) % 4: raise ValueError("program length is not a multiple of four")
    return list(struct.unpack(f"<{len(data)//4}I", data))


def main() -> None:
    parser = argparse.ArgumentParser(description="emit a host transaction plan")
    parser.add_argument("program", type=pathlib.Path)
    parser.add_argument("--warps", type=int, default=4)
    parser.add_argument("--launch-pc", type=lambda x: int(x, 0), default=0)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    transport = PlanTransport(); runtime = SimtRuntime(transport)
    runtime.clear(); runtime.load_program(read_program(args.program))
    runtime.launch(args.launch_pc, args.warps)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({"schema": "simt-host-plan-v1",
        "program": str(args.program), "operations": transport.operations}, indent=2)+"\n")


if __name__ == "__main__": main()
