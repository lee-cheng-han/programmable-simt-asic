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

The integrated warp-frontend test checks that a single round-robin memory port
fills all four per-warp instruction buffers, buffered records remain stable
during prolonged issue stalls, a consumed warp refills at its new PC, a PC
redirect cannot install an older response, and fatal/clear-style flushes discard
both buffered and in-flight work. Assertions enforce one-hot requested service,
active/in-range requests, and buffer-to-architectural-PC coherence.

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
dependency-heavy arithmetic baseline records 0.272 IPC for one warp and 0.750
IPC for four warps with the shared buffered instruction port. The checked-in result and interpretation are in
`docs/performance_results.md`.

The independent four-warp C++ model maintains a PC, active mask, GPRs,
predicates, dependency state, sequence counter, and depth-eight SIMT stack for
each resident warp. It selects eligible warps round-robin and delays multiplier
results by three model cycles. RTL and model emit canonical commit records keyed
by epoch, warp, and sequence; the comparator rejects duplicate keys and reports
the first field-level mismatch after key ordering. The arithmetic comparison
covers 48 events across two drained launches and the simultaneous divergence
comparison covers 44 events. Mid-flight epoch cancellation, three independent
backpressure boundaries, structured control, and the complete pre-memory ISA are
included in the closed differential matrix. Memory and barriers are next.

The UVM 1.2 processor environment provides a reusable command sequence item,
sequencer, active programming/launch driver, architectural commit monitor,
agent, environment, and protocol-aware scoreboard. Its smoke test programs and
launches four warps, enforces per-warp sequence continuity, checks drained issue
and commit counts, writes the canonical epoch/warp/sequence trace, and invokes
the same independent C++ model and first-mismatch comparator used by the directed
regression. `make uvm-differential` is the reproducible entry point. UVM remains
an additional verification frontend and does not replace fast Verilator tests.

### UVM and differential closure

The closed environment consists of the active core agent, driver,
monitor, scoreboard, basic arithmetic sequence, and independent differential
test. It remains the smoke gate while memory verification is added.

The current implementation includes constrained-random legal integer/dependency
programs, a clear/relaunch virtual sequence, deterministic test/seed selection,
per-run artifacts, randomized execution-completion and writeback backpressure,
stable-handshake assertions, and architectural opcode/warp/source/mask/stall
coverage. Shallow and nested divergence/reconvergence now run with a selectable
one-through-four resident warps, canonical lane ordering, and opcode-by-resident-
warp coverage. A fatal-recovery virtual sequence now provokes a stack underflow,
checks that the faulting instruction has no issue or commit side effect, clears
the sticky fault, and differentially checks a drained four-warp relaunch in the
next epoch. A separate virtual sequence cancels accepted outstanding work and
differentially checks the next epoch. The portable merge reports 43/43 approved
risk bins with no unexplained holes. Random
generation must favor
meaningful dependency, predication, scheduling, and
structured-control scenarios rather than arbitrary words dominated by illegal
encodings. Every run records the test name, simulator, seed, generated assembly
and binary, RTL trace, model trace, first mismatch, and simulation log.

The release regression runs reproducible seed lists sequentially because XSim
elaborations share runtime state. It retains failure artifacts and merges
portable coverage. The closed run contains seven test classes across seeds 1–3:
21 simulations, zero UVM errors, and 21 model-matched traces.

Closure evidence is 43/43 approved risk bins, two twelve-cycle inductive arbiter
proofs, one exhaustive architectural-writeback proof, and 9/9 detected mutations
with no survivors or invalid mutants. Mutations cover scheduler priority,
scoreboard epoch ownership, FIFO ordering/capacity, multiplier data, stale-epoch
writeback, divergent masks, stack overflow, and early `done`.

Memory verification adds a six-cycle bounded bank-engine proof and expands the
mutation result to 13/13 detected with no survivors or invalid mutants. The new
cases cover inactive-lane validation, fault prevalidation, bank selection, and
same-warp tracker exclusivity. Licensed memory differential runtime and its
coverage closure remain open.

Initial functional coverage includes opcode, resident warp count, selected warp,
completion source, dependency type, predicate mode, active-mask class, branch
outcome, divergence depth, queue occupancy, multiplier occupancy, epoch
transition, clear timing, fault class, and kernel-drain blocker. Required crosses
are limited to combinations representing a documented design risk so coverage
closure remains technically meaningful.

`make uvm-regression UVM_SEEDS="1 2 3"` reproduces the closed deterministic
multi-seed entry point. Each successful run retains its generated hexadecimal
and binary program, model and RTL traces, first-mismatch result, and simulator
logs under a test-and-seed-specific directory. Portable manifests use the same
identity and `make coverage-report` merges them without a proprietary coverage
license. Native XSim coverage is optional with `XSIM_NATIVE_COVERAGE=1`.

The divergence integration test executes the canonical `SSY`, guarded `BRA`,
uniform redirect, and two-arrival `SYNC` sequence. It checks low-lane taken-path
and high-lane deferred-path masks, final per-lane values, ordered sequence tags,
full drainage, empty-stack underflow, and ninth-push overflow. It also executes
a depth-two nested split and four simultaneously diverging resident warps. The
canonical 11-event RTL trace agrees with the independent emulator. Stack-depth,
state-stability, and fault-suppression assertions run in both simulators. The
mask-swap and stack-wrap mutations demonstrate focused-test sensitivity.

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
