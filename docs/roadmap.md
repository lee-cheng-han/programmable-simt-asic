# Tapeout development roadmap

This roadmap is subordinate to `docs/architecture.md`. Release stages are named
by their engineering exit criteria rather than internal sequence numbers.

## Immediate execution order

The following sequence is the active path to shared-memory development. SRAM
macro investigation runs in parallel but must converge before the frontend and
memory contracts freeze.

| Order | Release group | Current state | Required before shared memory |
|---:|---|---|---|
| 1 | Processor architecture foundation | Complete: consolidated core, four-warp execution, nested reconvergence, fatal bounds, emulator trace agreement, and provisional IHP SRAM views pass | Preserve the single authoritative core and selected macro contract |
| 2 | Frontend and model stabilization | Complete: SRAM-backed fetch, randomized response backpressure, lifecycle cancellation, mapped synthesis, and integrated legal placement | Preserve as a regression gate during memory integration |
| 3 | Pre-memory verification | Complete: 21-run differential matrix, 43/43 approved risk bins, three formal proofs, and 9/9 mutations detected | Preserve closure while extending coverage for memory behavior |
| 4 | Memory-system integration | In progress: banked memories, trackers, completion, barriers, directed reduction, and model support pass | Close differential, random, formal, mutation, macro-wrapper, and coverage evidence |

Performance counters remain limited to measurements needed for current claims.
Extended counters and bounded debug snapshots stay in the standalone-core
release. Floating point remains outside the baseline, and the shared-memory
reduction remains the primary end-to-end workload. A post-baseline FP32
execution extension is planned after the integer ASIC release closes; it does
not block any baseline release gate.

## Processor architecture foundation

This group establishes the executable SIMT processor, its authoritative contract,
and the implementation assumptions that affect every later subsystem.

### Specification merge

Audit existing code and tests, freeze one authoritative contract, remove
contradictory legacy platform descriptions, and preserve passing work.
Create and maintain `docs/requirements_traceability.md`, mapping every normative
requirement to RTL, directed tests, assertions/formal properties, coverage, and
current status.
Exit requires clean Python, C++, Verilator, and XSim regressions and no unresolved
policy conflict. The traceability matrix must contain no unowned requirement.

### SRAM and implementation feasibility

Before architectural freeze, select actual instruction, scratchpad, and shared
SRAM macros from the chosen open-PDK flow. Confirm supported widths and depths,
logical banking, Liberty/LEF/GDS/model availability, power-pin compatibility,
BIST-port feasibility, preliminary placement, routing channels, and timing across
each macro boundary. Run early synthesis and a trial floorplan around those real
views. Behavioral wrappers may remain during core development, but memory size,
banking, timing, and floorplan assumptions cannot freeze without this evidence.

### Integrated single-warp processor

Connect instruction memory, fetch, decode, dependency checks, register files,
predicate state, eight ALU lanes, ALU completion queue, architectural writeback,
and exit. Execute movement, arithmetic, logic, shifts, comparisons, predication,
`SEL`, `S2R`, and `EXIT` with instruction-level emulator agreement.
The GPR and predicate scoreboard skeleton is part of this integration, so this
stage is not limited to manually scheduled dependency-safe programs.

### Four-warp execution and multiplier

Extend the scoreboards across all warp state, add round-robin scheduling, three-stage
multiplier, multiplier queue, two-source arbitration, epoch/quiescence, and
scheduler/arbiter fairness. Publish one-warp versus four-warp arithmetic results.

### Divergence and reconvergence

Integrate branch masks, `SSY`, `SYNC`, nested SIMT stack behavior, redirects, and
fatal stack faults with differential and formal evidence. Exit requires nested
and simultaneous four-warp divergence, structured mask coverage, emulator
agreement, executable stack-safety assertions, and clean recovery after every
fatal control-flow fault. Randomized control flow and bounded-engine proofs
continue in the pre-memory verification gate.

### Authoritative-core consolidation

Replace the separate single-warp and four-warp processor implementations with one
authoritative parameterized core. A launch may activate one through four resident
warps without changing the implemented datapath. Preserve one-warp trace
comparison, four-warp throughput results, lifecycle faults, and divergence
behavior. Shared execution, fault, completion, quiescence, and counter logic must
have one RTL owner.

Exit requires every existing processor regression to use the consolidated core,
no duplicated architectural control path, and unchanged published arithmetic
results or a documented explanation for any cycle-count change.

## Frontend and pre-memory stabilization

This group replaces behavioral implementation assumptions, establishes
multi-warp differential evidence, and resolves physical risks before memory RTL
expands the design.

### Physically realizable instruction frontend

Replace the behavioral four-way combinational instruction lookup with a frontend
that can map to the selected instruction SRAM. Use one shared fetch port,
round-robin fetch arbitration, and at least one buffered instruction record per
warp. Scheduler eligibility derives from stable buffered decode state rather than
four simultaneous SRAM reads. Redirects invalidate only unissued buffered work,
and fetch backpressure cannot lose, duplicate, or issue a wrong-path instruction.

Exit requires a qualified SRAM-compatible port/timing contract, directed buffer
fill/drain/redirect tests, randomized fetch stalls, clean synthesis, and no
combinational architectural dependency on four instruction-memory read ports.

Current evidence: the authoritative core now uses one shared read request per
cycle, round-robin request arbitration, one stable instruction buffer per warp,
and tagged stale-response rejection. Directed tests cover all buffer fills,
prolonged issue stalls, consume/refill, redirect, and flush, and every processor
regression uses this frontend. Qualification against a selected SRAM macro,
randomized fetch stalls, synthesis, and physical timing evidence remain open.

### Multi-warp reference model and differential traces

Extend the independent model with four warp contexts, architectural warp IDs,
per-warp PC/mask/sequence/stack state, round-robin issue selection, dependency
stalls, multiplier latency, completion arbitration, epoch cancellation, and
drained kernel completion. The model and RTL emit warp-tagged traces containing
PC, instruction, active mask, stack summary, registers, predicates, commits,
faults, and cancellation reasons.

Exit requires first-mismatch comparison for arithmetic, predication, multiplier,
uniform and divergent branches, nested reconvergence, clear/relaunch, and fatal
stack faults. At least one reproducible randomized structured-control regression
must pass across multiple seeds.

Current evidence: an independent four-warp C++ model owns per-warp PC, mask,
register, predicate, sequence, dependency, multiplier-latency, and SIMT-stack
state with round-robin issue. Epoch/warp/sequence-keyed first-mismatch comparison
passes 48 arithmetic events across clear/relaunch and 44 simultaneous-divergence
events against RTL. Predication is exercised inside divergence, including
taken/deferred masks. Mid-flight epoch cancellation, fatal-stack differential records, completion
arbitration timing, and multi-seed structured-control generation remain open.

### Early implementation checkpoint

Synthesize the consolidated core and SRAM-compatible frontend before adding the
memory system. Report area, critical paths, reset fanout, multiplier cost,
register-file muxing, scheduler/decode timing, completion arbitration, and SIMT
stack implementation. Run a trial floorplan using the selected instruction,
scratchpad, and shared-memory macro outlines and timing views.

Review reset policy at this checkpoint. Reset validity, masks, ownership, pointers,
and control state; avoid resetting large data arrays unless the architectural or
test contract requires it. Any timing or area concern that would change the
pipeline, memory ports, banking, or physical hierarchy must be resolved before
the memory architecture freezes.

Current evidence: the complete authoritative core parses through the Yosys slang
frontend without errors or warnings. A generic behavioral-array trial reached
118,529 cells before ABC and presented ABC with 92,123 combinational gates,
25,298 inputs, and 3,266 outputs. This is diagnostic evidence, not a PPA result:
the replicated register file and behavioral storage structures dominate the
unmapped design. `make synth-elab` provides the bounded frontend gate and
`make synth` preserves the full generic experiment and its report. The IHP
SG13G2 64×64 and 256×64 SRAM artifact sets now pass automated LEF, GDS, CDL,
Verilog, three-corner Liberty, BIST-port, and power-pin checks. A 17-macro
OpenROAD trial reports 0.8583 mm² of macro area and legal placement in a
1.70 mm × 0.80 mm die. Memory wrappers, register-file implementation review,
integrated mapped timing/area, halos, PDN, and routing remain open.

Before physical freeze, complete a measured register-file implementation study
covering flip-flop, latch-based where supported, replicated SRAM, banked, and
time-multiplexed organizations. Compare area, timing, power, port semantics, and
routing, then select one explicitly. Run X-propagation and initialization tests
for SRAM, invalid queue payloads, trackers, inactive lanes, and reset release;
architectural behavior may not depend on uninitialized data.

Maintain a supported-configuration regression for one through four resident
warps, reduced simulation memories, permitted queue/tracker depths, and
behavioral, ASIC-macro, and later FPGA memory wrappers. Unsupported combinations
must fail elaboration with a clear diagnostic.

### Pre-memory verification gate

Add randomized backpressure at execution completion and architectural writeback.
Prove or bound scheduler fairness, stack bounds, stack-fault side-effect
suppression, exact scoreboard ownership, stale-epoch rejection, queue
conservation, and the complete kernel-done implication. Begin continuous mutation
testing with scheduler-priority, scoreboard-clear, forwarding-warp, multiplier-
latency, branch-mask, stack-wrap, and early-done defects.

Exit requires all required simulations, differential traces, selected bounded
proofs, and the initial mutation set to pass. Results must be reproducible from
checked-in commands, and every remaining waiver must have an owner and reason.

Current class-based evidence: a UVM 1.2 core agent drives instruction
programming and launch, monitors architectural commits, checks per-warp sequence
continuity and drained counters, emits the canonical trace, and compares it with
the independent C++ model. A legal constrained-random integer/dependency
sequence, clear/relaunch virtual sequence, architectural coverage subscriber,
seeded regression entry point, and per-run artifact layout run under XSim 2026.1.
Two reproducible seeds pass for legal dependency programs and independent
execution-completion/writeback backpressure, including 60- and 48-event random
traces plus 24-event stalled traces. Stalled grants remain stable, an elastic
writeback boundary decouples the ready domains, handshake assertions pass, and
stall coverage is sampled. Shallow and nested structured-control programs also
pass model comparison with one through four resident warps, including 19, 22,
33, 38, and 44-event traces. Twelve-cycle temporal-induction runs pass for the
four-request scheduler and three-request completion arbiter, covering one-hot
selection, request validity, stalled stability, and bounded accepted-grant wait.
The deterministic mutation suite detects 9/9 scheduler, scoreboard-owner, FIFO-
ordering/capacity, multiplier-datapath, stale-writeback, branch-mask, early-done,
and stack-overflow defects. Mid-flight host clear now
cancels accepted but uncommitted work and a four-warp epoch-1 relaunch drains
differentially. Random fetch-response backpressure is also model matched. A
portable 23-manifest coverage merge reports 43/43 approved risk bins (100%):
opcode, warp, resident-warp count, source, mask class, and execution/writeback
stall bins are closed. Twelve-cycle induction proves both arbitration uses, and
an exhaustive writeback proof covers fatal priority, stale epochs, handshake,
and side-effect gating. The pre-memory verification gate is closed.

The class-based verification work proceeds through four explicit closure phases:

1. **Environment foundation — complete.** Preserve the core agent, driver,
   monitor, scoreboard, directed sequence, canonical trace export, and
   independent-model differential test as a continuously passing smoke gate.
2. **Random stimulus and observability — complete.** Legal dependencies,
   structured control, resident-warp variation, three backpressure boundaries,
   fatal recovery, and outstanding-work cancellation pass differential checking.
3. **Regression and analysis — complete.** Seven classes across three seeds pass;
   portable coverage is 43/43 approved bins with no exclusions or holes.
4. **Verification closure — complete.** Three formal proofs pass and all 9
   injected mutations are detected, with no survivors or invalid mutants.

The first random release must cover one through four resident warps, RAW/WAW and
independent instruction streams, ALU/multiplier dependencies, predicate mask
classes, uniform and divergent branches, legal nested stack depths, drained
relaunch, mid-flight clear, fatal recovery, completion-source collisions, and
random completion/writeback stalls. High-value coverage crosses include opcode
by warp count, producer by consumer dependency, completion source by stall and
collision, branch outcome by mask class, stack depth by warp, and fault or clear
timing by outstanding work. Unbounded or architecturally meaningless crosses are
excluded rather than pursued for a cosmetic percentage.

## Memory system

This group implements both banked address spaces, ordering, replay, barriers,
trackers, and memory completion as one coherent subsystem.

### Shared memory and barriers

Integrate eight shared banks, replay, broadcast, tracker behavior, barriers,
ordering, and deadlock watchdog. Exit requires a passing multi-warp reduction.

Current implementation includes the eight-bank 2 KiB shared store, deterministic
lane replay and load broadcast, full-warp barriers, a missing-warp simulation
watchdog, and a four-warp shared-memory reduction that produces six in every
lane after synchronizing contributions from warp IDs zero through three.

The watchdog is now architectural rather than testbench-only: a parameterized
timeout raises sticky `FAULT_BARRIER_DEADLOCK`, reports the oldest waiting
barrier PC, suppresses further issue/commit through the fatal path, and is
mirrored by the multi-warp reference model. Directed tests cover successful
four-warp release, no early post-barrier commit, and a missing-warp timeout.

### General scratchpad and memory completion

Integrate the 4 KiB eight-bank scratchpad, four trackers, response collector,
memory queue, three-source arbitration, store ordering, load visibility, and
stale-response rejection. A fifth operation and second same-warp operation must
backpressure safely.

Current implementation includes the eight-bank 4 KiB scratchpad, four tagged
system-wide trackers, one-operation-per-warp allocation, a two-entry memory
completion queue, three-source completion arbitration, instruction-atomic fault
validation, and directed fifth-operation/same-warp backpressure checks.

### Memory architecture and verification closure

Freeze and verify cross-warp visibility, barrier ordering, same-address store
behavior, memory lifetime across launch/clear/reset/fault/BIST, and the explicit
absence of baseline atomics. Add host-visible watchdog control and a waiting-warp
snapshot around the implemented configurable architectural timeout. Prove that
valid barriers cannot trip it and that older memory drains before arrival.

Extend the UVM environment with memory-aware sequence items, constrained-random
addresses and masks, general/shared selection, broadcast, every bank-conflict
degree, all tracker occupancies, fifth-request and same-warp rejection,
completion backpressure, cross-warp aliases, clear/fault collisions, and virtual
sequences coordinating four warps. Add an optional diagnostic memory trace with
epoch, warp, sequence, lane, space, address, bank, row, tracker, service cycle,
response cycle, and fault result; the architectural commit trace remains the
pass/fail authority.

Current progress: the differential environment now contains a seeded legal
constrained-random memory sequence with six to fourteen store/load pairs across
general and shared spaces, selectable conflict-free or all-lanes-bank-zero
address patterns, randomized completion/writeback backpressure, automatic
instruction-count checking, and model trace comparison. Functional coverage
tracks all four memory opcodes plus load/store and general/shared classification.
The test passes XSim compilation and elaboration; simulation remains blocked on
this host when the XSim runtime cannot check out its license.

The bank engine now has a passing six-cycle bounded safety proof for readiness,
pending-mask consistency, atomic fault response, and stalled-response stability.
The deterministic mutation suite detects 13/13 injected defects with no
survivors or invalid mutants, including inactive-lane validation, skipped fault
prevalidation, wrong bank selection, and duplicate same-warp tracker allocation.

Close fault atomicity across load/store, both spaces, every invalid-lane
position, inactive invalid lanes, multiple invalid lanes, conflicts, stalled
completion, clear, and older work. Assertions and formal properties cover
tracker ownership/capacity, queue conservation, stable responses, ascending-lane
store service, no bank service before full validation, no faulting-store byte
write, no faulting-load GPR write, barrier-release preconditions, blocked-warp
issue suppression, memory-inclusive done, and cancellation under clear/epoch
change. Liveness is proven under explicit fairness assumptions.

Continue mutation testing with wrong row selection, permitted misalignment,
partial fault commits, prevalidation
store leakage, reversed lane priority, duplicate same-warp trackers, premature
tracker free, omitted epoch matching, early barrier release, ignored pre-barrier
memory, and early done. Publish injected/detected/invalid/surviving counts.

Coverage closure includes opcode by space, operation by conflict degree, mask
class by invalid lane, warp by tracker, occupancy by acceptance, broadcast versus
replay, completion source by backpressure, barrier arrival order by pending
memory, fault type by space/lane, and clear/fault by tracker state. Exclusions
require written justification. Exit requires multi-seed UVM differential passes,
no unexplained mismatch, closed approved bins, passing memory formal and mutation
suites, and reproducible reports.

### Qualified data memories

Select the real data-SRAM organization before place-and-route. Map every logical
bank to legal macros and provide one portable wrapper contract with ASIC macro,
behavioral simulation, and later FPGA block-RAM implementations. Freeze read
latency, byte masks, collisions, power pins, reset policy, BIST ports, and
Liberty/LEF/GDS/CDL/Verilog corner views. Re-pipeline address, SRAM, or response
collection if macro timing or congestion requires it. Exit requires automated
view checks, wrapper equivalence tests, synthesis inference evidence, preliminary
bank placement, and timing across every macro boundary.

Current progress: the portable logical-bank adapter supports the selected
64×64 IHP macro, the general-memory packed-half mapping, shared-memory low-half
mapping, byte masks, synchronous read response/backpressure, and exclusive BIST
ownership. Behavioral-versus-macro functional equivalence passes for full-word,
partial-byte, adjacent-half, stalled-response, and ownership cases. All sixteen
data adapters are integrated into the vector bank engines. Mapped synthesis
retains exactly 17 selected SRAM macros and reports 183,869 cells with about
3.23 mm² standard-cell area; the 3.20 mm × 2.50 mm trial legally places 183,852
movable cells and all 17 real macros at 53.4% utilization with zero placement
failures. Routed macro-boundary timing remains part of physical-design closure.

## Standalone verification release

This group turns the integrated processor into a reproducible, quantitatively
verified release with workloads, coverage, formal evidence, and continuous
regression gates.

### Standalone-core release

Complete workloads, counters, fault model, differential traces, random generation,
emulator memory ordering, and quantitative scheduler/memory/divergence studies.
Shared-memory reduction is the flagship end-to-end workload. It must exercise
four-warp scheduling, bank conflicts and replay, barriers, predication, ordering,
and performance counters. Matrix multiplication is a secondary workload.

Instrument cycles, issues, commits, empty-eligibility cycles, dependency stalls,
tracker stalls, replay cycles, broadcasts, completion stalls, barrier wait,
divergence, and faults. Architectural cycle/instruction counters are 64-bit
wrapping; diagnostic counters are 32-bit saturating. Compare identical one-warp
and four-warp workloads and publish cycles, IPC, stall breakdown, replay, and
barrier cost. The reduction is the primary walkthrough from model through RTL
and ASIC reports; vector addition is the first secondary throughput baseline,
with small integer matrix multiplication optional only after those close.

Add a bounded coherent host-readable snapshot of epoch, status/fault/PC,
resident and barrier masks, warp PCs and active masks, scoreboard and tracker
occupancy, SIMT-stack-top metadata, and completion/writeback queue occupancy.
Do not create a full-register-file ASIC debug mux.

Expose immutable ISA/architecture versions, RTL build ID, feature bits,
lane/warp counts, memory sizes, tracker depth, and queue configuration. Provide
a minimal C or Python host runtime for loading, initialization, launch, polling,
fault/counter inspection, and result retrieval; this is not a compiler or
CUDA/OpenCL compatibility layer.

Every workload has assembly, generated inputs, an independent expected result,
launch configuration, automatic checking, and one performance-report command.
Flows emit machine-readable JSON for tests, seeds, coverage, mutation, formal,
cycles/IPC, timing, area, power, and physical checks. Each result records the
revision and dirty state, tools, PDK/SRAM versions, constraint/workload hashes,
seed, date, and host. README tables consume these artifacts.

Add a cycle-level analytical model using instruction mix, warp count, dependency
distance, conflict/replay degree, and barriers. Compare predictions with RTL.
Study bank mapping and queue/tracker depth sensitivity on reduction and vector
addition, but change the baseline only when measured benefit justifies renewed
area, power, and verification cost.

### Verification closure

Close assertions, bounded formal properties, numerical functional coverage,
long seeded regressions, fairness stress, bug injection, requirements traceability,
and documented limitations. No unexplained mismatch may remain.

Complete pairwise fault-priority tests for reset, clear, fetch/decode, memory,
barrier/control, completion, and ordinary progress. Explicitly verify the
accepted-before-edge versus merely-valid writeback boundary. Retain first-
mismatch artifacts and requirement-to-test/assertion/coverage ownership.

### Continuous-integration release gate

Every merge candidate runs canonical ISA-generation consistency, assembler and
disassembler tests, emulator tests, RTL lint, Verilator unit tests, selected
integration programs, architectural trace comparison, documentation-link and
contract-consistency checks, and `git diff --check`. The required set must pass
from a clean checkout with pinned tool versions. XSim, long random regressions,
formal proofs, synthesis, DFT, and physical implementation remain scheduled or
manually triggered jobs whose reports are required at their release gates.

The required fast gate additionally runs mutation smoke, formal smoke, Python
syntax, documentation-link/contract checks, and all directed memory/barrier
programs. A deterministic licensed runner must host XSim UVM jobs; compilation
or elaboration alone is not a simulation pass. Scheduled jobs merge multi-seed
coverage and preserve seeds, programs, traces, logs, and tool versions.

CI validates claim categories and provenance. Every number is labeled as an
architectural-model result, RTL simulation, synthesized estimate, post-route
result, FPGA measurement, or silicon measurement; categories are not silently
substituted.

## ASIC integration and test

This group freezes the implementation contract and integrates host control,
qualified SRAMs, static signoff, the MPW harness, scan, and memory test.

### ASIC architecture freeze

Use early synthesis and floorplanning to freeze ISA, pipeline, register-file
organization, SRAM macros, queue depths, epoch, host map, clock/reset, DFT ports,
physical hierarchy, and the selected MPW harness contract. Exit requires qualified
SRAM views, preliminary macro placement and boundary timing, and no unresolved
architectural dependency on an assumed memory implementation.

### Static RTL signoff

Close RTL lint, clock-domain crossings, reset-domain crossings, reset assertion
and deassertion behavior, and functional/host/scan/BIST clock interactions before
the synthesis freeze. Review every crossing and document every synchronizer,
false path, asynchronous path, and tool waiver. Exit requires clean reports or
explicitly justified exceptions with owners.

Add RTL-to-synthesis-netlist equivalence and rerun equivalence after scan,
clock-gating, SRAM-wrapper substitution, and every functional ECO. Synchronize
reset deassertion and prove unsafe release cycles cannot issue, commit, write an
SRAM, or respond to the host.

### Host and SRAM integration

Add the internal bus, Wishbone wrapper, SRAM macro wrappers and views, host
loading/launch, quiescence/fault reporting, ownership checks, and instruction-write
busy fault.

The host register map covers program loading, launch PC, resident-warp count,
launch, clear, status, sticky fault/code/PC, watchdog control, counters, debug
snapshot, and explicitly authorized scratchpad initialization/readback. Verify
backpressure, invalid addresses, busy writes, reset, ownership, and simultaneous
host/core accesses. Freeze memory lifetime as follows unless later evidence
forces a revision: reset contents are unspecified, software initializes used
data, launch does not implicitly clear arrays, host clear preserves memory for
debug, a fault preserves memory, and destructive BIST may destroy contents.

Add bring-up breadcrumbs for reset observed, clock active, launch observed,
first issue, first commit, and SRAM-BIST completion. Include a deterministic
diagnostic program exercising ALU, registers, control flow, both memories, and
barriers independently of the normal workload stack.

Provide verification-build-only injection of SRAM read corruption, completion-
tag corruption, tracker timeout, illegal instructions, and suppressed barrier
arrival. Production synthesis removes or disables these hooks and records their
status in the build manifest.

### MPW harness integration

Deliver a harnessed digital macro: integrate the selected shuttle harness, address
and I/O map, top-level power connections, clocks and resets, Wishbone attachment,
and submission configuration. Close harness timing, full-wrapper DRC/LVS, shuttle
prechecks, and submission-specific repository validation. A standalone pad ring,
package, and board are outside this release target.

### DFT release

Complete scan architecture and simulation, supported ATPG reporting, destructive
SRAM BIST, test ownership, and functional/scan/BIST timing constraints.

Document scan enable/test mode, reset controllability, clock-gating bypass,
supported ATPG coverage, SRAM repair policy where available, destructive BIST
ownership, and all test clocks/exceptions. The functional baseline uses no manual
architectural clock gating; evaluate tool-inserted or coarse gating only after
ungated closure, prove enable equivalence, and force clocks active in scan mode.

Create a minimal UPF-aware power contract even for the single-domain baseline:
always-on assumptions, SRAM power pins, explicit absence of isolation/retention,
power-up order, and reset requirements are checked and documented.

## Physical and signoff release

This group takes the frozen, testable macro through implementation, physical
verification, timing/power closure, and the final GDS audit.

### Physical implementation

Complete synthesis, floorplan, macro placement, PDN, placement, CTS, routing,
extraction, timing optimization, antenna repair, fill, re-extraction, and ECO loop.
Every violation enters a tracked loop: root-cause analysis, RTL or physical ECO,
incremental implementation, extraction, STA, equivalence, DRC/LVS, and affected
functional regressions. An ECO closes only when all impacted evidence is rerun.

Close one balanced implementation end to end before exploring area or
performance variants. Define generated clocks, I/O delays, uncertainty, reset
treatment, false/multicycle paths, SRAM arcs, scan clocks, and mode constraints;
exceptions may not conceal violations. Floorplan banks near their engines,
inspect register-file and wide-vector-bus congestion, control reset fanout, and
pipeline macro boundaries when required by measured timing.

Use mapped and post-placement timing to review scheduler selection, register-
file reads, address generation, bank selection, completion arbitration, and
writeback fanout. Pipeline only paths shown to be limiting, and rerun all
architectural/differential evidence after any latency change.

### Signoff and GDS release

Complete supported MMMC STA, activity-based power, IR/EM review, DRC, LVS,
antenna, density/connectivity, equivalence, GLS/SDF, scan/BIST validation, release
audit, archived reports/checksums, bring-up firmware, and silicon test plan. The
filled GDS is the signoff database. After final fill, rerun extraction, setup/hold
STA, DRC, LVS, antenna, density, power review, and final-netlist consistency; no
pre-fill result may substitute for this exit gate.

Power uses activity from the shared reduction and vector-add workloads rather
than an unsupported default toggle rate. Report dynamic, leakage, clock,
register-file, SRAM, replay, and peak/average assumptions. Archive pinned tools,
commands, constraints, PDK/macro checks, report provenance, floorplan/congestion
images, timing and power summaries, waivers, and checksums. Never label generic,
estimated, pre-fill, or incomplete data as silicon/signoff PPA.

Run targeted SDF gate-level simulations of reset/launch, shared reduction,
vector addition, fault/clear recovery, SRAM access, and scan/BIST smoke. GLS
supplements rather than replaces STA and equivalence. Final release requires
RTL-to-final-netlist equivalence with documented handling of SRAM/test structures
that cannot be compared directly.

## Engineering decision and failure records

Maintain concise decision records for scratchpad over caches, four warps, eight
lanes/banks, one tracker per warp, queue depths, SRAM organization, ASIC-first
sequencing, and deferred FP32. Record alternatives, evidence, tradeoffs, and the
conditions for revisiting each decision.

Preserve representative real failure analyses with symptom, first mismatching
trace, root cause, correction, regression, and the assertion or mutation that
prevents recurrence. Do not create retrospective or fabricated failures.

## FPGA implementation after ASIC closure

Preserve the architectural core and substitute FPGA block-RAM wrappers behind
the same memory interfaces. Add only board-level clock generation, synchronized
reset, AXI-Lite or Wishbone/UART host transport, program/data loader, constraints,
and logic-analyzer hooks in the FPGA shell. Do not distort the ASIC datapath for
board-specific behavior.

Run the same shared reduction and vector-add binaries and compare emulator,
RTL, and hardware result memory plus counters. Publish achieved frequency,
resource utilization, cycles, IPC, stalls, replay, barrier wait, and readback.
The FPGA release closes only with reproducible bitstream generation and an
emulator-to-RTL-to-board agreement report.

## Planned post-baseline extension

### FP32 execution pipeline

After the integer ASIC release closes, add an optional eight-lane FP32 pipeline
supporting floating-point add and multiply. Before RTL begins, freeze the
arithmetic contract for rounding, NaNs, infinities, signed zero, subnormals, and
exception status. The initial extension uses round-to-nearest, ties-to-even; has
no traps, FP64, fused multiply-add, division, square root, or transcendental
operations; and represents FP32 operands as 32-bit values in the existing GPRs.

Reserve unused ISA opcode space and the fourth completion-class encoding for this
extension. The implementation receives its own elastic completion queue and
participates in fair shared writeback without changing integer, multiplier, or
memory semantics. Queue-depth and arbitration bounds must be re-proved for four
active completion sources.

Exit requires an independent bit-accurate reference, directed IEEE edge cases,
random differential testing, pipeline/backpressure verification, synthesis and
timing results, and updated power/area comparisons. The integer ASIC remains the
required completed project if the FP32 extension is not started or does not close.
Multi-cluster scheduling, caches, coherence, and external DRAM remain outside this
extension.

### Deferred architectural experiments

Caches remain deferred because tags, misses, replacement, write policy,
coherence, and ordering would obscure closure of the intentional scratchpad
architecture. Multi-cluster scheduling remains deferred until one cluster has a
complete host/memory interface and a measured bottleneck; it would require block
dispatch, cluster IDs, global arbitration, completion aggregation, and
inter-cluster ordering. Atomics remain deferred until ordinary cross-warp
visibility and barrier ordering are fully closed. If any experiment is
activated, it receives a frozen architectural contract, independent reference,
new differential/formal/coverage evidence, and fresh ASIC PPA before being
described as supported.
