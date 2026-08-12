# Known limitations

The authoritative `rtl/core/simt_core.sv` supports one through four resident
warps, independent register/predicate/scoreboard state, round-robin issue,
three-stage multiplication, shared completion arbitration, lane-level exit, and
depth-eight `SSY`/`BRA`/`SYNC` divergence stacks. Directed tests cover nested and
simultaneous four-warp reconvergence, stack faults, drained completion, and
one-warp emulator trace agreement.

The original C++ emulator remains the memory-capable single-warp architectural
model. A separate four-warp model now covers independent warp state,
round-robin issue, GPR dependency stalls, three-cycle multiplier completion,
SIMT stacks, and epoch/warp/sequence-keyed arithmetic, divergence, and drained
clear/relaunch traces. It does not yet model completion-queue arbitration,
mid-flight epoch cancellation, multi-warp memory ordering, or barriers. The core uses one shared instruction port with
round-robin arbitration, a tagged in-flight response, and one stable buffer per
warp. Its storage array remains behavioral until the selected macro adapter is
integrated. IHP SG13G2 SRAM physical, simulation, and three-corner timing views
are machine-checked, and a macro-only trial floorplan passes; integrated mapped
timing, PDN, and routing are not yet evidence. General/shared memory
trackers, bank replay, barriers, Wishbone, DFT, bounded formal runs, and physical
implementation are not yet integrated.

The current performance numbers are RTL cycle measurements for a small arithmetic
throughput workload, not post-synthesis frequency or silicon results. Assembly
memory images are simple text fixtures rather than an ELF ABI. The older
one-entry writeback component remains test history and is not the architectural
commit path.

The UVM 1.2 environment runs with XSim 2026.1 on the current host. Directed,
legal constrained-random, and randomized execution/writeback-backpressure tests
produce model-matched traces and retain portable per-seed coverage manifests. Structured
shallow and nested control flow passes differential testing with one
through four resident warps. A directed class-based test also verifies stack-
underflow side-effect suppression, sticky-fault clear, and an epoch-1 four-warp
recovery relaunch. The portable report covers all 43 approved pre-memory risk
bins across opcode, warp, resident-warp count, completion source, mask class,
and execution/writeback stall state. Three bounded/exhaustive component proofs
pass, and the mutation suite detects 9/9 injected defects with no survivors or
invalid mutants. These results close the pre-memory gate; memory-system behavior,
DFT, routed timing, and signoff are deliberately outside that release boundary.
