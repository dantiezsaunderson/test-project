#!/usr/bin/env python3
"""CLI for RLVR M5 CSV replay validation."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .config import ReplayConfig
from .io_csv import load_levels_csv, load_m5_csv, write_events_csv
from .replay_engine import ReplayEngine


def _print_summary(summary) -> None:
    print("=== RLVR Replay Summary ===")
    print(f"Bars processed:      {summary.total_bars}")
    print(f"Peak armed levels:   {summary.levels_armed}")
    print(f"Sweep starts:        {summary.sweep_starts}")
    print(f"Sweep too deep:      {summary.sweep_too_deep}")
    print(f"Sweep timeouts:      {summary.sweep_timeouts}")
    print(f"Reclaims:            {summary.reclaims}")
    print(f"Reclaim TTL expired: {summary.reclaim_ttl_expired}")
    print(f"Invalidations:       {summary.invalidations}")
    print(f"Total events:        {len(summary.events)}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Replay RLVR sweep/reclaim detection on historical M5 CSV bars."
    )
    parser.add_argument(
        "m5_csv",
        type=Path,
        help="M5 OHLC CSV (columns: datetime/time, open, high, low, close)",
    )
    parser.add_argument(
        "--levels-csv",
        type=Path,
        help="Optional manual liquidity levels CSV",
    )
    parser.add_argument(
        "--config",
        type=Path,
        help="Path to PARAMETER-DEFAULTS.json (default: docs/rlvr/PARAMETER-DEFAULTS.json)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Write events to CSV path",
    )
    parser.add_argument(
        "--summary-json",
        type=Path,
        help="Write summary counts to JSON path",
    )
    parser.add_argument(
        "--no-pdh-pdl",
        action="store_true",
        help="Disable auto PDH/PDL levels (use with --levels-csv)",
    )
    parser.add_argument(
        "--no-body-filter",
        action="store_true",
        help="Disable reclaim rejection-body filter",
    )

    args = parser.parse_args(argv)

    if not args.m5_csv.exists():
        print(f"Error: file not found: {args.m5_csv}", file=sys.stderr)
        return 1

    config = ReplayConfig.from_json(args.config)
    if args.no_body_filter:
        structure = config.structure
        config = ReplayConfig(
            structure=type(structure)(
                sweep_depth_min_atr=structure.sweep_depth_min_atr,
                sweep_depth_max_atr=structure.sweep_depth_max_atr,
                sweep_window_bars=structure.sweep_window_bars,
                reclaim_ttl_seconds=structure.reclaim_ttl_seconds,
                reclaim_body_filter=False,
                invalidation_buffer_atr=structure.invalidation_buffer_atr,
                acceptance_distance_atr=structure.acceptance_distance_atr,
            ),
            levels=config.levels,
            atr_period=config.atr_period,
        )

    bars = load_m5_csv(args.m5_csv)
    manual_levels = load_levels_csv(args.levels_csv) if args.levels_csv else None

    engine = ReplayEngine(config)
    summary = engine.run(
        bars,
        manual_levels=manual_levels,
        use_pdh_pdl=not args.no_pdh_pdl,
    )

    _print_summary(summary)

    if args.output:
        write_events_csv(args.output, summary.events)
        print(f"Events written to {args.output}")

    if args.summary_json:
        args.summary_json.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "total_bars": summary.total_bars,
            "levels_armed": summary.levels_armed,
            "sweep_starts": summary.sweep_starts,
            "sweep_too_deep": summary.sweep_too_deep,
            "sweep_timeouts": summary.sweep_timeouts,
            "reclaims": summary.reclaims,
            "reclaim_ttl_expired": summary.reclaim_ttl_expired,
            "invalidations": summary.invalidations,
            "total_events": len(summary.events),
        }
        args.summary_json.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        print(f"Summary written to {args.summary_json}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
