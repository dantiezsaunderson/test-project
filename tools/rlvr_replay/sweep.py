"""Sweep detector — formal spec Section 7."""

from __future__ import annotations

from typing import Optional

from .config import StructureConfig
from .models import Bar, FadeDirection, LevelState, LiquidityLevel, ReplayEvent


def upside_penetration(bar: Bar, level_price: float) -> float:
    if bar.high <= level_price:
        return 0.0
    return bar.high - level_price


def downside_penetration(bar: Bar, level_price: float) -> float:
    if bar.low >= level_price:
        return 0.0
    return level_price - bar.low


def detect_sweep_on_bar(
    level: LiquidityLevel,
    bar: Bar,
    atr_m5: float,
    config: StructureConfig,
) -> list[ReplayEvent]:
    """
    Process one M5 bar for sweep state transitions.

  Returns zero or more events (start, too deep, extremum update logged only on start).
    """
    events: list[ReplayEvent] = []
    if atr_m5 <= 0:
        return events

    d_min = config.sweep_depth_min_atr * atr_m5
    d_max = config.sweep_depth_max_atr * atr_m5
    level_price = level.price

    if level.state == LevelState.ARMED:
        up = upside_penetration(bar, level_price)
        down = downside_penetration(bar, level_price)

        if up >= d_min and up >= down:
            level.state = LevelState.SWEEP_DETECTED
            level.sweep_side = "above"
            level.sweep_start_time = bar.time
            level.sweep_start_bar_index = bar.index
            level.sweep_extreme = bar.high
            events.append(
                ReplayEvent(
                    timestamp=bar.time,
                    event_type="SWEEP_START",
                    level_id=level.level_id,
                    level_price=level_price,
                    bar_index=bar.index,
                    atr_m5=atr_m5,
                    sweep_extreme=level.sweep_extreme,
                    penetration=up,
                    direction=FadeDirection.FADE_SELL.value,
                    message=f"Upside sweep penetration={up:.2f} d_min={d_min:.2f}",
                )
            )
            if up > d_max:
                level.state = LevelState.EXPIRED
                events.append(
                    ReplayEvent(
                        timestamp=bar.time,
                        event_type="SWEEP_TOO_DEEP",
                        level_id=level.level_id,
                        level_price=level_price,
                        bar_index=bar.index,
                        atr_m5=atr_m5,
                        sweep_extreme=level.sweep_extreme,
                        penetration=up,
                        message=f"Penetration {up:.2f} > d_max {d_max:.2f}",
                    )
                )
            return events

        if down >= d_min:
            level.state = LevelState.SWEEP_DETECTED
            level.sweep_side = "below"
            level.sweep_start_time = bar.time
            level.sweep_start_bar_index = bar.index
            level.sweep_extreme = bar.low
            events.append(
                ReplayEvent(
                    timestamp=bar.time,
                    event_type="SWEEP_START",
                    level_id=level.level_id,
                    level_price=level_price,
                    bar_index=bar.index,
                    atr_m5=atr_m5,
                    sweep_extreme=level.sweep_extreme,
                    penetration=down,
                    direction=FadeDirection.FADE_BUY.value,
                    message=f"Downside sweep penetration={down:.2f} d_min={d_min:.2f}",
                )
            )
            if down > d_max:
                level.state = LevelState.EXPIRED
                events.append(
                    ReplayEvent(
                        timestamp=bar.time,
                        event_type="SWEEP_TOO_DEEP",
                        level_id=level.level_id,
                        level_price=level_price,
                        bar_index=bar.index,
                        atr_m5=atr_m5,
                        sweep_extreme=level.sweep_extreme,
                        penetration=down,
                        message=f"Penetration {down:.2f} > d_max {d_max:.2f}",
                    )
                )
            return events

        return events

    if level.state != LevelState.SWEEP_DETECTED:
        return events

    assert level.sweep_side is not None
    assert level.sweep_start_bar_index is not None

    if level.sweep_side == "above":
        level.sweep_extreme = max(level.sweep_extreme or bar.high, bar.high)
        penetration = level.sweep_extreme - level_price
    else:
        level.sweep_extreme = min(level.sweep_extreme or bar.low, bar.low)
        penetration = level_price - level.sweep_extreme

    if penetration > d_max:
        level.state = LevelState.EXPIRED
        events.append(
            ReplayEvent(
                timestamp=bar.time,
                event_type="SWEEP_TOO_DEEP",
                level_id=level.level_id,
                level_price=level_price,
                bar_index=bar.index,
                atr_m5=atr_m5,
                sweep_extreme=level.sweep_extreme,
                penetration=penetration,
                message=f"Penetration {penetration:.2f} > d_max {d_max:.2f}",
            )
        )

    return events


def sweep_window_expired(
    level: LiquidityLevel,
    bar: Bar,
    sweep_window_bars: int,
) -> bool:
    if level.sweep_start_bar_index is None:
        return False
    return (bar.index - level.sweep_start_bar_index) > sweep_window_bars


def reclaim_ttl_expired(
    level: LiquidityLevel,
    bar: Bar,
    reclaim_ttl_seconds: int,
) -> bool:
    if level.sweep_start_time is None:
        return False
    elapsed = (bar.time - level.sweep_start_time).total_seconds()
    return elapsed > reclaim_ttl_seconds
