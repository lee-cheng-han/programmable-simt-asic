# Mutation report

The deterministic suite injects thirteen independent RTL defects into temporary
build copies and runs the focused test that owns each contract. The canonical RTL
is never modified. `make mutation-smoke` reproduces the experiment and retains
compile and simulation logs under `build/mutation/`.

| Injected defect | Expected detector | Result |
|---|---|---|
| Scheduler priority does not advance after an accepted grant | Round-robin arbiter sequence | Detected |
| GPR scoreboard clear ignores kernel epoch ownership | Dependency-scoreboard wrong-epoch test | Detected |
| Completion FIFO head pointer does not advance | Completion-queue ordering test | Detected |
| Multiplier computes addition instead of multiplication | Multiplier datapath test | Detected |
| Full completion FIFO incorrectly accepts without a simultaneous dequeue | Completion-queue capacity and exchange test | Detected |
| Stale-epoch completion is allowed to commit | ALU completion/writeback lifecycle test | Detected |
| Divergent branch saves the taken mask as deferred work | Four-warp divergence differential test | Detected |
| Kernel completion ignores pipeline drainage | Four-warp completion/counter test | Detected |
| Full SIMT stack wraps instead of faulting | Divergence overflow test | Detected |
| Inactive lanes are included in address validation | Bank-engine inactive-lane fault test | Detected |
| Faulting memory requests bypass full prevalidation | Bank-engine atomic-fault test | Detected |
| Bank selection uses the wrong address bits | Distinct-bank one-cycle service test | Detected |
| A warp can allocate a second outstanding memory tracker | Memory-subsystem same-warp rejection test | Detected |

Injected: 13; detected: 13; survived: 0; invalid: 0. The first nine cases retain
the closed pre-memory mutation evidence; the four added cases cover memory
prevalidation, bank mapping, and tracker ownership.
