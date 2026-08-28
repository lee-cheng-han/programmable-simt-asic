# Deterministic bring-up diagnostic: ALU, control flow, both data memories,
# full-warp barrier, and clean lane-level exit. Run with four resident warps.
S2R R1, LANEID
MOVI R2, 4
SHL R3, R1, R2
MOVI R4, 85
ST.G [R3], R4
LD.G R5, [R3]
ST.S [R3], R5
LD.S R6, [R3]
SETP.LT P0, R1, R2
SSY join
@P0 BRA low_half
MOVI R7, 2
BRA join
low_half: MOVI R7, 1
join: SYNC
BAR
ADD R8, R6, R7
EXIT
