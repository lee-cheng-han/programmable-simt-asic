#!/usr/bin/env python3
"""Reject broken repository-local Markdown links and stale release claims."""
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
errors=[]
for document in [ROOT/'README.md',*sorted((ROOT/'docs').glob('*.md'))]:
    text=document.read_text(encoding='utf-8')
    for target in re.findall(r'\[[^]]+\]\(([^)]+)\)',text):
        target=target.split('#',1)[0]
        if not target or '://' in target or target.startswith('mailto:'):
            continue
        resolved=(document.parent/target).resolve()
        if ROOT not in resolved.parents and resolved!=ROOT:
            errors.append(f'{document.relative_to(ROOT)}: link escapes repository: {target}')
        elif not resolved.exists():
            errors.append(f'{document.relative_to(ROOT)}: missing link target: {target}')

required_sources={
    'scripts/run_rtl_unit_tests.sh':'rtl/memory/data_sram_bank_adapter.sv',
    'scripts/run_uvm_differential.sh':'rtl/memory/data_sram_bank_adapter.sv',
    'scripts/run_early_synthesis.sh':'rtl/memory/data_sram_bank_adapter.sv',
    'scripts/run_mapped_synthesis.sh':'rtl/memory/data_sram_bank_adapter.sv',
    'scripts/run_bounded_formal.sh':'rtl/memory/data_sram_bank_adapter.sv',
}
for filename,needle in required_sources.items():
    if needle not in (ROOT/filename).read_text(encoding='utf-8'):
        errors.append(f'{filename}: required integrated source missing: {needle}')
if errors:
    raise SystemExit('\n'.join(errors))
print('PASS documentation links and integrated-source contracts')
