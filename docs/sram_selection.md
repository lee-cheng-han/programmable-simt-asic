# SRAM selection and banking contract

The provisional ASIC memory target is the open IHP SG13G2 platform distributed
with OpenROAD-flow-scripts. Selection is based on views that are present and
machine-checkable in that flow; it is not a claim that the final routed macro has
closed timing.

## Selected macros

| Use | Logical organization | Physical organization | Selected macro |
|---|---:|---:|---|
| Instruction memory | 64 × 32-bit baseline | One 64 × 64-bit macro; two instructions per row | `RM_IHPSG13_1P_64x64_c2_bm_bist` |
| General scratchpad | Eight banks, 4 KiB total | Eight 64 × 64-bit macros; one macro per bank | `RM_IHPSG13_1P_64x64_c2_bm_bist` |
| Shared memory | Eight banks, 2 KiB total | Eight 64 × 64-bit macros, lower 32 bits used per row | `RM_IHPSG13_1P_64x64_c2_bm_bist` |

The 256 × 64 variant is also qualified as an instruction-memory growth option,
but it is not the baseline because it increases macro area without adding value
to the current 64-word architectural configuration.

Each selected macro has a synchronous single functional port, a 64-bit bit mask,
dedicated BIST controls, and separate `VDD`, `VDDARRAY`, and `VSS` power pins.
The checked views are LEF, GDS, CDL, Verilog, and Liberty at typical, slow, and
fast corners. `make sram-check` verifies their presence and the required port and
power-pin contract.

## Adapter rules

- Instruction fetch selects the low or high 32-bit half using PC bit zero and
  retains the existing tagged one-cycle response contract.
- Scratchpad bank selection uses word-address bits `[2:0]`; the remaining word
  address selects a row and bit 3 selects the 32-bit half. Byte enables expand
  to the corresponding four bits of the macro's 64-bit bit mask.
- Shared memory uses one physical macro per logical bank. Only the low 32 bits
  are architecturally visible, preserving simultaneous access to all eight banks
  at the cost of unused physical capacity.
- Functional and BIST ownership are mutually exclusive. Scan/test mode must not
  permit both clocks to operate the array concurrently.
- The baseline has no cache, coherence, virtual addressing, or multiported SRAM.

`rtl/memory/data_sram_bank_adapter.sv` implements this contract. Its 128-word
mode packs adjacent logical words into the low/high halves used by a general
scratchpad bank; `LOW_HALF_ONLY` maps a 64-word shared-memory bank directly to
the low half of all 64 macro rows. Both modes provide four byte enables,
one-cycle synchronous reads with stable backpressured responses, and exclusive
functional/BIST ownership. Clear resets interface state but deliberately does
not clear SRAM contents. The unit regression compares the behavioral 128-word
implementation against a pin-accurate functional model of the selected macro.

The 64 × 64 macro outline is 784.48 µm × 64.36 µm. Seventeen baseline instances
therefore contribute approximately 0.859 mm² of raw macro area before halos,
routing channels, logic, and harness overhead. This makes macro placement and
MPW harness capacity an explicit architecture constraint for the trial
floorplan rather than a later implementation detail.

`make trial-floorplan` reads the technology, standard-cell, macro LEF, and
typical Liberty views and places all 17 macros in a 1.70 mm × 0.80 mm die trial.
The generated OpenDB report measures 0.8583 mm² of macro area, 1.2548 mm² of core
area, and 68.4% macro-only utilization with legal nonoverlapping placement.
The macro-only trial establishes the minimum geometry. The integrated mapped
netlist retains the instruction macro plus all 16 real data-bank instances and
contains 183,869 total cells. A separate integrated trial legally places 183,852
movable standard cells and 17 fixed macros in a 3.20 mm × 2.50 mm outline. The
placed instance area is 4.0887 mm² at 53.4% utilization, with zero detailed-
placement failures. This is placement feasibility, not routed timing, PDN,
clock-tree, DRC, or signoff closure.
