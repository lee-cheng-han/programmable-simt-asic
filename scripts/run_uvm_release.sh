#!/usr/bin/env sh
set -eu

: "${XSIM_RELEASE:?set XSIM_RELEASE to the XSim version being qualified}"

# Freeze the one-, two-, and three-resident-warp structured-control samples.
# Simulator-specific randomization may choose different warp counts for the
# same seed; explicit overrides make the approved coverage matrix portable.
for test_name in \
  constrained_random_differential_test \
  backpressure_differential_test \
  fetch_backpressure_differential_test \
  structured_control_differential_test \
  isa_coverage_differential_test \
  fault_clear_relaunch_differential_test \
  midflight_clear_relaunch_differential_test; do
  for seed in 1 2 3; do
    warp_count=0
    if [ "$test_name" = structured_control_differential_test ]; then
      case "$seed" in
        1) warp_count=1 ;;
        2) warp_count=3 ;;
        3) warp_count=2 ;;
      esac
    fi
    echo "UVM release test=$test_name seed=$seed warps=$warp_count"
    UVM_TEST="$test_name" SEED="$seed" WARP_COUNT="$warp_count" \
      scripts/run_uvm_differential.sh
  done
done

for test_name in memory_differential_test \
                 constrained_random_memory_differential_test; do
  for seed in 1 2 3 4 5; do
    echo "UVM release test=$test_name seed=$seed"
    UVM_TEST="$test_name" SEED="$seed" WARP_COUNT=0 \
      scripts/run_uvm_differential.sh
  done
done
