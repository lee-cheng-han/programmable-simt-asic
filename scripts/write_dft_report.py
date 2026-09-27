#!/usr/bin/env python3
import json,pathlib,sys
cells=int(sys.argv[1]);chains=int(sys.argv[2])
audit_path=pathlib.Path("build/dft/scan_audit.json")
audit=json.loads(audit_path.read_text())
if audit["scan_cells"]!=cells or audit["scan_chains"]!=chains:
 raise SystemExit("scan audit does not match insertion counts")
timing_path=pathlib.Path("build/dft/mpw_wrapper_scan_timing.txt")
timing={"status":"not-run"}
if timing_path.is_file():
 values=dict(line.split("=",1) for line in timing_path.read_text().splitlines())
 timing={"status":"measured","mode":"10 MHz pre-placement scan shift",
         "setup_slack_ns":float(values["setup_slack_ns"]),
         "hold_slack_ns":float(values["hold_slack_ns"]),
         "setup_status":values["setup_status"],
         "hold_status":values["hold_status"]}
report={"schema":"simt-dft-report-v1","scan_cells":cells,"scan_chains":chains,
 "scan_structure":{"status":audit["status"],"chain_lengths":audit["chain_lengths"],
                   "all_cells_reachable":audit["all_cells_reachable"],
                   "balanced":audit["balanced"],
                   "max_chain_imbalance":audit["max_chain_imbalance"],
                   "imbalance_limit":audit["imbalance_limit"]},
 "scan_timing":timing,
 "atpg":{"status":"not-run","reason":"no supported ATPG engine installed",
         "stuck_at_coverage":None},
 "sram_bist":{"algorithm":"six-pass zero/one/checkerboard",
              "destructive":True,"spaces":["general","shared"]}}
pathlib.Path("build/dft/dft_report.json").write_text(json.dumps(report,indent=2)+"\n")
