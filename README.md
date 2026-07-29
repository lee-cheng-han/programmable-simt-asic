# Programmable SIMT Compute Cluster ASIC

A tapeout-oriented, programmable four-warp/eight-lane SIMT throughput processor
implemented as a harnessed MPW digital macro. The project targets ASIC RTL,
design verification, DFT, physical design, and accelerator architecture. It does
not claim CUDA, OpenCL, graphics-API, or commercial-GPU compatibility.

The central engineering question is whether warp interleaving can hide execution
and banked-memory latency in a compact ASIC while retaining precise, independently
checkable architectural behavior.

## Current status

```text
Release stage:  Instruction-frontend and multi-warp model preparation
Completed:      Consolidated core; nested/four-warp SIMT reconvergence
Verified:       Python, C++, Verilator, architectural trace, and XSim components
In progress:    SRAM feasibility and buffered-fetch architecture
Next:           Physically realizable instruction frontend
Not started:    Memory system, DFT, physical implementation
```

The authoritative contract is [docs/architecture.md](docs/architecture.md).
[Measured warp-interleaving results](docs/performance_results.md) report the
checked-in one-warp versus four-warp arithmetic baseline.
Supporting documents explain individual topics but cannot override it.

## Frozen tapeout configuration

```text
1 cluster, 1 block, 4 warps, 8 threads/warp, 8 integer lanes
16 × 32-bit GPRs/thread, 4 predicates/thread
3-cycle fully pipelined multiplier
4 KiB eight-bank general scratchpad
2 KiB eight-bank shared memory
4 memory trackers, at most 1 per warp
3 completion sources, 2 queue entries per source
6-bit kernel epoch
16-bit per-warp instruction sequence number
25 MHz initial target, 50 MHz stretch target
Internal control bus plus Wishbone wrapper
Supported open PDK
Selected MPW harness and Wishbone attachment
```

## Verification-first flow

```text
Canonical ISA
  → Python assembler/disassembler
  → C++ architectural emulator
  → SystemVerilog RTL
  → instruction-level differential traces
  → assertions and bounded formal checks
  → functional coverage and reproducible random programs
  → deliberate bug injection
  → lint, CDC, and reset-domain closure
  → reproducible merge CI gate
  → scan and SRAM BIST
  → RTL-to-GDS physical implementation and signoff audit
```

Every release reports what is implemented, what was actually run, exact results,
warnings, limitations, and the next acceptance gate. Planned work is never
presented as completed evidence.

## Quick start

```sh
make test
make assemble PROGRAM=tb/programs/vector_add.s
build/simt-emulator build/vector_add.bin --memory tb/programs/vector_add.mem
make xsim-smoke
```

Requirements are Python 3.8+, a C++17 compiler, GNU Make, Verilator 5+, and
Vivado/XSim 2025.2 for the optional cross-simulator compile/elaboration check.
No package is installed automatically by repository scripts.

## Current repository components

```text
isa/                    Canonical 32-bit ISA definition
tools/                  Assembler, disassembler, ISA generators
model/                  C++17 architectural emulator and tests
rtl/frontend/           Instruction memory, fetch, decoder
rtl/register_file/      Replicated GPR file and predicate file
rtl/execute/            Integer lanes, vector ALU, preliminary writeback
tb/unit/                Self-checking component tests
tb/programs/            Directed assembly programs and memory images
docs/                   Normative architecture and verification contracts
scripts/                Reproducible regression entry points
```

## Scope boundaries

The baseline excludes external DDR, caches, virtual memory, coherence, floating
point, packed application-specific operations, graphics units, Linux drivers,
compiler backends, multiple clusters, multiple resident blocks, preemption,
out-of-order issue, and dual issue. After integer ASIC closure, the core plan
includes an optional eight-lane FP32 add/multiply pipeline with an independent
reference model and renewed completion-fabric verification. Multi-cluster
scheduling remains outside the planned extension.

Physical results will state the exact PDK, libraries, SRAM views, tool versions,
constraints, corners, switching activity, and limitations. Producing GDS with an
open flow is not described as fabrication or silicon validation. The ASIC release
targets a harnessed shuttle macro; a standalone pad ring, package, and board are
outside its scope.
