"""Tests for structural scan-chain auditing."""

import importlib.util
from pathlib import Path
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "check_scan_netlist.py"
SPEC = importlib.util.spec_from_file_location("check_scan_netlist", SCRIPT)
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


def cell(name: str, q: str, scd: str) -> str:
    return (f" sg13g2_sdfrbpq_1 {name} (.Q({q}), .CLK(clk), .RESET_B(rst_n), "
            f".SCD({scd}), .D(d), .SCE(scan_enable_i));\n")


class ScanNetlistTest(unittest.TestCase):
    def test_complete_balanced_chains_pass(self):
        text = (
            cell("a0", "qa0", "scan_in_0") + cell("a1", "qa1", "qa0") +
            cell("b0", "qb0", "scan_in_1") + cell("b1", "qb1", "qb0") +
            "assign scan_out_0 = qa1;\nassign scan_out_1 = qb1;\n"
        )
        result = AUDIT.audit_scan_text(text, expected_chains=2)
        self.assertEqual(result["chain_lengths"], [2, 2])
        self.assertEqual(result["scan_cells"], 4)

    def test_orphan_cell_fails(self):
        text = (cell("a0", "qa0", "scan_in_0") +
                cell("orphan", "qx", "scan_in_0") +
                "assign scan_out_0 = qa0;\n")
        with self.assertRaisesRegex(ValueError, "outside the chains"):
            AUDIT.audit_scan_text(text, expected_chains=1)

    def test_explicit_small_imbalance_limit(self):
        text = (
            cell("a0", "qa0", "scan_in_0") +
            cell("a1", "qa1", "qa0") +
            cell("a2", "qa2", "qa1") +
            cell("b0", "qb0", "scan_in_1") +
            "assign scan_out_0 = qa2;\nassign scan_out_1 = qb0;\n"
        )
        with self.assertRaisesRegex(ValueError, "unbalanced"):
            AUDIT.audit_scan_text(text, expected_chains=2)
        result = AUDIT.audit_scan_text(text, expected_chains=2,
                                       max_imbalance=2)
        self.assertEqual(result["max_chain_imbalance"], 2)
        self.assertEqual(result["imbalance_limit"], 2)

    def test_wrong_input_and_enable_fail(self):
        wrong_input = cell("a0", "qa0", "scan_in_1") + "assign scan_out_0 = qa0;\n"
        with self.assertRaisesRegex(ValueError, "terminates"):
            AUDIT.audit_scan_text(wrong_input, expected_chains=1)
        wrong_enable = cell("a0", "qa0", "scan_in_0").replace(
            "scan_enable_i", "other_enable") + "assign scan_out_0 = qa0;\n"
        with self.assertRaisesRegex(ValueError, "SCE"):
            AUDIT.audit_scan_text(wrong_enable, expected_chains=1)


if __name__ == "__main__":
    unittest.main()
