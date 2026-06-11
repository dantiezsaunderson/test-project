#!/usr/bin/env python3
"""Generate synthetic M5 CSV fixtures for manual replay demos."""

from __future__ import annotations

import csv
from datetime import datetime, timedelta
from pathlib import Path


def write_bars(path: Path, bars: list[dict]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle, fieldnames=["datetime", "open", "high", "low", "close"]
        )
        writer.writeheader()
        writer.writerows(bars)


def warmup(start: datetime, n: int, base: float = 2396.0) -> list[dict]:
    rows = []
    for i in range(n):
        t = start + timedelta(minutes=5 * i)
        rows.append(
            {
                "datetime": t.strftime("%Y-%m-%d %H:%M:%S"),
                "open": base,
                "high": base + 0.6,
                "low": base - 0.6,
                "close": base,
            }
        )
    return rows


def main() -> None:
    fixtures = Path(__file__).parent
    start = datetime(2025, 6, 10, 8, 0, 0)

    upside = warmup(start, 20)
    upside.append(
        {
            "datetime": (start + timedelta(minutes=100)).strftime("%Y-%m-%d %H:%M:%S"),
            "open": 2399.6,
            "high": 2400.55,
            "low": 2399.85,
            "close": 2400.45,
        }
    )
    upside.append(
        {
            "datetime": (start + timedelta(minutes=105)).strftime("%Y-%m-%d %H:%M:%S"),
            "open": 2400.6,
            "high": 2400.7,
            "low": 2399.2,
            "close": 2399.5,
        }
    )
    write_bars(fixtures / "upside_sweep_reclaim_m5.csv", upside)
    print("Wrote upside_sweep_reclaim_m5.csv")


if __name__ == "__main__":
    main()
