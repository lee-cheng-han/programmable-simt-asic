# Tapeout development roadmap

This roadmap is subordinate to `docs/architecture.md`. Release stages are named
by their engineering exit criteria rather than internal sequence numbers.

## Immediate execution order

The following sequence is the active path to shared-memory development. SRAM
macro investigation runs in parallel but must converge before the frontend and
memory contracts freeze.

| Order | Release group | Current state | Required before shared memory |
|---:|---|---|---|
| 1 | Processor architecture foundation | Complete except SRAM feasibility: consolidated core, four-warp execution, nested reconvergence, fatal bounds, and emulator trace agreement pass | Select usable SRAM views and preserve the single authoritative core |
| 2 | Frontend and model stabilization | Not started | SRAM-compatible buffered fetch, four-warp reference model, differential traces, synthesis, reset review, and trial floorplan |
| 3 | Pre-memory verification | Not started | Backpressure stress, bounded proofs, mutation testing, and reproducible reports |
| 4 | Memory system | Blocked by groups above | Begin shared memory, barriers, and scratchpad only after stabilization closes |

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

## Memory system

This group implements both banked address spaces, ordering, replay, barriers,
trackers, and memory completion as one coherent subsystem.

### Shared memory and barriers

Integrate eight shared banks, replay, broadcast, tracker behavior, barriers,
ordering, and deadlock watchdog. Exit requires a passing multi-warp reduction.

### General scratchpad and memory completion

Integrate the 4 KiB eight-bank scratchpad, four trackers, response collector,
memory queue, three-source arbitration, store ordering, load visibility, and
stale-response rejection. A fifth operation and second same-warp operation must
backpressure safely.

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

### Verification closure

Close assertions, bounded formal properties, numerical functional coverage,
long seeded regressions, fairness stress, bug injection, requirements traceability,
and documented limitations. No unexplained mismatch may remain.

### Continuous-integration release gate

Every merge candidate runs canonical ISA-generation consistency, assembler and
disassembler tests, emulator tests, RTL lint, Verilator unit tests, selected
integration programs, architectural trace comparison, documentation-link and
contract-consistency checks, and `git diff --check`. The required set must pass
from a clean checkout with pinned tool versions. XSim, long random regressions,
formal proofs, synthesis, DFT, and physical implementation remain scheduled or
manually triggered jobs whose reports are required at their release gates.

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

### Host and SRAM integration

Add the internal bus, Wishbone wrapper, SRAM macro wrappers and views, host
loading/launch, quiescence/fault reporting, ownership checks, and instruction-write
busy fault.

### MPW harness integration

Deliver a harnessed digital macro: integrate the selected shuttle harness, address
and I/O map, top-level power connections, clocks and resets, Wishbone attachment,
and submission configuration. Close harness timing, full-wrapper DRC/LVS, shuttle
prechecks, and submission-specific repository validation. A standalone pad ring,
package, and board are outside this release target.

### DFT release

Complete scan architecture and simulation, supported ATPG reporting, destructive
SRAM BIST, test ownership, and functional/scan/BIST timing constraints.

## Physical and signoff release

This group takes the frozen, testable macro through implementation, physical
verification, timing/power closure, and the final GDS audit.

### Physical implementation

Complete synthesis, floorplan, macro placement, PDN, placement, CTS, routing,
extraction, timing optimization, antenna repair, fill, re-extraction, and ECO loop.
Every violation enters a tracked loop: root-cause analysis, RTL or physical ECO,
incremental implementation, extraction, STA, equivalence, DRC/LVS, and affected
functional regressions. An ECO closes only when all impacted evidence is rerun.

### Signoff and GDS release

Complete supported MMMC STA, activity-based power, IR/EM review, DRC, LVS,
antenna, density/connectivity, equivalence, GLS/SDF, scan/BIST validation, release
audit, archived reports/checksums, bring-up firmware, and silicon test plan. The
filled GDS is the signoff database. After final fill, rerun extraction, setup/hold
STA, DRC, LVS, antenna, density, power review, and final-netlist consistency; no
pre-fill result may substitute for this exit gate.

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
