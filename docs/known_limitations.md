# Known limitations

The authoritative `rtl/core/simt_core.sv` supports one through four resident
warps, independent register/predicate/scoreboard state, round-robin issue,
three-stage multiplication, shared completion arbitration, lane-level exit, and
depth-eight `SSY`/`BRA`/`SYNC` divergence stacks. Directed tests cover nested and
simultaneous four-warp reconvergence, stack faults, drained completion, and
one-warp emulator trace agreement.

The C++ emulator remains an architectural one-warp model rather than a cycle-aware
four-warp scheduling model. The integrated instruction storage currently exposes
behavioral combinational lookups and must be replaced by a single-port,
SRAM-compatible buffered frontend. General/shared memory trackers, bank replay,
barriers, Wishbone, selected SRAM macros, DFT, bounded formal runs, and physical
implementation are not yet integrated.

The current performance numbers are RTL cycle measurements for a small arithmetic
throughput workload, not post-synthesis frequency or silicon results. Assembly
memory images are simple text fixtures rather than an ELF ABI. The older
one-entry writeback component remains test history and is not the architectural
commit path.
