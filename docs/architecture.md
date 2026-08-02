# Programmable SIMT Compute Cluster ASIC — Authoritative Specification

This document is the normative architectural and implementation contract. If a
supporting document, comment, test, or current RTL implementation disagrees with
this file, this file takes precedence until the discrepancy is resolved and
verified. The design is a custom programmable SIMT throughput processor; it does
not claim CUDA, OpenCL, graphics-API, or commercial-GPU compatibility.

## Objective and release boundary

The tapeout-oriented, harnessed MPW digital macro answers one question quantitatively: can a
compact SIMT processor hide execution and on-chip memory latency through warp
interleaving while preserving precise, verifiable behavior and remaining
practical for ASIC implementation?

The fixed release configuration is implemented through RTL, differential and
formal verification, scan insertion, SRAM BIST, SRAM macro integration, complete
RTL-to-GDS implementation, and open-tool signoff. Results are reported with tool,
PDK, library, activity, and corner assumptions. The release includes the selected
shuttle harness integration and submission checks, but not a standalone pad ring,
package, or board. A GDS result is not a fabrication claim.

## Frozen configuration

| Item | Value |
|---|---:|
| Compute clusters | 1 |
| Resident blocks | 1 |
| Resident warps | 4 |
| Threads per warp | 8 |
| Physical integer lanes | 8 |
| Warp issue width | 1 instruction/cycle |
| General registers/thread | 16 × 32 bits |
| Predicate registers/thread | 4 × 1 bit |
| Instruction width | 32 bits |
| Multiplier latency / initiation interval | 3 / 1 cycles |
| SIMT-stack depth | 8 |
| General-data scratchpad | 4 KiB, 8 banks |
| Shared memory | 2 KiB, 8 banks |
| Outstanding memory operations | 4 system-wide, 1/warp |
| Completion sources | ALU, multiplier, memory |
| Completion queue depth | 2/source |
| Kernel epoch width | 6 bits |
| Instruction sequence width | 16 bits |
| Functional clocks | 1 |
| Initial / stretch frequency | 25 / 50 MHz |
| Host interface | Internal bus plus Wishbone wrapper |
| Process target | Supported open PDK |

Parameters may support verification, but the tapeout release uses this one
configuration. External DDR, caches, virtual memory, multiple clusters, multiple
resident blocks, floating point, dual issue, and out-of-order warp issue are not
part of the baseline.

The architecture reserves unused opcode values and completion class `2'b11` for
a post-baseline FP32 execution extension. That extension is limited initially to
eight-lane FP32 add and multiply using existing 32-bit GPR storage. It must freeze
rounding, special-value, subnormal, and exception-status behavior before changing
the ISA or RTL. No baseline block may depend on the extension being present.

## Architectural state and execution order

Each warp shares a PC, decoded instruction, active mask, GPR and predicate
scoreboards, SIMT stack, barrier state, block ID, architectural instruction
sequence counter, and six-bit kernel epoch. The sequence counter is 16 bits and
increments on accepted issue. Completion matching always includes epoch, warp ID,
and sequence number. Wrap is safe because the bounded per-warp in-flight capacity
is far smaller than 2^16 and reuse is forbidden while an older matching operation
is live. Each of its eight threads owns sixteen
GPR values, four predicate values, and lane-specific operands/results.

Instructions issue in program order within a warp. Different warps interleave.
There is no reorder buffer. Writeback is the architectural commit boundary.
Execution completion, queue insertion, and memory response do not make a result
architecturally visible.

Every pipeline and delayed-operation record carries valid, epoch, warp ID,
instruction sequence, PC, instruction word, masks, destination metadata, and
operation-level status metadata. Fatal faults never travel through these records
or wait for completion arbitration. Valid payloads remain stable under backpressure. Reset, host
clear, fatal fault, and stale-epoch rejection are explicit cancellation causes.

## Instruction frontend

The core uses one shared instruction-memory read port rather than one read port
per warp. Round-robin fetch arbitration selects an active warp whose instruction
buffer is empty and which has no response in flight. Each warp owns one buffered
record containing its architectural PC and instruction word. Only a valid record
whose PC still matches the warp PC may become scheduler-eligible.

The behavioral storage implements the timing contract expected of a synchronous
single-port SRAM: one request is accepted per cycle and its tagged response fills
the selected warp buffer after the memory read. Issue consumes exactly one
buffered record. A PC change makes any older response stale; stale responses are
discarded by comparing both warp ID and PC. Clear and fatal fault invalidate all
buffered and in-flight frontend work. Program writes are accepted only while the
core is idle.

## ISA and predication

`isa/isa.json` is the single machine-readable ISA source for Python tools,
generated C++ and SystemVerilog definitions, the emulator, decoder, documentation,
and test generation. Base operations are the existing integer, comparison,
movement, general/shared memory, branch, synchronization, and exit instructions.
Reserved, illegal, and noncanonical encodings fault before side effects.

Ordinary predication computes `active_mask & predicate_mask`, or
`active_mask & ~predicate_mask` when inverted. Inactive work cannot write state,
store memory, affect control flow, or raise lane-local faults. `SEL` uses its
predicate as a data selector and writes every active lane.

## Warp eligibility and scheduler fairness

A warp is eligible only when valid, unfinished, unfaulted, unblocked by barrier,
memory, serialization, execution, or backpressure, and when all GPR/predicate
sources and destinations are available. The scheduler is round-robin and advances
only after accepted issue. Selection remains stable while downstream is stalled.

Under continuous eligibility, continuing accepted issue opportunities, and no
reset/clear/halt, each of four warps must issue within four accepted grants.
Backpressured cycles do not count. Bounded formal properties, randomized fairness
stress, issue counts, and maximum/average eligible wait provide evidence.

## GPR and predicate dependencies

Each warp has a 16-bit pending-GPR bitmap. Accepted issue checks all source bits
and the destination bit. A pending destination blocks issue, preventing WAW as
well as RAW hazards. A destination bit is set only on accepted issue and cleared
only on matching accepted commit.

Each warp also has a four-bit pending-predicate bitmap. Predicate producers set a
bit at accepted issue. Predicate readers and writers stall on a pending bit.
Predicate consumers include predicated operations, branches, memory operations,
and `SEL`.

There is no predicate forwarding. Even a single-cycle comparison becomes visible
only at architectural predicate commit. GPR writeback forwarding remains required
for the replicated vector register file.

Scoreboard clear matches epoch, warp ID, instruction sequence, and destination.
It never occurs at execution finish, queue insertion, response arrival, selection
of a stalled commit, stale completion, or unrelated commit.

## Register files

The GPR file has eight lane banks. Each bank contains 4 warps × 16 registers ×
32 bits and two replicas for two vector reads. Every accepted masked write updates
both replicas. Same-cycle GPR forwarding compares valid, warp, register, and lane
mask. Replica consistency is asserted. The baseline uses standard cells; a
time-multiplexed or SRAM-backed replacement requires physical evidence and full
re-verification.

The predicate file stores 4 warps × 4 predicates × 8 lane bits in resettable
flip-flops. Writes are lane masked. Reads return committed state only.

## Execution and multiplier

Eight integer lanes implement 32-bit arithmetic, Boolean operations, low-five-bit
shifts, signed comparisons/min/max, low-32-bit multiply, movement, predicate
selection, address generation, and store-data generation. Memory instructions do
not modify memory in the execution unit.

The tapeout multiplier is an eight-lane three-stage pipeline with initiation
interval one. Back-to-back vector multiplies may enter on consecutive cycles.
Every stage carries epoch, warp, sequence, PC, destination, and lane mask. If the
two-entry multiplier completion queue cannot accept the final result, all stages
stall consistently and input acceptance stops before overflow.

## Completion fabric and queue-depth proof

There are three completion classes: integer/predicate ALU, multiplier, and memory.
Each feeds a two-entry elastic queue. A completion record carries all architectural
tags, GPR/predicate destinations and masks, eight results, scoreboard-clear
metadata, completion class, and operation-level nonfatal status. Fatal-fault
capture is a separate, higher-priority path and is never queued here.

Each producer emits at most one completion per cycle and responds to backpressure
within one cycle. One entry holds ordinary buffered data; the second captures the
one result already committed to emerge after availability is removed. Backpressure
then prevents a third arrival. A one-entry queue would require a combinational
stop path; a third is unnecessary under this frozen contract. Any higher producer
rate, longer response latency, or non-backpressurable source requires a new proof.

Assertions cover occupancy, overwrite prevention, source rate, response latency,
payload stability, and exactly-once commit or explicit cancellation.

Completion class `2'b11` remains reserved during the baseline for the planned
FP32 pipeline. Enabling it creates a four-source arbiter and requires a new
fairness bound, collision test, queue-depth proof, and completion conservation
evidence.

## Shared writeback arbitration

One round-robin arbiter selects the ALU, multiplier, or memory queue. At most one
completion commits per cycle, and arbitration advances only after accepted
commit. A continuously nonempty queue receives service within three accepted
writeback opportunities when writeback continues accepting.

Faulting completions suppress ordinary writes. Empty masks do not write. A stale
epoch cannot write registers, predicates, clear scoreboards, modify memory, or
complete a new kernel. A directed three-source collision and a dropped-completion
mutation are mandatory verification cases.

## Kernel epoch and quiescence

All delayed operations carry a six-bit kernel epoch. Six bits provide diagnostic
and implementation margin; safe epoch reuse is guaranteed by cancellation and
full quiescence, never by a bounded-latency assumption. Commit requires equality
with the current epoch. Host clear advances the epoch and invalidates warp,
pipeline, queue, scoreboard, tracker, barrier, and stack state while preserving
SRAM contents.

A launch is accepted only when `CORE_QUIESCENT` is true: no warp contexts,
pipeline or multiplier entries, memory trackers, completion queues, pending
writeback, active barrier, or BIST transition. Epoch wrap is safe only because
quiescence guarantees no older matching operation can return.

The internal launch shape supplies one common entry PC and a resident-warp count
from one through four. Every launched warp begins at that PC with all eight
lanes active, zeroed sequence state, and its architectural warp ID available
through `S2R WID`. Invalid warp counts are not accepted. The host register layer
may add richer grid metadata later without changing this core launch contract.

## Fatal faults and cancellation

A fatal fault uses a dedicated sticky capture path and does not compete for or
wait behind writeback. Its assertion immediately blocks new issue and normal
commit, invalidates queues, flushes or discards
execution, cancels memory trackers, suppresses subsequent state/memory effects,
and freezes diagnostic state until clear/reset.

The governing completion property is: every accepted completion eventually
commits exactly once or is explicitly cancelled by reset, host clear, fatal fault,
or stale-epoch rejection.

## Same-cycle event priority

State transitions use this strict global priority, from highest to lowest:

1. Reset.
2. Accepted host clear.
3. Fatal-fault capture.
4. Accepted normal architectural completion, including writeback and kernel done.
5. Ordinary pipeline, scheduler, tracker, barrier, and SRAM-response progress.

Reset discards concurrent SRAM responses and causes no SRAM write. Host clear
advances the epoch, clears sticky runtime status, and cancels concurrent kernel
completion, faults, responses, and ordinary progress while preserving SRAM
contents. A fatal fault suppresses normal writeback in its assertion cycle even
when that writeback was selected and otherwise ready; the interface must not
report an accepted commit. It also suppresses stores not completed in an earlier
cycle. A barrier fault therefore cancels an outstanding store.

When fatal sources assert together, the primary cause uses this fixed subpriority:
host/interface, instruction fetch/decode, SIMT-stack or barrier/control, then
memory. A simultaneous-cause bitmap records every asserted fatal class so lower-
priority information is not lost. An illegal instruction is therefore primary
over a simultaneous memory fault. Fatal sources never wait for a completion queue
or writeback arbitration.

## Divergence

Predicated branches form taken and not-taken masks from the active mask. Divergent
execution uses the existing `SSY`/`BRA`/`SYNC` protocol. Each depth-8 stack entry
stores reconvergence PC, deferred PC/mask, union mask, and state. Overflow and
underflow never wrap or overwrite state; they suppress side effects, capture PC,
warp, mask, and depth, and abort the kernel.

Frontend redirects flush only unissued work. Because wrong-path instructions are
never speculatively issued, redirects do not invalidate completion queues.

## On-chip memories

The 4 KiB general scratchpad is 8 banks × 128 words × 32 bits. The 2 KiB shared
memory is 8 banks × 64 words × 32 bits. Both use:

```text
word_address = byte_address >> 2
bank_index   = word_address[2:0]
bank_row     = word_address >> 3
```

Controllers collect lane requests, serve one distinct request per bank/cycle,
broadcast identical-address loads, replay conflicts, preserve lane mapping, and
finish only after every participating lane completes.

There are four system-wide memory trackers and at most one per warp. Each holds
epoch, warp, sequence, PC, space/type, destination, participation/pending/
completed masks, per-lane address/data/enables/results, fault, and completion
state. A fifth operation or second operation from one warp backpressures safely.
A round-robin response collector emits at most one completed tracker per cycle to
the two-entry memory completion queue.

## Store order and visibility

Within one warp instruction, active stores are serviced in ascending lane order.
Same-bank stores replay in that order. Same-address stores are all applied, so
the highest participating lane produces the final value. Traces and the emulator
must compare service order, not merely final contents.

Memory operations serialize their warp. A younger same-warp load waits until an
older store has completed all lanes/replays and committed its memory completion;
it therefore observes the final highest-lane value. Cross-warp races are unordered
without synchronization. A completed barrier orders both shared and general
scratchpad accesses for the resident block.

All active addresses of a vector memory instruction are validated before any bank
request is issued. A fault in any active lane makes the instruction atomic: loads
commit no destination and stores perform no lane write. Inactive lanes are not
validated. Core loads and stores are little-endian, four-byte-aligned, full-word
operations; misaligned accesses are fatal rather than split. Scratchpad word
addresses range from `0x000` through `0xffc`, and shared-memory word addresses
range from `0x000` through `0x7fc`.

## Barriers

One block contains up to four warps. `BAR` records arrival and blocks the warp.
Release occurs only after all required warps arrive and their earlier serializing
memory operations complete. Predicated or divergent barriers are fatal errors. A
simulation watchdog detects missing-warp deadlock.

## SRAM reset, clear, programming, and BIST

Instruction, scratchpad, and shared SRAM contents are undefined after reset.
Reset and host clear produce no SRAM writes; host clear preserves contents.
Software initializes all read locations. BIST is destructive and has exclusive
ownership. After BIST, launch remains blocked until required memories are reloaded.

Instruction-memory programming while running is `IMEM_WRITE_WHILE_BUSY`: suppress
the write, complete the bus transaction deterministically, assert bus error where
supported, capture sticky fault, halt at the documented boundary, and require
clear/reset. Repeated illegal writes cannot destabilize the fault record.

## Host interface

The core exposes an internal bus and a Wishbone wrapper. Registers cover control,
status, launch shape, argument base, counters, fault record, build ID, scratch,
quiescence, and epoch. Host windows expose instruction SRAM, general scratchpad,
optional debug state, and BIST. Start-while-busy/not-quiescent/faulted, invalid PC,
memory ownership conflict, and unsupported launch shape have deterministic errors.

The host-visible debug interface is a small captured snapshot, not an
asynchronous full-register-file mux. On a host snapshot request or fatal fault it
captures each warp's PC, active mask, GPR/predicate pending masks, SIMT-stack
depth and top entry, the four tracker valid/warp/state summaries, all three
completion-queue occupancies, current epoch, quiescence, and fault state. The
baseline does not expose the entire GPR file through a debug mux.

## Kernel completion and lane exit

`KERNEL_DONE` asserts only when every launched warp has finished through
lane-level `EXIT`, no valid frontend or execution-pipeline entry remains, the
multiplier is empty, all memory trackers and completion queues are empty, no
architectural writeback is pending, no barrier is active, and no fatal fault is
set. It cannot assert when the final warp merely decodes or executes `EXIT`. A
faulted kernel reports `KERNEL_FAULTED`, not `KERNEL_DONE`.

`EXIT` removes only its effective predicated exit mask:
`active_mask = active_mask & ~exit_mask`. Deferred divergent paths remain live in
the SIMT stack. A warp finishes only after its active mask is zero and no deferred
path remains.

## Performance evidence

Required counters include cycles, issue/commit, active lanes, eligibility and
stall classes, multiplier activity, replay cycles, divergence/stack depth, memory
requests, completion occupancy, arbitration waits, faults, and cancellations.

Cycle, accepted-issue, and architectural-commit counters are unsigned 64-bit
wrapping counters. Diagnostic event counters are unsigned 32-bit saturating
counters so overflow cannot appear as a small event count. Saturation sets a
sticky aggregate `COUNTER_SATURATED` status bit, and per-counter saturation is
visible in the debug snapshot. Counter behavior never raises a kernel fault.

Studies compare one versus four warps, memory patterns, and divergence patterns.
They report cycles, IPC, lane utilization, idle/stall cycles, multiplier initiation,
completion collisions, serviced lanes/cycle, replay, bandwidth, branch efficiency,
and reconvergence overhead with reproducible workloads and seeds.

## Verification contract

Every feature maps to documentation, directed tests, assertions, numerical
coverage, differential checking, and bounded formal properties where suitable.
Emulator and RTL traces include sequence, cycle, epoch, warp, PC, instruction,
masks, destinations/data, memory request/response/service order, stack/barrier,
completion/cancellation, and fault events. The comparator reports the first
architectural mismatch.

Bug injection covers hazards, forwarding/replicas, queues/arbitration, multiplier
tags, stack, memory lane mapping/replay/order, barriers, stale epochs, instruction
programming, and byte enables. Each mutation records the first detector, latency,
committed corruption, fix, and regression result.

## DFT and physical signoff

Before architecture freeze, actual SRAM macros must be qualified for supported
depths and widths, logical banking, functional/timing/physical view availability,
power connectivity, BIST feasibility, preliminary placement, and boundary timing.
The final architecture cannot depend only on generic inferred-memory assumptions.

RTL static signoff includes lint, CDC, reset-domain crossing analysis, reset
deassertion checks, and functional/host/scan/BIST clock interactions. Every
exception is reviewed and documented before synthesis freeze.

The functionally closed baseline uses no manual architectural clock gating.
Tool-inserted or coarse-grained integrated clock-gating cells may be evaluated
only after the ungated implementation passes functional verification and initial
signoff. Every enable condition requires equivalence, assertion, and power-aware
simulation evidence; STA covers all gating checks, and scan/test modes force gated
clocks active.

After architectural verification closure, scan replacement/stitching, shift and
capture simulation, supported ATPG reporting, and destructive SRAM BIST are added.
BIST reports failing memory/address and expected/observed data and exercises zero,
one, ascending, descending, and both transition directions.

The physical flow includes the chosen MPW harness and submission checks, SRAM
views, synthesis, floorplan/macro placement, PDN,
placement, CTS, routing, extraction, optimization, antenna repair, fill, and
re-extraction. Mode-specific SDC covers functional, host programming, scan shift/
capture, and BIST with no unconstrained endpoints. STA runs after synthesis,
placement, CTS, route, ECO, and fill across supported PVT corners.

Each violation is tracked through root-cause analysis, RTL or physical ECO,
incremental implementation, extraction, STA, equivalence, DRC/LVS, and affected
regressions. Final fill is followed by re-extraction, setup/hold STA, DRC, LVS,
antenna, density, power review, and netlist-consistency checks against the filled
GDS used for release.

Final evidence includes timing, activity-based and vectorless power, IR/EM where
supported, DRC, LVS, antenna, density/connectivity, equivalence, gate-level and
SDF simulation, scan and BIST validation, release checksums, frozen tools/PDK/SRAM
versions, archived reports, and a silicon test plan. Open-tool limitations and
waivers are explicit; unsupported signoff claims are prohibited.
