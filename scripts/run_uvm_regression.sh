#!/usr/bin/env sh
set -eu

test_name=${UVM_TEST:-constrained_random_differential_test}
if [ "$#" -eq 0 ]; then
  set -- 1 2 3 4 5
fi
for seed in "$@"; do
  echo "UVM regression test=$test_name seed=$seed"
  UVM_TEST="$test_name" SEED="$seed" scripts/run_uvm_differential.sh
done
