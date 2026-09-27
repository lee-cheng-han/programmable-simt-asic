# MPW-wrapper physical implementation evidence

The balanced IHP SG13G2 wrapper configuration consumes the complete
`simt_mpw_wrapper` scan netlist rather than treating the inner compute core as
the shuttle boundary. It constrains the 25 MHz user clock, Wishbone inputs and
outputs, interrupts, BIST interface, reset, functional test mode, and scan-only
paths independently from the legacy core physical configuration.

`make mpw-floorplan` passes from a clean wrapper scan artifact. OpenROAD retains
and legally places all 17 qualified SRAM macros in the 3.70 mm × 3.00 mm die,
builds the constant distribution trees, and emits the floorplan OpenDB and SDC.
The reported design area is 4,601,464 square micrometres at 43% utilization.

`make mpw-place` also passes. Timing- and routability-driven global placement,
electrical repair, resizing, and detailed placement produce 228,120 legally
placed standard cells at 45.8% post-resize utilization. The detailed-placement
audit reports zero failed moves, overlaps, wrong-region cells, row/site alignment
errors, edge-spacing errors, or padding errors. Its final HPWL is 16,965,847
micrometres. Placement optimization reports +4.125 ns estimated worst slack at
the 25 MHz target; this is pre-CTS, estimated-parasitic evidence only.

`make mpw-cts` passes from that audited placement database. TritonCTS builds a
three-level tree for 17 SRAM sinks and an eight-to-nine-level tree for 31,518
register sinks, inserting 5,560 clock buffers and six latency-balancing buffers.
Post-CTS legalization places 233,933 cells at 48.2% utilization with no failed
moves. Timing repair reports no setup violations and repairs 66 initial hold
endpoints with 31 delay buffers to +0.006 ns hold WNS under placement-estimated
parasitics.

This is congestion-free global-route evidence, not detailed-route closure. PDN
generation completed,
but the IHP macro geometry produces warnings where some candidate
Metal4-to-TopMetal1 vias cannot be inserted; power connectivity, IR/EM, and
physical verification remain release gates. Detailed routing, extracted MMMC
STA, final antenna repair, DRC/LVS, fill, and final GDS are open.

The first post-CTS route baseline failed with 1,515 overflow units in 1,261
reported boxes, dominated by horizontal signal-pin bands under the R0 SRAMs.
The accepted floorplan rotates every SRAM by 90 degrees and arranges nine banks
along the bottom edge and eight along the top, turning each long signal-pin row
into a vertical edge and preserving a broad central standard-cell channel.

That change closes `make mpw-grt`: FastRoute reaches zero congestion after 12
repair iterations, routes 236,311 nets with 25,748,776 micrometres of wire, and
emits a normal route guide, OpenDB, SDC, and zero-error metrics record. Estimated
global-route timing reports +2.067 ns slack at the 25 MHz target. Antenna repair
reduces 1,362 initial violations to two remaining net/pin violations; these and
detailed-route DRC remain open and are not hidden by the global-route gate.

```sh
make synth-mpw-mapped
make dft-release
make mpw-floorplan
make mpw-place
make mpw-cts
make mpw-grt
```

Generated evidence is under `build/physical/mpw_balanced/`.
