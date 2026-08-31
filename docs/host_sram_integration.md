# Host and SRAM integration release

This release closes the ASIC host-control and SRAM-maintenance boundary. The
32-bit Wishbone port programs instruction memory, launches and clears kernels,
reports status/faults/counters, controls the barrier watchdog, captures bounded
debug snapshots, and performs explicitly quiescent scalar maintenance accesses
to the general and shared SRAM banks.

## Ownership and memory lifetime

The host maintenance path arbitrates through the real bank engines. It is not a
hierarchical simulation backdoor. A command is accepted only when the core is
quiescent, all memory trackers are free, neither bank engine is active, and the
selected maintenance port is ready. Active-kernel commands and overlapping host
commands terminate with Wishbone error. Alignment and range faults are returned
in maintenance status without partially modifying memory.

Instruction, general, and shared SRAM contents are unspecified after reset.
Software initializes every location it consumes. Launch does not clear memory;
host clear and fatal fault preserve memory for diagnosis. The later destructive
BIST flow owns the SRAM ports exclusively and requires software reload afterward.

## Debug and bring-up

A synchronous snapshot request, or the first fatal fault, captures four warp
PCs, active masks, scoreboard masks, SIMT-stack depth/top, resident/barrier/memory
state, four tracker summaries, completion occupancies, epoch, quiescence, and
fault state. No full-register-file debug mux exists. Sticky breadcrumbs record
reset observed, clock active, launch accepted, first issue, first commit, and the
future SRAM-BIST completion input.

The production manifest disables all injection controls. A verification build
may enable five synthesizably removable hooks: SRAM-read corruption, completion-
tag corruption, tracker timeout, illegal instruction, and suppressed barrier
arrival. `config/asic_build_manifest.json` records their build disposition.

## Evidence and reproduction

`tb/programs/asic_diagnostic.s` independently exercises integer ALU operations,
structured divergence/reconvergence, general memory, shared memory, a full-warp
barrier, and exit. The ASIC-top integration test drives only Wishbone and pins:
it initializes and reads both SRAM spaces, programs a diagnostic kernel, launches
four warps, waits for drained completion, and reads counters, breadcrumbs, and a
snapshot. It passes 114 bus/integration checks with 40 architectural commits.
The standalone host-controller regression additionally passes 40 directed checks,
and the bank/memory-subsystem maintenance regressions pass 9 and 10 checks.

```sh
make host-sram-release
```

The release gate includes the pre-DFT static-signoff gate, build-contract check,
diagnostic assembly, strict lint, RTL-to-synthesis integration equivalence, and
the end-to-end host/SRAM simulation.

## Runtime and performance visibility

The host map exposes eight saturating diagnostic counters at `0xc0` through
`0xdc`: empty eligibility, dependency stall, execution backpressure, memory
active, completion stall, barrier wait, divergent branches, and fatal events.
`0xe0[0]` is sticky when any diagnostic counter saturates. Cycle, issue, and
commit counts remain 64-bit wrapping architectural counters.

`tools/host/runtime.py` is the transport-independent host runtime. It implements
program loading, explicit SRAM initialization/readback, launch, polling, fault
inspection, coherent 64-bit counter reads, and diagnostic capture. Its CLI emits
a versioned JSON Wishbone transaction plan so an MPW or FPGA transport can be
added without changing launch semantics:

```sh
make host-plan PROGRAM=tb/programs/asic_diagnostic.s
```
