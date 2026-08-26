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
SIMT stacks, epoch/warp/sequence-keyed arithmetic, divergence, bank-independent
general/shared memory, deterministic lane stores, and full-warp barriers. It does
not model cycle-accurate bank replay, completion-queue arbitration, or mid-flight
epoch cancellation. The core uses one shared instruction port with
round-robin arbitration, a tagged in-flight response, and one stable buffer per
warp. Its storage array remains behavioral until the selected macro adapter is
integrated. IHP SG13G2 SRAM physical, simulation, and three-corner timing views
are machine-checked, and a macro-only trial floorplan passes; integrated mapped
timing, PDN, and routing are not yet evidence. The RTL now has 4 KiB general and
2 KiB shared eight-bank memories behind behavioral/IHP-selectable adapters, four memory trackers, bank replay,
broadcast loads, full-warp barriers, and a passing four-warp shared reduction.
Missing-warp barriers raise a parameterized architectural deadlock fault in RTL
and the multi-warp model; the ASIC Wishbone path now exposes launch/programming,
status, fault, and counters, while the bounded debug snapshot remains pending.
The qualified data-SRAM bank adapter is implemented, equivalence-tested, and
integrated into all sixteen vector banks. Mapped synthesis retains all 17 SRAM
macros and trial placement is legal. Wishbone control, synchronized reset, test
ownership, scan anchors, functional/scan SDC, and a minimal UPF are integrated.
Scan insertion/ATPG, SRAM BIST, routed timing, PDN, and signoff are not yet
complete. A six-cycle bounded bank-engine safety proof now passes; broader
tracker, ordering, and liveness proofs remain open.

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
recovery relaunch. The portable report covers all 51 approved risk bins across
opcode, warp, resident-warp count, completion source, mask class,
execution/writeback stalls, and memory opcode/kind/space. Four bounded/exhaustive component proofs
pass, and the expanded mutation suite detects 13/13 injected defects with no
survivors or invalid mutants. Both memory differential tests pass seeds 1
through 5 under XSim 2026.1 with model-matched traces and zero UVM errors;
portable coverage is 51/51. Tool-inserted DFT, routed timing, and signoff remain
outside the current release boundary.
