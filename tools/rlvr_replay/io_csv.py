"""CSV loaders for M5 bars and manual liquidity levels."""

from __future__ import annotations

import csv
from datetime import datetime
from pathlib import Path

from .models import Bar, LevelType, LiquidityLevel, LevelState


def _parse_datetime(value: str) -> datetime:
    value = value.strip()
    for fmt in (
        "%Y-%m-%d %H:%M:%S",
        "%Y.%m.%d %H:%M:%S",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%d %H:%M",
    ):
        try:
            return datetime.strptime(value, fmt)
        except ValueError:
            continue
    raise ValueError(f"Unsupported datetime format: {value!r}")


def load_m5_csv(path: Path) -> list[Bar]:
    """Load OHLC CSV. Required columns: time/datetime, open, high, low, close."""
    bars: list[Bar] = []
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise ValueError(f"Empty CSV: {path}")

        fields = {name.strip().lower(): name for name in reader.fieldnames}
        time_key = fields.get("time") or fields.get("datetime") or fields.get("date")
        if not time_key:
            raise ValueError("CSV must include time, datetime, or date column")

        for row_index, row in enumerate(reader):
            bar = Bar(
                time=_parse_datetime(row[time_key]),
                open=float(row[fields["open"]]),
                high=float(row[fields["high"]]),
                low=float(row[fields["low"]]),
                close=float(row[fields["close"]]),
                index=row_index,
            )
            bars.append(bar)

    bars.sort(key=lambda item: item.time)
    for index, bar in enumerate(bars):
        bar.index = index
    return bars


def load_levels_csv(path: Path) -> list[LiquidityLevel]:
    """
    Optional manual levels file.

    Columns: level_id, type, price, created_at, expires_at, quality_score
    """
    levels: list[LiquidityLevel] = []
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            levels.append(
                LiquidityLevel(
                    level_id=row["level_id"],
                    level_type=LevelType(row["type"]),
                    price=float(row["price"]),
                    quality_score=float(row.get("quality_score", "0.8")),
                    created_at=_parse_datetime(row["created_at"]),
                    expires_at=_parse_datetime(row["expires_at"]),
                    state=LevelState.ARMED,
                )
            )
    return levels


def write_events_csv(path: Path, events: list) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "timestamp",
        "event_type",
        "level_id",
        "level_price",
        "bar_index",
        "atr_m5",
        "sweep_extreme",
        "void_midpoint",
        "direction",
        "penetration",
        "message",
    ]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for event in events:
            writer.writerow(
                {
                    "timestamp": event.timestamp.isoformat(sep=" "),
                    "event_type": event.event_type,
                    "level_id": event.level_id,
                    "level_price": f"{event.level_price:.5f}",
                    "bar_index": event.bar_index,
                    "atr_m5": f"{event.atr_m5:.5f}" if event.atr_m5 else "",
                    "sweep_extreme": (
                        f"{event.sweep_extreme:.5f}" if event.sweep_extreme is not None else ""
                    ),
                    "void_midpoint": (
                        f"{event.void_midpoint:.5f}" if event.void_midpoint is not None else ""
                    ),
                    "direction": event.direction or "",
                    "penetration": (
                        f"{event.penetration:.5f}" if event.penetration is not None else ""
                    ),
                    "message": event.message,
                }
            )
