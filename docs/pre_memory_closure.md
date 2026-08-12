# Pre-memory closure report

The processor front end, integer execution machine, SIMT control flow, completion
fabric, lifecycle behavior, and independent reference model are closed as the
stable foundation for memory-system integration.

## Release evidence

| Gate | Result |
|---|---|
| Python ISA/tool tests | Pass |
| C++ emulator tests | Pass |
| Verilator unit and integration suite | Pass |
| XSim UVM differential regression | 21/21 pass: seven classes, seeds 1–3 |
| Architectural trace comparison | 21/21 model matched |
| Portable architectural coverage | 43/43 approved bins, 100% |
| Formal | Two 12-cycle inductive arbiter proofs and one exhaustive writeback proof pass |
| Mutation testing | 9/9 detected, zero survivors, zero invalid mutants |
| Generic synthesis elaboration | Pass with zero design-check errors |
| IHP mapped synthesis | Pass; 142,699 cells including one instruction SRAM macro |
| Integrated placement trial | 142,698 movable cells and 17 macros legally placed |

The approved coverage model contains all 26 implemented pre-memory opcodes, all
four warp IDs, one through four resident warps, both completion sources, full,
split, and sparse mask classes, and observed/no-observed execution and writeback
stall states. Memory opcodes and barrier behavior are excluded because their RTL
is the next implementation boundary, rather than treated as unreachable bins.

The formal writeback proof exhaustively checks fatal suppression, stale-epoch
cancellation, commit-ready behavior, and architectural side-effect gating. The
inductive arbitration proofs check requested one-hot grants, stable stalled
grants, and bounded accepted-grant wait for the four-warp scheduler and the
three-input completion arbiter configuration.

The mutation suite injects scheduler-priority, scoreboard epoch, FIFO order,
FIFO capacity, multiplier datapath, stale writeback, divergent mask, early-done,
and stack-overflow defects into temporary copies. Every defect is detected by
its owning focused test; canonical RTL is never modified by the experiment.

## Reproduction

```sh
make test
make uvm-regression UVM_SEEDS="1 2 3"
make coverage-report
make formal
make mutation-smoke
make synth-elab
make sram-check
make synth-mapped
make integrated-floorplan
```

XSim jobs run sequentially because concurrent elaborations share simulator
runtime state. Native XSim coverage is optional; the release uses portable
manifests because the installed BASIC license cannot merge native databases with
`xcrg`.

## Next boundary

This report does not claim a memory subsystem, DFT closure, routed timing,
clock-tree synthesis, power-grid closure, DRC/LVS, or silicon results. Those are
subsequent deliverables and do not invalidate the closed processor foundation.
