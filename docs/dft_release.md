# MPW wrapper and DFT release evidence

The shuttle-facing `simt_mpw_wrapper` preserves the frozen 32-bit Wishbone
contract, user clock/reset, done/fault interrupts, scan anchors, destructive
SRAM-BIST controls, and single-domain power boundary.

## SRAM BIST

Test mode rejects functional Wishbone traffic and transfers exclusive ownership
of the real general/shared bank engines to `sram_bist_controller`. The six-pass
destructive sequence writes and reads zero, one, and address-alternating
checkerboard data over all 1,024 general words and all 512 shared words. It
captures the first failing address and address space and requires software to
reload memory afterward.

The ASIC integration regression runs the normal 40-commit diagnostic, enters
test mode, tests both complete memories, and requires clean BIST completion.

## Scan insertion and ATPG boundary

`make dft-release` runs OpenROAD DFT against the mapped IHP SG13G2 netlist and
qualified SRAM views. OpenROAD replaces 31,277 sequential cells and generates
four stitched no-mix chains. The scan netlist, OpenDB database, log, and JSON
report are written below `build/dft/`.

This is genuine scan replacement and stitching, not the pre-insertion RTL bypass.
The current environment has no supported ATPG engine installed, so stuck-at
pattern generation and numerical stuck-at coverage are reported as `not-run`,
never inferred from scan-cell count. That external-tool gate remains open before
the project may claim ATPG coverage closure.

```sh
make asic-lint host-sram-integration
make dft-release
```
