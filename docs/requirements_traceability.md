# Requirements traceability

This matrix connects the normative contracts in `docs/architecture.md` to their
implementation and verification evidence. `Planned` means the contract is frozen
but the named artifact does not yet exist. A requirement cannot close with a
blank evidence category; justified exclusions must be written explicitly.

| Requirement | RTL | Directed test | Assertion/formal | Coverage | Status |
|---|---|---|---|---|---|
| Completion commits exactly once or is explicitly cancelled | Completion fabric | Completion collision/cancellation test | Queue conservation and exactly-once properties | Commit/cancel reason crosses | Planned |
| Round-robin scheduler services a continuously eligible warp within four accepted grants | `rtl/control/round_robin_arbiter.sv`, `rtl/core/simt_core.sv` | `tb/unit/tb_round_robin_arbiter.sv`, `tb/integration/tb_four_warp_core.sv` | One-hot, requested-grant, and stalled-stability assertions; bounded formal pending | All four warps issue and retire; ready-count bins pending | Partial: integrated four-warp fairness and backpressure verified |
| Instruction fetch uses one shared SRAM-compatible port and stable per-warp buffers | `rtl/frontend/warp_instruction_frontend.sv`, `rtl/core/simt_core.sv` | `tb/unit/tb_warp_instruction_frontend.sv`, all core integration tests | One-hot/request validity, buffer PC coherence, and core request-bound assertions | Four buffer fills, prolonged stalls, refill, redirect, flush | Verified at directed/integration level; macro qualification and random stalls remain |
| Four-warp architectural behavior agrees with an independent reference | `model/emulator/multi_warp_emulator.cpp`, `rtl/core/simt_core.sv` | Directed arithmetic/divergence regressions and `four_warp_differential_test` | Unique epoch/warp/sequence trace keys; model/RTL first-mismatch comparator; UVM sequence-continuity scoreboard | 48 clear/relaunch arithmetic and 44 divergence events; UVM smoke covers 24 commits | Partial: arithmetic, multiplier dependencies, WID, divergence, and drained relaunch agree; mid-flight cancellation/memory remain |
| Round-robin writeback services a continuously nonempty source within three accepted commits | `rtl/execute/completion_arbiter.sv` | `tb/unit/tb_completion_arbiter.sv` | Shared arbiter protocol assertions; bounded formal pending | Source × collision × wait bins pending | Partial: three-source collision and stalls verified |
| GPR pending state sets only on accepted issue and clears only on matching commit | `rtl/control/dependency_scoreboard.sv` | `tb/unit/tb_dependency_scoreboard.sv` | Issue-ready assertion; exhaustive matching properties pending | Opcode × dependency pending | Partial: component RAW/WAW and tag matching verified |
| Predicate pending state has no forwarding and clears only on matching commit | Scoreboard and predicate register file | Scoreboard RAW/WAW plus register-file no-forwarding tests | Issue-ready and committed-state checks; exhaustive formal pending | Predicate producer × consumer pending | Partial: component behavior verified |
| Stale epochs have no architectural or memory side effects | `rtl/execute/architectural_writeback.sv`; remaining commit points planned | `tb/unit/tb_alu_completion_writeback.sv` | Writeback stale-side-effect assertions; memory properties pending | Source × stale cancellation pending | Partial: ALU writeback verified |
| Epoch reuse is permitted only after full quiescence | Epoch/quiescence controller | Clear, drain, wrap-directed test | Quiescence completeness | Quiescence blocker × launch | Planned |
| Fatal faults immediately block issue/commit and use a dedicated sticky path | `rtl/control/fatal_fault_controller.sv` and commit gating | ALU priority and single-warp lifecycle fault tests | Sticky-fault and side-effect assertions; global formal pending | Fault class × outstanding source pending | Partial: single-warp fault path verified |
| Stores within one warp instruction execute in ascending lane order | Memory controllers | Same-bank and same-address store tests | Monotonic service-lane property | Participation mask × conflict degree | Planned |
| A younger same-warp load observes the completed older store | Warp memory serialization | Load-after-store tests | No younger allocation before store commit | Space × alias pattern | Planned |
| Barrier release waits for all required warps and older memory completion | Barrier controller | Four-warp reduction and missing-warp tests | Barrier release preconditions | Arrival order × pending memory | Planned |
| Two-entry completion queues never overwrite, duplicate, or lose payloads | `rtl/execute/completion_queue.sv`, ALU and multiplier instances | `tb/unit/tb_completion_queue.sv`, `tb/unit/tb_vector_multiplier_pipeline.sv` | Occupancy, valid-tag, pipeline and queue stability assertions; conservation pending formal | Source × occupancy transition pending | Partial: ALU and multiplier queues verified |
| Four memory trackers are system-wide with at most one per warp | Tracker allocator | Fifth-operation and same-warp rejection tests | Allocation uniqueness and capacity | Occupancy × requesting warp | Planned |
| Instruction writes while busy are suppressed and fault deterministically | Core programming gate and fatal controller; Wishbone path planned | `tb/integration/tb_single_warp_lifecycle.sv` | SRAM collision assertion; bus properties pending | Bus state × busy write pending | Partial: core behavior verified |
| GPR replicas remain consistent after every accepted masked write | Vector register file | Full and partial-mask write tests | Replica consistency assertions | Warp × register × lane mask | Verified at component level |
| Predicate reads expose committed state only | Predicate register file | No-forwarding test | Committed-state read checks | Address × masked write | Verified at component level |
| Same-cycle events obey reset, clear, fatal, commit, then progress priority | Global control and commit gating | Pairwise event-collision tests | Lower-priority side-effect suppression | Higher event × lower event | Planned |
| Vector memory faults are instruction-atomic | Memory validation front end | One-invalid-lane load/store tests | No request before all-lane validation | Space × lane × fault type | Planned |
| Kernel done requires all warps exited and complete machine drain | `rtl/core/simt_core.sv` | `tb/integration/tb_four_warp_core.sv` and lifecycle integration tests | Drain precondition checks; exhaustive formal pending | ALU/multiplier drain exercised; memory blockers pending | Partial: four-warp ALU/multiplier drain verified |
| EXIT deactivates only its effective lane mask | Single-warp lane-exit logic complete; divergent controller planned | Full-mask and predicated partial-mask EXIT tests | Deferred-path properties pending | Exit mask × stack state pending | Partial: nondivergent lane exit verified |
| Divergent branches execute taken and deferred masks before reconvergence | `rtl/core/simt_core.sv` per-warp SIMT stacks | `tb/integration/tb_four_warp_divergence.sv`; emulator trace comparison | Stack-depth, stability, and fault-suppression assertions; bounded engine run pending | Taken/deferred, depth-two nested, four-warp simultaneous, overflow and underflow | Verified at directed/integration level; bounded proof remains in pre-memory gate |
| Sequence matching uses 16-bit sequence plus epoch and warp | Issue tags and all delayed paths | Wrap-near-boundary tag test | No mismatched scoreboard clear/commit | Source × tag fields | Planned |
| Architectural counters wrap at 64 bits and diagnostic counters saturate at 32 bits | Performance counters | Boundary and saturation tests | Width/update/saturation properties | Counter class × boundary | Planned |
| Debug uses a bounded coherent snapshot without a full GPR mux | Debug snapshot unit | Live and fault snapshot tests | Snapshot stability and field coherence | Trigger × captured structure | Planned |
| Ungated baseline and any later clock gating preserve behavior and scan visibility | Clock/test control | Functional and scan gating tests | Enable equivalence and gating checks | Mode × enable state | Planned |

The matrix expands as implementation proceeds. Detailed report paths, test names,
property identifiers, coverage percentages, owners, and waiver links replace the
generic artifact names before verification closure.

Before shared-memory RTL begins, the roadmap additionally requires one
authoritative parameterized core, an SRAM-compatible buffered instruction
frontend, a four-warp reference model, early synthesis/floorplanning evidence,
randomized backpressure, selected bounded proofs, and an initial mutation report.
These are architecture-stabilization gates rather than deferred signoff polish.

The optional post-baseline FP32 add/multiply extension has no baseline
traceability credit. If activated, it requires a frozen numerical contract,
independent bit-accurate reference, IEEE edge-case and random differential tests,
pipeline/backpressure assertions, four-source arbitration evidence, and new
area/timing/power reports before it may be described as complete.
