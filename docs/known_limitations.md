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
warp. Its storage array is still behavioral until a qualified open-PDK SRAM macro
and all required physical/timing views are selected. General/shared memory
trackers, bank replay, barriers, Wishbone, DFT, bounded formal runs, and physical
implementation are not yet integrated.

The current performance numbers are RTL cycle measurements for a small arithmetic
throughput workload, not post-synthesis frequency or silicon results. Assembly
memory images are simple text fixtures rather than an ELF ABI. The older
one-entry writeback component remains test history and is not the architectural
commit path.

The UVM 1.2 environment runs with XSim 2026.1 on the current host. Directed,
legal constrained-random, and randomized execution/writeback-backpressure tests
produce model-matched traces and retain per-seed coverage databases. Coverage
Structured shallow and nested control flow passes differential testing with one
through four resident warps. Coverage database merging and numerical closure,
randomized fault recovery, bounded proofs, and mutation results are not yet claimed.
