# Memory verification closure

The integrated memory subsystem has reproducible directed, differential,
formal, mutation, synthesis, and placement evidence. The licensed release
matrix passes under XSim 2026.1.

| Gate | Result |
|---|---|
| Bank engine, tracker, fault, barrier, reduction, and architectural trace regression | Pass |
| Behavioral/IHP SRAM adapter equivalence | 5/5 checks pass |
| Bank-engine bounded formal target | Pass to depth 6 |
| Complete formal suite | Four targets pass |
| Mutation campaign | 13/13 detected; zero survivors; zero invalid |
| Pairwise fatal-source priority | 15 source pairs plus reset/clear/sticky cases pass |
| Generic and mapped synthesis | Pass; mapped netlist retains 17 SRAM macros |
| Integrated trial placement | 183,852 movable cells and 17 macros; zero failures |
| Portable coverage from executed seeds | 51/51 approved bins (100.0%) |
| Memory UVM compile and elaboration | Pass under XSim 2026.1 |
| Memory UVM runtime and trace comparison | 10/10 runs pass with zero UVM errors and model-matched traces |

The release matrix covers `memory_differential_test` and
`constrained_random_memory_differential_test` at seeds 1 through 5. Reproduce it
with:

```sh
make uvm-regression UVM_TEST="memory_differential_test constrained_random_memory_differential_test" UVM_SEEDS="1 2 3 4 5"
make coverage-closure
```

All ten runs produce model-matched traces with zero UVM errors, and the strict
coverage gate reports 51/51. Memory differential verification is released.
