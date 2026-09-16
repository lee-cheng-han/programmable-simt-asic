"""Synthetic checks for the physical global-route release gate."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/check_balanced_grt.py"
SPEC = importlib.util.spec_from_file_location("check_balanced_grt", SCRIPT)
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


class BalancedGrtCheckTest(unittest.TestCase):
    def test_clean_result_and_congestion_failure(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            for folder in ("logs", "results", "reports"):
                (base / folder).mkdir()
            for name in ("logs/5_1_grt.log", "results/5_1_grt.odb",
                         "results/5_1_grt.sdc", "results/route.guide"):
                (base / name).write_text("result\n", encoding="utf-8")
            (base / "logs/5_1_grt.json").write_text(json.dumps({
                "globalroute__flow__errors__count": 0,
            }), encoding="utf-8")
            (base / "reports/congestion.rpt").write_text(
                "no violations\n", encoding="utf-8")
            self.assertEqual(CHECKER.check_run(base), [])

            (base / "reports/congestion.rpt").write_text(
                "violation type: Horizontal congestion\n", encoding="utf-8")
            self.assertIn("global-route congestion violations remain",
                          CHECKER.check_run(base))

    def test_missing_artifact_and_tool_error_fail(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            self.assertIn("missing or empty results/route.guide",
                          CHECKER.check_run(base))
            for folder in ("logs", "results", "reports"):
                (base / folder).mkdir()
            for name in ("logs/5_1_grt.log", "results/5_1_grt.odb",
                         "results/5_1_grt.sdc", "results/route.guide"):
                (base / name).write_text("result\n", encoding="utf-8")
            (base / "logs/5_1_grt.json").write_text(json.dumps({
                "globalroute__flow__errors__count": 1,
            }), encoding="utf-8")
            (base / "reports/congestion.rpt").write_text("\n", encoding="utf-8")
            self.assertIn("global-route error count is 1, expected 0",
                          CHECKER.check_run(base))


if __name__ == "__main__":
    unittest.main()
