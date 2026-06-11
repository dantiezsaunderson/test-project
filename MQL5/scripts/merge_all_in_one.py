#!/usr/bin/env python3
"""Merge RLVR Include modules + EA into one compilable .mq5 file."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

MODULE_ORDER = [
    "Include/RLVR/Types.mqh",
    "Include/RLVR/Config.mqh",
    "Include/RLVR/AtrUtils.mqh",
    "Include/RLVR/Telemetry.mqh",
    "Include/RLVR/TradeUtils.mqh",
    "Include/RLVR/RiskManager.mqh",
    "Include/RLVR/BasketManager.mqh",
    "Include/RLVR/SweepDetector.mqh",
    "Include/RLVR/ReclaimDetector.mqh",
    "Include/RLVR/Invalidation.mqh",
    "Include/RLVR/EntryEngine.mqh",
    "Include/RLVR/RecoveryEngine.mqh",
    "Include/RLVR/ExitManager.mqh",
    "Include/RLVR/AntiBlowup.mqh",
    "Include/RLVR/RegimeFilter.mqh",
    "Include/RLVR/LevelsEngine.mqh",
    "Include/RLVR/StateMachine.mqh",
]

SKIP_INCLUDE = re.compile(
    r'#include\s+(<Trade/Trade\.mqh>|"[^"]+"|<RLVR/[^>]+>)'
)


def strip_mqh_module(text: str) -> str:
    lines = text.splitlines()
    out: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("#ifndef __RLVR_"):
            i += 1
            if i < len(lines) and lines[i].startswith("#define __RLVR_"):
                i += 1
            continue
        if SKIP_INCLUDE.match(line.strip()):
            i += 1
            continue
        if line.strip() == "#endif" and i >= len(lines) - 2:
            i += 1
            continue
        out.append(line)
        i += 1
    while out and out[-1].strip() in ("", "#endif"):
        out.pop()
    return "\n".join(out)


def extract_ea_body(ea_text: str) -> str:
    """Keep inputs, globals, and event handlers; drop #property and RLVR includes."""
    out: list[str] = []
    for line in ea_text.splitlines():
        stripped = line.strip()
        if stripped.startswith("#property"):
            continue
        if stripped.startswith("#include"):
            continue
        out.append(line)
    return "\n".join(out).strip() + "\n"


def main() -> None:
    parts: list[str] = [
        "//+------------------------------------------------------------------+",
        "//| RLVR_AllInOne.mq5 — single-file RLVR (run merge_all_in_one.py)   |",
        "//| Compile THIS file only — no Include/RLVR folder required.        |",
        "//+------------------------------------------------------------------+",
        '#property copyright "RLVR"',
        '#property version   "2.01"',
        "#property strict",
        "",
        "#include <Trade/Trade.mqh>",
        "",
        "//+------------------------------------------------------------------+",
        "//| MERGED MODULES",
        "//+------------------------------------------------------------------+",
        "",
    ]

    for rel in MODULE_ORDER:
        path = ROOT / rel
        name = Path(rel).stem
        parts.append(f"// ===== BEGIN {name} =====")
        parts.append(strip_mqh_module(path.read_text(encoding="utf-8")))
        parts.append(f"// ===== END {name} =====")
        parts.append("")

    ea_path = ROOT / "Experts/RLVR/RLVR_EA.mq5"
    parts.append("//+------------------------------------------------------------------+")
    parts.append("//| EA ENTRY POINT")
    parts.append("//+------------------------------------------------------------------+")
    parts.append(extract_ea_body(ea_path.read_text(encoding="utf-8")))

    out_path = ROOT / "Experts/RLVR/RLVR_AllInOne.mq5"
    out_path.write_text("\n".join(parts), encoding="utf-8")
    print(f"Generated {out_path} ({out_path.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
