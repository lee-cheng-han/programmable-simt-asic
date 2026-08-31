# ASIC interface and mode contract

The ASIC-facing integration boundary is `rtl/asic/simt_asic_top.sv`. It freezes a
single positive-edge core clock, asynchronous active-low external reset with
two-stage synchronous release, a 32-bit Wishbone control plane, explicit test
ownership, and scan stitch anchors. The baseline contains one always-on power
domain and no architectural clock gating.

## Host register map

| Byte address | Access | Meaning |
|---:|:---:|---|
| `0x00` | W | Control: bit 0 launch, bit 1 clear; write-one pulses |
| `0x04` | R | Status: running, done, fault |
| `0x08` | R/W | Launch PC |
| `0x0c` | R/W | Resident warp count |
| `0x10` | R/W | Instruction-memory word address |
| `0x14` | R/W | Instruction-memory data; a write emits one programming request |
| `0x18` | R | Sticky fault code |
| `0x1c` | R | Sticky fault PC |
| `0x20`–`0x34` | R | Cycle, issue, and commit counters, low word then high word |
| `0x38` | R/W | Barrier watchdog enable and limit |
| `0x3c` | R | Build ID (`SIMT`) |
| `0x40` | R | Quiescence and epoch |
| `0x44` | R | Bring-up breadcrumbs |
| `0x48`–`0x80` | R/W, R | Snapshot trigger and bounded warp/pipeline snapshot |
| `0x84`–`0x90` | R/W | Quiescent general/shared SRAM maintenance port |
| `0x94` | R/W | Verification-only injection mask; disabled in production |
| `0xa0`–`0xbc` | R | Captured SIMT-stack tops and tracker summaries |
| `0xc0`–`0xdc` | R | Eight 32-bit saturating diagnostic counters |
| `0xe0` | R | Sticky aggregate counter-saturation status |

Transactions are single-cycle classic Wishbone completions. Misaligned or
unmapped addresses terminate with `err` and without `ack`. Byte selects apply to
writable payload registers. A launch request remains asserted until accepted;
clear and program writes are one-cycle pulses. Test mode owns the block, holds
the functional core in reset, rejects host transactions, and suppresses all host
control pulses.

## Reset, scan, timing, and power

External reset asserts asynchronously and releases only after two rising clock
edges. Functional constraints hold test and scan enables inactive. Scan-shift
constraints claim the same ungated clock at a conservative shift period and
hold both test controls active. `scan_in_i` and `scan_out_o` are preserved
pre-insertion stitch anchors; actual scan replacement, chain balancing, ATPG,
and shift/capture GLS are DFT-release evidence and are not claimed by this RTL
freeze.

`physical/simt_asic.upf` declares one always-on domain with explicit VDD/VSS and
no isolation, retention, or level shifting. SRAM supply-pin mapping remains a
physical-library integration responsibility.

## Reproduction

```sh
make asic-contract asic-lint
make rtl-test
```

The contract checker enforces the top-level mode ports, host map, functional and
scan SDCs, and UPF presence. Directed tests cover byte writes, programming,
launch backpressure, clear pulses, counter/status reads, invalid transactions,
test ownership, and asynchronous-assert/synchronous-release reset behavior.
The completed integration evidence is recorded in
`docs/host_sram_integration.md`.
