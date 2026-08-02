# Reproducible performance results

Results in this file come from checked-in workloads and self-checking RTL
testbenches. They are architectural simulation measurements, not post-layout
frequency, power, or silicon claims.

## Warp-interleaving arithmetic baseline

The `tb/programs/four_warp_arithmetic.s` workload contains six instructions per
warp: warp-ID read, immediate initialization, dependent add, dependent
three-stage multiply, dependent add, and exit. The one-warp and four-warp runs
use identical RTL and instruction streams; only the launch warp count changes.

Run:

```sh
scripts/run_rtl_unit_tests.sh
```

The `tb_four_warp_core` result is:

| Resident warps | Instructions | Cycles | IPC |
|---:|---:|---:|---:|
| 1 | 6 | 22 | 0.272 |
| 4 | 24 | 32 | 0.750 |

Four resident warps improve IPC by approximately 2.76× for this dependency-heavy
stream. These measurements include the shared single-port, buffered instruction
frontend rather than the earlier four-way combinational lookup. The result
demonstrates that round-robin interleaving fills otherwise idle issue and fetch
opportunities while another warp waits for dependent writeback. It does not
claim a 2.76× speedup for one fixed-size kernel: the four-warp run
performs four times as much work and measures throughput scaling.
