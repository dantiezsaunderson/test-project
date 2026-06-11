"""Post-reclaim invalidation — formal spec Section 9."""

from __future__ import annotations

from .config import StructureConfig
from .models import Bar, LevelState, LiquidityLevel, ReplayEvent


def detect_invalidation_on_bar_close(
    level: LiquidityLevel,
    bar: Bar,
    atr_m5: float,
    config: StructureConfig,
) -> ReplayEvent | None:
    if level.state != LevelState.RECLAIM_CONFIRMED:
        return None
    if level.sweep_extreme is None or level.sweep_side is None:
        return None

    buffer_distance = config.invalidation_buffer_atr * atr_m5
    acceptance_distance = config.acceptance_distance_atr * atr_m5
    level_price = level.price

    if level.sweep_side == "above":
        if bar.close > level.sweep_extreme + buffer_distance:
            level.state = LevelState.EXPIRED
            return ReplayEvent(
                timestamp=bar.time,
                event_type="INVALIDATION",
                level_id=level.level_id,
                level_price=level_price,
                bar_index=bar.index,
                atr_m5=atr_m5,
                sweep_extreme=level.sweep_extreme,
                message="INV-1: close beyond sweep extreme + buffer",
            )
        if bar.close > level_price + acceptance_distance:
            level.state = LevelState.EXPIRED
            return ReplayEvent(
                timestamp=bar.time,
                event_type="INVALIDATION",
                level_id=level.level_id,
                level_price=level_price,
                bar_index=bar.index,
                atr_m5=atr_m5,
                sweep_extreme=level.sweep_extreme,
                message="INV-6: re-acceptance beyond level",
            )
    else:
        if bar.close < level.sweep_extreme - buffer_distance:
            level.state = LevelState.EXPIRED
            return ReplayEvent(
                timestamp=bar.time,
                event_type="INVALIDATION",
                level_id=level.level_id,
                level_price=level_price,
                bar_index=bar.index,
                atr_m5=atr_m5,
                sweep_extreme=level.sweep_extreme,
                message="INV-2: close beyond sweep extreme + buffer",
            )
        if bar.close < level_price - acceptance_distance:
            level.state = LevelState.EXPIRED
            return ReplayEvent(
                timestamp=bar.time,
                event_type="INVALIDATION",
                level_id=level.level_id,
                level_price=level_price,
                bar_index=bar.index,
                atr_m5=atr_m5,
                sweep_extreme=level.sweep_extreme,
                message="INV-6: re-acceptance beyond level",
            )

    return None
