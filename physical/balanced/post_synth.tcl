# Scan replacement creates implicit one_/zero_ constant nets.  Materialize
# them after synth ODB dead-logic cleanup so physical optimization can build
# compact, buffered distribution trees.
insert_tiecells sg13g2_tiehi/L_HI -prefix physical_tiehi
insert_tiecells sg13g2_tielo/L_LO -prefix physical_tielo

set block [ord::get_db_block]
foreach name {one_ zero_} {
  set net [$block findNet $name]
  if {$net ne "NULL"} {
    $net setSigType SIGNAL
  }
}
