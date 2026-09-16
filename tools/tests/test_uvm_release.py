"""Focused checks for the version-specific differential release gate."""

import importlib.util
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "check_uvm_release.py"
SPEC = importlib.util.spec_from_file_location("check_uvm_release", SCRIPT)
RELEASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RELEASE)


class UvmReleaseCheckTest(unittest.TestCase):
    def test_release_matrix_is_fixed_at_31_runs(self):
        cases = RELEASE.expected_cases()
        self.assertEqual(len(cases), 31)
        self.assertEqual(len(set(cases)), 31)

    def test_complete_run_passes_and_wrong_version_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            run = Path(temp)
            for name in (
                "xvlog.log", "portable_coverage.txt", "program.hex",
                "program.bin", "model.trace", "uvm_four_warp.trace", "run.cfg",
            ):
                (run / name).write_text("sample\n", encoding="utf-8")
            (run / "xelab.log").write_text("Vivado Simulator v2025.2\n",
                                             encoding="utf-8")
            (run / "comparison.txt").write_text(
                "PASS architectural trace comparison events=24\n",
                encoding="utf-8",
            )
            (run / "xsim.log").write_text(
                "Running test memory_differential_test...\n"
                "UVM_ERROR : 0\nUVM_FATAL : 0\n$finish called\n",
                encoding="utf-8",
            )
            self.assertEqual(RELEASE.check_run(run, "2025.2",
                                               "memory_differential_test"), [])
            self.assertIn("wrong XSim elaboration release",
                          RELEASE.check_run(run, "2026.1",
                                            "memory_differential_test"))
            (run / "xsim.log").write_text(
                "Running test memory_differential_test...\n"
                "UVM_ERROR : 1\nUVM_FATAL : 0\n$finish called\n",
                encoding="utf-8",
            )
            self.assertIn("nonzero or absent UVM_ERROR summary",
                          RELEASE.check_run(run, "2025.2",
                                            "memory_differential_test"))

    def test_missing_artifact_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            run = Path(temp)
            self.assertIn("missing or empty xsim.log",
                          RELEASE.check_run(run, "2025.2",
                                            "memory_differential_test"))

    def test_structured_control_warp_count_is_frozen(self):
        with tempfile.TemporaryDirectory() as temp:
            run = Path(temp)
            for name in (
                "xvlog.log", "portable_coverage.txt", "program.hex",
                "program.bin", "model.trace", "uvm_four_warp.trace",
            ):
                (run / name).write_text("sample\n", encoding="utf-8")
            (run / "xelab.log").write_text("Vivado Simulator v2025.2\n",
                                             encoding="utf-8")
            (run / "comparison.txt").write_text(
                "PASS architectural trace comparison events=33\n",
                encoding="utf-8",
            )
            (run / "xsim.log").write_text(
                "Running test structured_control_differential_test...\n"
                "UVM_ERROR : 0\nUVM_FATAL : 0\n$finish called\n",
                encoding="utf-8",
            )
            (run / "run.cfg").write_text("4\n", encoding="utf-8")
            self.assertIn("expected 3", RELEASE.check_run(
                run, "2025.2", "structured_control_differential_test", 2)[0])
            (run / "run.cfg").write_text("3\n", encoding="utf-8")
            self.assertEqual(RELEASE.check_run(
                run, "2025.2", "structured_control_differential_test", 2), [])


if __name__ == "__main__":
    unittest.main()
