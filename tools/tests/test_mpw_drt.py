"""Synthetic checks for the MPW-wrapper detailed-route release gate."""

import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/check_mpw_drt.py"
SPEC = importlib.util.spec_from_file_location("check_mpw_drt", SCRIPT)
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


class MpwDetailedRouteCheckTest(unittest.TestCase):
    def populate(self, base: Path) -> None:
        for folder in ("logs", "results", "reports"):
            (base / folder).mkdir()
        (base / "results/5_1_grt.odb").write_text("input\n", encoding="utf-8")
        for name in (
            "logs/5_2_route.log",
            "results/5_2_route.odb",
            "results/maze.log",
            "reports/5_route_drc.rpt",
            "reports/drt_antennas.log",
        ):
            (base / name).write_text("clean\n", encoding="utf-8")
        (base / "logs/5_2_route.json").write_text(
            json.dumps({"detailedroute__flow__errors__count": 0}),
            encoding="utf-8",
        )

    def test_clean_and_drc_dirty_results(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            self.populate(base)
            self.assertEqual(CHECKER.check_run(base), [])

            (base / "reports/5_route_drc.rpt").write_text(
                "violation type: Short\n", encoding="utf-8"
            )
            self.assertIn(
                "detailed-route DRC violations remain", CHECKER.check_run(base)
            )

    def test_stale_unrouted_and_tool_error_fail(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            self.populate(base)
            future = (base / "results/5_2_route.odb").stat().st_mtime_ns + 1
            os.utime(base / "results/5_1_grt.odb", ns=(future, future))
            errors = CHECKER.check_run(base)
            self.assertIn(
                "stale detailed-route artifact results/5_2_route.odb", errors
            )

            (base / "logs/5_2_route.log").write_text(
                "[ERROR DRT-0001] failure\nDesign has unrouted nets.\n",
                encoding="utf-8",
            )
            errors = CHECKER.check_run(base)
            self.assertIn("detailed router reported an error", errors)
            self.assertIn("detailed router left unrouted nets", errors)


if __name__ == "__main__":
    unittest.main()
