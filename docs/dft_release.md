# MPW wrapper and DFT release evidence

The shuttle-facing `simt_mpw_wrapper` preserves the frozen 32-bit Wishbone
contract, user clock/reset, done/fault interrupts, scan anchors, destructive
SRAM-BIST controls, and single-domain power boundary.
`make synth-mpw-mapped` separately proves that this complete boundary—not only
the inner compute core—maps with all 17 IHP SRAM instances retained. The mapped
wrapper contains 31,321 flip-flops, 189,435 standard-cell/macro instances, and
3,272,182.44 square micrometres of reported standard-cell area; SRAM macro area
is excluded by Yosys and must not be inferred from that number.

The wrapper has independent 25 MHz functional and 10 MHz scan-shift SDCs.
`make mpw-mapped-timing` confirms that the functional SDC binds real mapped
paths and records the pre-placement slow-corner diagnostic. Its current worst
setup slack is -300.686 ns because the area-oriented mapped netlist contains an
unbuffered 4,097-load control net. This is an explicit open physical-optimization
item, not timing closure; placed/routed STA is the acceptance evidence.

## SRAM BIST

Test mode rejects functional Wishbone traffic and transfers exclusive ownership
of the real general/shared bank engines to `sram_bist_controller`. The six-pass
destructive sequence writes and reads zero, one, and address-alternating
checkerboard data over all 1,024 general words and all 512 shared words. It
captures the first failing address and address space and requires software to
reload memory afterward.

The ASIC integration regression runs the normal 40-commit diagnostic, enters
test mode, tests both complete memories, and requires clean BIST completion.
The shuttle-wrapper regression independently checks Wishbone identity access,
done/fault interrupt propagation, clear/relaunch behavior, pre-insertion scan
bypass, test-mode bus suppression, and a complete clean SRAM-BIST pass.
The current run passes 17 wrapper checks and observes 32,257 BIST cycles, which
also guards against a false immediate-done result.

## Scan insertion and ATPG boundary

`make dft-release` runs OpenROAD DFT against the complete mapped MPW-wrapper
netlist and qualified SRAM views. OpenROAD replaces 31,321 sequential cells and
generates four stitched no-mix chains of 7,831, 7,831, 7,831, and 7,828 cells.
The three-cell maximum imbalance is an explicit release bound. A structural graph
audit follows every scan-data connection from each output to its matching input,
requires every inserted cell to be reachable exactly once, checks the common
scan enable, and rejects cycles, orphans, shared cells, or imbalanced chains.
The wrapper scan netlist, OpenDB database, log, audit, and JSON report are written
below `build/dft/`.

The same release command also regenerates and audits the 31,560-cell inner-core
scan netlist (four chains of 7,890 cells) consumed by the current balanced P&R
configuration. Keeping this implementation artifact alongside the canonical
wrapper scan result prevents a clean physical build from depending on stale
outputs. Physical signoff must ultimately move to the complete wrapper database;
the core-only P&R result is not accepted as shuttle-boundary closure.

The post-insertion scan SDC explicitly deselects functional `D` endpoints because
the IHP scan-flop Liberty view publishes unconditional timing checks on both `D`
and `SCD`. At 10 MHz, pre-placement scan-shift setup passes with +25.205 ns slack;
hold is -0.510 ns and remains open for placement/CTS hold repair. This is mode-
specific timing evidence, not a claim of routed scan timing closure.

This is genuine scan replacement and stitching, not the pre-insertion RTL bypass.
The current environment has no supported ATPG engine installed, so stuck-at
pattern generation and numerical stuck-at coverage are reported as `not-run`,
never inferred from scan-cell count. That external-tool gate remains open before
the project may claim ATPG coverage closure.

```sh
make asic-lint host-sram-integration
make mpw-wrapper-validation
make synth-mpw-mapped
make mpw-mapped-timing
make dft-release
make scan-audit
make mpw-scan-timing
```
