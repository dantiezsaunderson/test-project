"""Simplified levels engine for CSV replay (PDH/PDL + manual levels)."""

from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timedelta
from typing import Sequence

from .models import Bar, LevelState, LevelType, LiquidityLevel


def _day_key(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%d")


def build_pdh_pdl_levels(
    bars: Sequence[Bar],
    quality_score: float = 0.85,
) -> list[LiquidityLevel]:
    """
    Compute prior-day high/low levels.

    PDH/PDL for day D are derived from all M5 bars on day D-1.
    Level becomes active at first bar of day D.
    """
    by_day: dict[str, list[Bar]] = defaultdict(list)
    for bar in bars:
        by_day[_day_key(bar.time)].append(bar)

    sorted_days = sorted(by_day)
    levels: list[LiquidityLevel] = []

    for day_index in range(1, len(sorted_days)):
        prior_day = sorted_days[day_index - 1]
        current_day = sorted_days[day_index]
        prior_bars = by_day[prior_day]
        day_high = max(bar.high for bar in prior_bars)
        day_low = min(bar.low for bar in prior_bars)
        active_from = by_day[current_day][0].time
        expires_at = active_from + timedelta(days=1)

        levels.append(
            LiquidityLevel(
                level_id=f"PDH_{prior_day}",
                level_type=LevelType.PDH,
                price=day_high,
                quality_score=quality_score,
                created_at=active_from,
                expires_at=expires_at,
                state=LevelState.ARMED,
            )
        )
        levels.append(
            LiquidityLevel(
                level_id=f"PDL_{prior_day}",
                level_type=LevelType.PDL,
                price=day_low,
                quality_score=quality_score,
                created_at=active_from,
                expires_at=expires_at,
                state=LevelState.ARMED,
            )
        )

    return levels


def active_levels_at(
    levels: Sequence[LiquidityLevel],
    bar_time: datetime,
    quality_threshold: float,
    max_levels: int,
) -> list[LiquidityLevel]:
    """Return armed levels valid at bar_time, capped by quality and count."""
    active = [
        level
        for level in levels
        if (
            level.state
            in {
                LevelState.ARMED,
                LevelState.SWEEP_DETECTED,
                LevelState.RECLAIM_CONFIRMED,
            }
            and level.created_at <= bar_time < level.expires_at
            and level.quality_score >= quality_threshold
        )
    ]
    active.sort(key=lambda item: (-item.quality_score, item.created_at))
    return active[:max_levels]
