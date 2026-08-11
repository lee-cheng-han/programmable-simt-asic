#!/usr/bin/env sh
set -eu

if [ "$#" -eq 0 ]; then
  set -- 1 2 3 4 5
fi
if [ -n "${UVM_TEST:-}" ]; then
  tests=$UVM_TEST
else
  tests="constrained_random_differential_test backpressure_differential_test"
fi
for test_name in $tests; do
  for seed in "$@"; do
    echo "UVM regression test=$test_name seed=$seed"
    UVM_TEST="$test_name" SEED="$seed" scripts/run_uvm_differential.sh
  done
done
