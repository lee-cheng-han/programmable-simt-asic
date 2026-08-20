#!/usr/bin/env sh
set -eu

command -v yosys >/dev/null 2>&1 || {
  echo 'yosys not found' >&2
  exit 2
}

mkdir -p build/formal

run_proof() {
  name=$1
  top=$2
  sources=$3
  depth=$4
  parameter_command=${5:-}
  log="build/formal/${name}.log"
  # Source splitting is intentional: each list is repository-controlled.
  # shellcheck disable=SC2086
  yosys -ql "$log" -p "read_verilog -formal -sv -DSYNTHESIS $sources; $parameter_command prep -top $top -flatten; async2sync; dffunmap; sat -verify -prove-asserts -set-assumes -seq $depth -tempinduct -show-ports"
  echo "PASS bounded proof $name depth=$depth"
}

run_slang_comb_proof() {
  name=$1
  top=$2
  sources=$3
  log="build/formal/${name}.log"
  # Slang handles package-scoped packed architectural records.
  # Source splitting is intentional: each list is repository-controlled.
  # shellcheck disable=SC2086
  yosys -m slang -ql "$log" -p "read_slang --top $top $sources; prep -top $top -flatten; chformal -lower; memory_map; sat -verify -prove-asserts -show-ports"
  echo "PASS exhaustive combinational proof $name"
}

run_slang_seq_proof() {
  name=$1
  top=$2
  sources=$3
  depth=$4
  log="build/formal/${name}.log"
  # shellcheck disable=SC2086
  yosys -m slang -ql "$log" -p "read_slang --top $top $sources; prep -top $top -flatten; memory_map; async2sync; clk2fflogic; chformal -lower; dffunmap; sat -verify -prove-asserts -set-assumes -seq $depth"
  echo "PASS bounded proof $name depth=$depth"
}

run_proof scheduler_arbiter_4way round_robin_arbiter_formal \
  'rtl/control/round_robin_arbiter.sv formal/round_robin_arbiter_formal.sv' 12
run_proof completion_arbiter_3way round_robin_arbiter_formal \
  'rtl/control/round_robin_arbiter.sv formal/round_robin_arbiter_formal.sv' 12 \
  'chparam -set REQUESTERS 3 round_robin_arbiter_formal;'
run_slang_comb_proof architectural_writeback_safety \
  architectural_writeback_formal \
  'rtl/simt_gpu_pkg.sv rtl/execute/architectural_writeback.sv formal/architectural_writeback_formal.sv'
run_slang_seq_proof banked_vector_memory_safety banked_vector_memory_formal \
  'rtl/simt_gpu_pkg.sv rtl/memory/banked_vector_memory.sv formal/banked_vector_memory_formal.sv' 6
