#!/usr/bin/env python3
"""Compare Python harness events vs MT5 RLVR_EA telemetry CSV."""

from __future__ import annotations

import argparse
import csv
import sys
from dataclasses import dataclass
from pathlib import Path

from .config import ReplayConfig
from .io_csv import load_levels_csv, load_m5_csv, write_events_csv
from .replay_engine import ReplayEngine


@dataclass(frozen=True)
class NormalizedEvent:
    event_type: str
    level_id: str
    direction: str
    level_price: str

    @classmethod
    def from_row(cls, row: dict[str, str]) -> NormalizedEvent:
        return cls(
            event_type=row.get("event_type", "").strip(),
            level_id=row.get("level_id", "").strip(),
            direction=row.get("direction", "").strip(),
            level_price=row.get("level_price", "").strip(),
        )


def load_events_csv(path: Path) -> list[NormalizedEvent]:
    events: list[NormalizedEvent] = []
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            events.append(NormalizedEvent.from_row(row))
    return events


def run_python_reference(
    m5_csv: Path,
    levels_csv: Path | None,
    no_pdh_pdl: bool,
    output: Path | None,
) -> list[NormalizedEvent]:
    config = ReplayConfig.from_json()
    bars = load_m5_csv(m5_csv)
    manual = load_levels_csv(levels_csv) if levels_csv else None
    summary = ReplayEngine(config).run(
        bars, manual_levels=manual, use_pdh_pdl=not no_pdh_pdl
    )
    if output:
        write_events_csv(output, summary.events)
    return [
        NormalizedEvent(
            event_type=event.event_type,
            level_id=event.level_id,
            direction=event.direction or "",
            level_price=f"{event.level_price:.2f}",
        )
        for event in summary.events
    ]


def compare_sequences(
    reference: list[NormalizedEvent],
    candidate: list[NormalizedEvent],
) -> tuple[bool, list[str]]:
    messages: list[str] = []
    ok = True

    if len(reference) != len(candidate):
        ok = False
        messages.append(
            f"Event count mismatch: reference={len(reference)} candidate={len(candidate)}"
        )

    limit = min(len(reference), len(candidate))
    for index in range(limit):
        ref = reference[index]
        cand = candidate[index]
        if ref != cand:
            ok = False
            messages.append(
                f"Mismatch at index {index}: ref={ref!s} cand={cand!s}"
            )

    if len(reference) > limit:
        for extra in reference[limit:]:
            messages.append(f"Missing in candidate: {extra!s}")
    if len(candidate) > limit:
        for extra in candidate[limit:]:
            messages.append(f"Extra in candidate: {extra!s}")

    if ok:
        messages.append(f"PARITY OK — {len(reference)} events matched")
    return ok, messages


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Compare MT5 RLVR telemetry against Python reference replay."
    )
    parser.add_argument("m5_csv", type=Path, nargs="?", help="M5 CSV for Python reference run")
    parser.add_argument("--mt5-events", type=Path, required=True, help="MT5 RLVR_events.csv")
    parser.add_argument("--python-events", type=Path, help="Precomputed Python events CSV")
    parser.add_argument("--levels-csv", type=Path, help="Manual levels for Python reference")
    parser.add_argument("--no-pdh-pdl", action="store_true")
    parser.add_argument("--write-python", type=Path, help="Write Python reference events to path")

    args = parser.parse_args(argv)

    if not args.mt5_events.exists():
        print(f"Error: MT5 events not found: {args.mt5_events}", file=sys.stderr)
        return 1

    if args.python_events and args.python_events.exists():
        reference = load_events_csv(args.python_events)
    elif args.m5_csv and args.m5_csv.exists():
        reference = run_python_reference(
            args.m5_csv,
            args.levels_csv,
            args.no_pdh_pdl,
            args.write_python,
        )
    else:
        print("Provide --python-events or m5_csv for reference generation", file=sys.stderr)
        return 1

    candidate = load_events_csv(args.mt5_events)
    ok, messages = compare_sequences(reference, candidate)

    for message in messages:
        print(message)

    return 0 if ok else 2


if __name__ == "__main__":
    raise SystemExit(main())
