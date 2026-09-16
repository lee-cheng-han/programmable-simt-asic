# Balanced ASIC routing trials

The balanced IHP SG13G2 design retains all 17 SRAM macros and has reached
legal placement and CTS. Neither trial below passed global routing; no routed
timing, detailed-route DRC, or GDS signoff is claimed.

| Left SRAM row pitch | Placement strategy | Final global-route congestion | Result |
|---:|---|---:|---|
| 120 µm | Original placement, right-bank routing apron | 7 | Failed; seven local overflow boxes near the left SRAM stack |
| 170 µm | Wider left-bank spacing, same right apron | 84 | Failed; 77 violation boxes after 30 repair iterations |

The 170-µm experiment passed detailed-placement legalization and CTS, with no
pre-route setup violations reported and three hold endpoints repaired. Its
congestion snapshots decreased from 1,732 boxes at iteration 5 to 368 at
iteration 10 and 103 at iteration 15, then rose to 139 at iteration 20; the
final report retained 77 boxes. Most final hotspots are near the right edge
of the left SRAM column, around x=760–810 µm. The wider spacing has therefore
been reverted to the 120-µm baseline.

The flow now sets `GENERATE_ARTIFACTS_ON_FAILURE=0`, so OpenROAD writes a
failure-suffixed database and exits nonzero on congested global routing. The
independent `make asic-grt-check` gate also rejects a missing route guide,
router errors, or any residual congestion report entry. The next physical
change must address local SRAM pin escape/routing capacity and rerun placement,
CTS, and global routing. Pre-route setup/hold estimates are not timing closure.
