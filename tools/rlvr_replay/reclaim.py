"""Reclaim detector — formal spec Section 8."""

from __future__ import annotations

from .config import StructureConfig
from .models import Bar, FadeDirection, LevelState, LiquidityLevel, ReplayEvent


def _body_ratio(bar: Bar) -> float:
    span = bar.high - bar.low
    if span <= 0:
        return 0.0
    return abs(bar.close - bar.open) / span


def _close_in_outer_third_toward_reclaimed_side(bar: Bar, reclaimed_above: bool) -> bool:
    """Close in outer 30% of range toward reclaimed (inside) side."""
    span = bar.high - bar.low
    if span <= 0:
        return False
    position = (bar.close - bar.low) / span
    if reclaimed_above:
        # Swept above, reclaimed below L — want close in lower 30%
        return position <= 0.30
    # Swept below, reclaimed above L — want close in upper 30%
    return position >= 0.70


def detect_reclaim_on_bar_close(
    level: LiquidityLevel,
    bar: Bar,
    atr_m5: float,
    config: StructureConfig,
) -> ReplayEvent | None:
    """Evaluate reclaim on M5 bar close while in SWEEP_DETECTED."""
    if level.state != LevelState.SWEEP_DETECTED:
        return None
    if level.sweep_side is None or level.sweep_extreme is None:
        return None

    level_price = level.price

    if level.sweep_side == "above":
        reclaimed = bar.close < level_price
        direction = FadeDirection.FADE_SELL
        reclaimed_side_above = True
    else:
        reclaimed = bar.close > level_price
        direction = FadeDirection.FADE_BUY
        reclaimed_side_above = False

    if not reclaimed:
        return None

    if config.reclaim_body_filter:
        if _body_ratio(bar) < 0.30:
            return None
        if not _close_in_outer_third_toward_reclaimed_side(bar, reclaimed_side_above):
            return None

    level.state = LevelState.RECLAIM_CONFIRMED
    level.reclaim_time = bar.time
    level.direction = direction
    level.void_midpoint = (level_price + level.sweep_extreme) / 2.0

    return ReplayEvent(
        timestamp=bar.time,
        event_type="RECLAIM",
        level_id=level.level_id,
        level_price=level_price,
        bar_index=bar.index,
        atr_m5=atr_m5,
        sweep_extreme=level.sweep_extreme,
        void_midpoint=level.void_midpoint,
        direction=direction.value,
        message="M5 close reclaimed inside level",
    )
