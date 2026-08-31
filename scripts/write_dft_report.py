#!/usr/bin/env python3
import json,pathlib,sys
cells=int(sys.argv[1]);chains=int(sys.argv[2])
report={"schema":"simt-dft-report-v1","scan_cells":cells,"scan_chains":chains,
 "scan_shift_simulation":"structural-chain generation",
 "atpg":{"status":"not-run","reason":"no supported ATPG engine installed",
         "stuck_at_coverage":None},
 "sram_bist":{"algorithm":"six-pass zero/one/checkerboard",
              "destructive":True,"spaces":["general","shared"]}}
pathlib.Path("build/dft/dft_report.json").write_text(json.dumps(report,indent=2)+"\n")
