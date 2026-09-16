# XSim 2025.2 differential qualification

The Ubuntu 26.04 WSL host uses Vivado 2025.2's standalone simulation runtime.
The Tcl-mediated `xsim` launcher faults before simulation time zero on this
host; that limitation is isolated from RTL behavior and the standalone path.

The frozen differential matrix consists of seven processor tests at seeds
1–3 and two memory tests at seeds 1–5. Structured-control seeds 1, 2, and 3
explicitly launch one, three, and two resident warps, respectively, so the
coverage result does not depend on simulator-specific random choices.

The completed 2025.2 matrix passed 31/31 architectural first-mismatch trace
comparisons, reported zero UVM errors and fatals, and covered 51/51 approved
portable risk bins (100%). `make xsim-smoke` also compiled the RTL and
elaborated all 18 directed testbench tops with 2025.2. No XSim Tcl-runtime
simulation result is claimed.

```sh
XILINX_VIVADO=/path/to/Vivado/2025.2/Vivado make uvm-release XSIM_RELEASE=2025.2
XILINX_VIVADO=/path/to/Vivado/2025.2/Vivado make xsim-smoke
make uvm-release-check XSIM_RELEASE=2025.2
```

The checker requires the exact 31 retained runs, matching simulator release,
nonempty source/program/trace artifacts, a clean UVM finish, the architectural
trace result, and closed release-specific coverage. The local evidence is in
`build/uvm/release_2025.2.json`,
`build/uvm/portable_coverage_report_2025.2.md`, and
`build/uvm/runs/2025.2/`. These generated files are not committed.
