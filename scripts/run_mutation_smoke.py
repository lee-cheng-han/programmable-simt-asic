#!/usr/bin/env python3
"""Run a small, deterministic mutation set against focused RTL tests."""

from __future__ import annotations

import shutil
import subprocess
import os
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build" / "mutation"
CORE_DEPS = (
    "build/simt_isa_pkg.sv", "rtl/simt_gpu_pkg.sv",
    "rtl/frontend/instruction_decoder.sv",
    "rtl/register_file/vector_register_file.sv",
    "rtl/register_file/predicate_register_file.sv",
    "rtl/execute/integer_lane.sv", "rtl/execute/vector_integer_alu.sv",
    "rtl/execute/completion_queue.sv", "rtl/execute/alu_completion_stage.sv",
    "rtl/execute/vector_multiplier_pipeline.sv",
    "rtl/control/round_robin_arbiter.sv", "rtl/execute/completion_arbiter.sv",
    "rtl/execute/architectural_writeback.sv",
    "rtl/control/dependency_scoreboard.sv", "rtl/control/fatal_fault_controller.sv",
    "rtl/memory/banked_vector_memory.sv", "rtl/memory/memory_subsystem.sv",
    "rtl/frontend/instruction_sram_adapter.sv",
    "rtl/frontend/warp_instruction_frontend.sv",
)


@dataclass(frozen=True)
class Mutation:
    name: str
    source: str
    old: str
    new: str
    top: str
    dependencies: tuple[str, ...]
    testbench: str


MUTATIONS = (
    Mutation(
        "scheduler_priority_stuck",
        "rtl/control/round_robin_arbiter.sv",
        "priority_q <= INDEX_W'((int'(grant_index_o) + 1) % REQUESTERS);",
        "priority_q <= grant_index_o;",
        "tb_round_robin_arbiter",
        (),
        "tb/unit/tb_round_robin_arbiter.sv",
    ),
    Mutation(
        "scoreboard_ignores_epoch",
        "rtl/control/dependency_scoreboard.sv",
        "gpr_owner_epoch_q[clear_warp_i][clear_gpr_i] ==\n                        clear_epoch_i &&",
        "1'b1 &&",
        "tb_dependency_scoreboard",
        ("rtl/simt_gpu_pkg.sv",),
        "tb/unit/tb_dependency_scoreboard.sv",
    ),
    Mutation(
        "completion_fifo_head_stuck",
        "rtl/execute/completion_queue.sv",
        "head_q <= head_q + 1'b1;",
        "head_q <= head_q;",
        "tb_completion_queue",
        ("rtl/simt_gpu_pkg.sv",),
        "tb/unit/tb_completion_queue.sv",
    ),
    Mutation(
        "multiplier_product_corrupt",
        "rtl/execute/vector_multiplier_pipeline.sv",
        "src_a_i[lane] * src_b_i[lane]",
        "src_a_i[lane] + src_b_i[lane]",
        "tb_vector_multiplier_pipeline",
        ("rtl/simt_gpu_pkg.sv", "rtl/execute/completion_queue.sv"),
        "tb/unit/tb_vector_multiplier_pipeline.sv",
    ),
    Mutation(
        "completion_fifo_rejects_exchange",
        "rtl/execute/completion_queue.sv",
        "(occupancy_q < QUEUE_DEPTH) || completion_ready_i",
        "1'b1",
        "tb_completion_queue",
        ("rtl/simt_gpu_pkg.sv",),
        "tb/unit/tb_completion_queue.sv",
    ),
    Mutation(
        "stale_writeback_commits",
        "rtl/execute/architectural_writeback.sv",
        "assign epoch_match = completion_i.epoch == current_epoch_i;",
        "assign epoch_match = 1'b1;",
        "tb_alu_completion_writeback",
        ("rtl/simt_gpu_pkg.sv", "rtl/execute/completion_queue.sv",
         "rtl/execute/alu_completion_stage.sv"),
        "tb/unit/tb_alu_completion_writeback.sv",
    ),
    Mutation(
        "branch_deferred_mask_swapped",
        "rtl/core/simt_core.sv",
        "stack_deferred_mask_q[scheduler_warp]\n              [stack_depth_q[scheduler_warp]-1'b1] <=\n                branch_not_taken_mask;",
        "stack_deferred_mask_q[scheduler_warp]\n              [stack_depth_q[scheduler_warp]-1'b1] <=\n                branch_taken_mask;",
        "tb_four_warp_divergence",
        CORE_DEPS,
        "tb/integration/tb_four_warp_divergence.sv",
    ),
    Mutation(
        "kernel_done_ignores_pipeline_drain",
        "rtl/core/simt_core.sv",
        "warp_valid_q == '0 && alu_occupancy == 0 &&\n          mul_occupancy == 0 && mul_stage_valid == '0 && !completion_v &&\n          writeback_occupancy == 0 &&\n          gpr_pending == '0 && pred_pending == '0 && !fatal_now",
        "warp_valid_q == '0 && !fatal_now",
        "tb_four_warp_core",
        CORE_DEPS,
        "tb/integration/tb_four_warp_core.sv",
    ),
    Mutation(
        "simt_stack_overflow_wraps",
        "rtl/core/simt_core.sv",
        "OP_SSY: if (stack_depth_q[scheduler_warp] ==\n                    $clog2(SIMT_STACK_DEPTH+1)'(SIMT_STACK_DEPTH))",
        "OP_SSY: if (stack_depth_q[scheduler_warp] >\n                    $clog2(SIMT_STACK_DEPTH+1)'(SIMT_STACK_DEPTH))",
        "tb_four_warp_divergence",
        CORE_DEPS,
        "tb/integration/tb_four_warp_divergence.sv",
    ),
)


def run_mutation(mutation: Mutation) -> tuple[str, str]:
    case_dir = OUT / mutation.name
    obj_dir = case_dir / "obj"
    case_dir.mkdir(parents=True)
    source_text = (ROOT / mutation.source).read_text(encoding="utf-8")
    if source_text.count(mutation.old) != 1:
        raise RuntimeError(f"{mutation.name}: mutation point is not unique")
    mutant = case_dir / Path(mutation.source).name
    mutant.write_text(source_text.replace(mutation.old, mutation.new), encoding="utf-8")

    command = [
        "verilator", "--binary", "--timing", "--assert", "--Wall",
        "-Wno-UNUSEDPARAM", "-Wno-UNUSEDSIGNAL", "--Mdir", str(obj_dir),
        "--top-module", mutation.top,
        *(str(ROOT / path) for path in mutation.dependencies),
        str(mutant), str(ROOT / mutation.testbench),
    ]
    build = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    (case_dir / "compile.log").write_text(build.stdout + build.stderr, encoding="utf-8")
    if build.returncode != 0:
        return "INVALID", "mutant did not compile"

    simulation = subprocess.run(
        [str(obj_dir / f"V{mutation.top}")], cwd=ROOT, text=True,
        capture_output=True,
    )
    (case_dir / "simulation.log").write_text(
        simulation.stdout + simulation.stderr, encoding="utf-8"
    )
    if simulation.returncode == 0:
        return "SURVIVED", "focused test passed"
    return "DETECTED", "focused test failed"


def main() -> int:
    if shutil.which("verilator") is None:
        raise SystemExit("verilator not found")
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)

    selected = MUTATIONS
    if filter_name := os.environ.get("MUTATION_FILTER"):
        selected = tuple(m for m in MUTATIONS if m.name == filter_name)
        if not selected:
            raise SystemExit(f"unknown MUTATION_FILTER: {filter_name}")
    results = [(mutation, *run_mutation(mutation)) for mutation in selected]
    report = [
        "# Mutation smoke report", "",
        "| Mutation | Result | Detector |", "|---|---|---|",
    ]
    for mutation, result, detector in results:
        report.append(f"| `{mutation.name}` | {result} | {detector} |")
        print(f"{result} {mutation.name}: {detector}")
    detected = sum(result == "DETECTED" for _, result, _ in results)
    invalid = sum(result == "INVALID" for _, result, _ in results)
    survived = sum(result == "SURVIVED" for _, result, _ in results)
    report.extend(("", f"Injected: {len(results)}; detected: {detected}; "
                   f"survived: {survived}; invalid: {invalid}."))
    (OUT / "report.md").write_text("\n".join(report) + "\n", encoding="utf-8")
    return 0 if detected == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
