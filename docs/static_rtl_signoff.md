# Static ASIC RTL signoff

This release closes the pre-DFT static RTL gate for `simt_asic_top`. The design
has one functional clock domain. All host inputs are synchronous to `clk_i` by
interface contract. External reset is the only asynchronous control: it asserts
the two-stage reset synchronizer asynchronously and reaches all functional state
only through its synchronous release output. Test mode is a static mode strap
that is constrained outside functional timing and holds the core reset.

## Clock and reset inventory

The structural checker enumerates every `always_ff` event control under `rtl/`.
All functional state is positive-edge triggered by `clk`/`clk_i`; the sole
multi-event state process is `reset_synchronizer`. There are no generated,
divided, muxed, negative-edge, or manually gated architectural clocks. The SRAM
functional ports use the core clock. BIST clocks are tied inactive until the DFT
release owns and constrains them.

The external reset path is false-pathed only to the synchronizer assertion pins.
Reset deassertion is synchronous. Assertions and directed tests require reset to
suppress Wishbone responses, launch, clear, and instruction programming. Test
mode independently suppresses those side effects and host acknowledgements.

## Equivalence boundary

The reproducible Yosys-Slang `equiv_opt` proof snapshots the ASIC integration top
immediately before and after flattening synthesis and proves the transformation
by temporal induction. The processor is a compositional cut point represented in
both copies by the same deterministic, pin-sensitive abstraction. This keeps the
proof focused on reset synchronization, host control, mode ownership, and every
core-boundary connection; the processor itself remains owned by its mapped
synthesis, formal, mutation, and differential-verification gates. The proof must
leave zero unproven `$equiv` cells. The asynchronous
assertion flop is transformed with the same `async2sync` abstraction in both
copies because the Yosys SAT engine does not model asynchronous FF cells; true
asynchronous assertion remains covered by the reset-synchronizer test.

This proof is the pre-DFT baseline. Scan replacement/stitching, SRAM BIST
integration, clock-gating insertion, and functional ECOs each require a fresh
equivalence result; none is covered by this baseline report.

## Reproduction and waivers

```sh
make asic-static-signoff
```

There are no functional CDC waivers and no architectural clock-gating waivers.
The reviewed asynchronous-reset assertion path and SRAM black-box abstraction
are intentional methodology boundaries, not ignored violations. Dedicated scan
and BIST clocks are deferred to the DFT release because they do not yet drive
functional RTL.
