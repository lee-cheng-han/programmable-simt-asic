S2R R1, LANEID
MOVI R2, 4
SETP.LT P0, R1, R2
SSY outer_join
@P0 BRA outer_taken
MOVI R4, 90
BRA outer_join
outer_taken:
MOVI R3, 2
SETP.LT P1, R1, R3
SSY inner_join
@P1 BRA inner_taken
MOVI R4, 30
BRA inner_join
inner_taken:
MOVI R4, 10
inner_join:
SYNC
outer_join:
SYNC
EXIT
