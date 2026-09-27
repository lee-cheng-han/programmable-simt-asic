"""Synthetic checks for the MPW-wrapper physical-closure gate."""

import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/check_mpw_physical_close.py"
SPEC = importlib.util.spec_from_file_location("check_mpw_physical_close", SCRIPT)
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


class MpwPhysicalCloseCheckTest(unittest.TestCase):
    REQUIRED = (
        "results/5_3_fillcell.odb",
        "results/5_route.odb",
        "results/5_route.sdc",
        "results/6_1_fill.odb",
        "results/6_1_fill.sdc",
        "logs/6_report.log",
        "results/6_final.odb",
        "results/6_final.def",
        "results/6_final.v",
        "results/6_final.sdc",
        "results/6_final.spef",
        "reports/VDD.rpt",
        "reports/VSS.rpt",
    )

    def populate(self, base: Path, setup: float = 0.1, hold: float = 0.0) -> None:
        for folder in ("logs", "results", "reports"):
            (base / folder).mkdir()
        (base / "results/5_2_route.odb").write_text("input\n", encoding="utf-8")
        for name in self.REQUIRED:
            (base / name).write_text("result\n", encoding="utf-8")
        (base / "logs/6_report.json").write_text(
            json.dumps({
                "finish__flow__errors__count": 0,
                "finish__timing__setup__ws": setup,
                "finish__timing__hold__ws": hold,
            }),
            encoding="utf-8",
        )

    def test_clean_and_negative_slack(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            self.populate(base)
            self.assertEqual(CHECKER.check_run(base), [])
            metrics_path = base / "logs/6_report.json"
            metrics = json.loads(metrics_path.read_text(encoding="utf-8"))
            metrics["finish__timing__hold__ws"] = -0.01
            metrics_path.write_text(json.dumps(metrics), encoding="utf-8")
            self.assertIn(
                "negative extracted hold slack: -0.01", CHECKER.check_run(base)
            )

    def test_stale_and_flow_error(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            self.populate(base)
            metrics_path = base / "logs/6_report.json"
            metrics = json.loads(metrics_path.read_text(encoding="utf-8"))
            metrics["finish__flow__errors__count"] = 2
            metrics_path.write_text(json.dumps(metrics), encoding="utf-8")
            errors = CHECKER.check_run(base)
            self.assertIn("final flow error count is 2, expected 0", errors)

            future = (base / "results/6_final.odb").stat().st_mtime_ns + 1
            os.utime(base / "results/5_2_route.odb", ns=(future, future))
            self.assertIn(
                "stale physical-close artifact results/6_final.odb",
                CHECKER.check_run(base),
            )


if __name__ == "__main__":
    unittest.main()
