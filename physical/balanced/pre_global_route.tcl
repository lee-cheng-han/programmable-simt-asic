# OpenROAD DFT emits constant tie nets with POWER/GROUND signal metadata even
# though they are routed logic nets driven by tie cells. TritonRoute requires
# ordinary signal nets here; actual VDD/VSS remain special nets from the PDN.
set block [ord::get_db_block]
foreach {name type} {one_ SIGNAL zero_ SIGNAL} {
  set net [$block findNet $name]
  if {$net ne "NULL"} {
    $net setSigType $type
  }
}
