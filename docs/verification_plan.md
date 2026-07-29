# Verification plan

The software-tool release uses Python unit tests for encoding, round trips, diagnostics, and
the generated ISA binding, plus black-box C++ emulator tests for arithmetic,
predication, uniform and divergent branches, aligned memory, vector-add
semantics, exit, illegal instructions, and SIMT-stack overflow/underflow.
Seeds must be printed for randomized tests. `make test` is the
single regression entry point.

`docs/requirements_traceability.md` is the closure index. Each normative
requirement must name its RTL owner, directed test, assertion or formal property,
coverage point, and status. A blank field is an explicit verification gap, not an
implicit waiver.

Later modules require self-checking unit tests and assertions before integration.
The closure matrix covers every opcode/register/predicate/lane/warp; RAW and
multi-cycle completion; active-mask categories and nested divergence; shared and
scratchpad conflict degree/broadcast; memory-tracker occupancy; scheduler-ready
counts; Wishbone backpressure; completion collisions; barrier order; and every
fault. Crosses are opcode×mask,
opcode×dependency, scheduler×ready count, memory×coalescing, branch×divergence,
and shared operation×conflict. RTL traces will be compared at first mismatch with
the emulator's PC, instruction, masks, writes, memory, stack, and fault events.

The decoder unit test exercises every allocated opcode, signed
immediate extraction, all output metadata classes, a reserved opcode, and a
representative violation of each canonical-field rule. It runs as a compiled
SystemVerilog simulation through `make rtl-test`; XSim separately compiles and
elaborates the same decoder and testbench through `make xsim-smoke`.

The replicated vector-register-file test initializes and reads all 64 logical
warp/register addresses across all eight lane banks. It checks two independent
read addresses, complementary partial masks, inactive-lane preservation,
same-cycle forwarding on both ports, forwarding rejection for a different warp,
invalid-read behavior, and the per-lane replica-write assertions.

The predicate-register-file test covers all 16 warp/predicate addresses, all
eight lane bits, full and complementary partial masks, absence of forwarding,
concurrent-write isolation, invalid reads, reset recovery, masked-write assertions,
and unmasked-lane preservation assertions.

The integer-lane/vector-ALU test covers every arithmetic, logic, shift,
comparison, movement, selection, special-register, branch, and memory-address
operation. It explicitly checks two's-complement `MIN`/`MAX`/comparisons,
low-32-bit multiply, five-bit shift amounts, immediate sign extension, inactive
output suppression, predicate inversion and gating, `SEL` on every active lane,
write masks, unsupported operations, and vector address/store-data generation.

The instruction-fetch test programs every memory word, checks sequential fetch,
multi-cycle downstream stalls, stable response data, redirects, final-word
execution, sequential and launch-time range faults, sticky fault reporting,
software clear, restart, and halt. An assertion rejects ambiguous simultaneous
programming and fetching of the same instruction word.

The writeback test covers buffered backpressure, complete payload stability,
GPR-only and predicate-only commits, lane-mask preservation, simultaneous
drain/refill, flush cancellation, and empty-mask suppression. Assertions ensure
that stalled payloads remain stable and that empty architectural writes cannot
reach either register file.

The completion-queue test transports the complete canonical tagged record and
covers empty/one/full occupancy, prolonged output backpressure, FIFO ordering,
simultaneous drain/refill, ring-pointer wraparound, and flush cancellation.
Assertions check occupancy bounds, valid record tags, and complete payload
stability while stalled. Three instantiated sources, arbitration, and end-to-end
conservation remain integration-level obligations.

The ALU-completion/writeback integration test checks construction and transport
of every canonical tag, writeback stalls, GPR data/masks, predicate retirement
with an empty lane mask, epoch/warp/sequence/destination scoreboard-clear tags,
stale-epoch cancellation, and fatal-fault suppression of an otherwise ready
same-cycle commit. Multiplier/memory collisions and arbiter fairness remain open.

The dependency-scoreboard test covers reset and host clear, per-warp isolation,
GPR RAW/WAW blocking, predicate RAW/WAW blocking, exact epoch/warp/sequence/
destination clear matching, rejection of wrong tags, same-cycle GPR commit release
for register-file forwarding, and the required lack of same-cycle predicate
release. An assertion forbids accepted issue while any dependency is unresolved.

The round-robin issue test drives all four requesters, sparse eligibility, and a
three-cycle downstream stall. It checks accepted grants rotate 0, 1, 2, 3,
priority advances only on acceptance, and the selected request remains stable
while stalled. The completion-arbiter test repeats the protocol across all three
architectural completion classes.

The multiplier test accepts three fully tagged vector operations on consecutive
cycles, checks all eight low-32-bit products, fills the two-entry completion
queue and three pipeline stages under sink backpressure, drains in order, and
verifies flush cancellation. The lifecycle integration test executes a dependent
`MUL`, observes a multiplier-class architectural completion, and confirms clean
drain before kernel completion.

The four-warp integration test launches one and four resident warps through the
same instruction stream. It checks independent PC, active-mask, sequence,
register, and scoreboard state; `S2R WID`; all 24 ordered per-warp commits;
round-robin progress; multiplier tags; counters; and full-machine drainage. Its
dependency-heavy arithmetic baseline records 0.428 IPC for one warp and 0.827
IPC for four warps. The checked-in result and interpretation are in
`docs/performance_results.md`.

The divergence integration test executes the canonical `SSY`, guarded `BRA`,
uniform redirect, and two-arrival `SYNC` sequence. It checks low-lane taken-path
and high-lane deferred-path masks, final per-lane values, ordered sequence tags,
full drainage, empty-stack underflow, and ninth-push overflow. It also executes
a depth-two nested split and four simultaneously diverging resident warps. The
canonical 11-event RTL trace agrees with the independent emulator. Stack-depth,
state-stability, and fault-suppression assertions run in both simulators;
bounded-engine proofs remain assigned to the pre-memory verification gate.

The single-warp integration test programs instruction memory and executes two
independent immediate writes, a RAW-dependent add, a predicate comparison, a
predicate-dependent guarded add, and lane-level `EXIT`. It checks six ordered,
fully tagged architectural commits, representative lane results, predicate data,
pipeline drainage, and clean kernel completion without a fault.

The lifecycle integration test covers partial-mask and final lane exit, surviving-
lane execution, multiplier completion, unsupported-stage and illegal-instruction faults, instruction
programming while busy, same-cycle suppression, sticky diagnostics, and clear
recovery. The C++ emulator and RTL independently emit complete register,
predicate, active-mask, PC, and instruction state after each architectural event;
`scripts/compare_arch_traces.py` stops at the first differing line.

Before synthesis freeze, static verification closes RTL lint, CDC, reset-domain
crossings, reset deassertion, and interactions among functional, host, scan, and
BIST clocks. Every reported crossing and exception receives a documented review.

The merge CI gate runs ISA-generation consistency, Python assembler/disassembler
tests, C++ emulator tests, RTL lint, Verilator unit tests, selected integrated
programs, first-mismatch trace comparison, documentation consistency, and diff
format checks from a clean checkout. Large XSim, formal, synthesis, DFT, and
physical jobs may run on schedules or explicit release triggers.
