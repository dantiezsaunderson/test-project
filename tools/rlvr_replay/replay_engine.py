"""Bar-by-bar RLVR replay orchestrator."""

from __future__ import annotations

from dataclasses import replace
from typing import Sequence

from .atr import wilder_atr_series
from .config import ReplayConfig
from .invalidation import detect_invalidation_on_bar_close
from .levels import active_levels_at, build_pdh_pdl_levels
from .models import Bar, LevelState, LiquidityLevel, ReplayEvent, ReplaySummary
from .reclaim import detect_reclaim_on_bar_close
from .sweep import (
    detect_sweep_on_bar,
    reclaim_ttl_expired,
    sweep_window_expired,
)


class ReplayEngine:
    def __init__(self, config: ReplayConfig) -> None:
        self.config = config

    def run(
        self,
        bars: Sequence[Bar],
        manual_levels: Sequence[LiquidityLevel] | None = None,
        use_pdh_pdl: bool = True,
    ) -> ReplaySummary:
        if len(bars) < self.config.atr_period + 1:
            raise ValueError(
                f"Need at least {self.config.atr_period + 1} bars for ATR; got {len(bars)}"
            )

        atr_series = wilder_atr_series(bars, self.config.atr_period)
        all_levels: list[LiquidityLevel] = []
        if use_pdh_pdl:
            all_levels.extend(build_pdh_pdl_levels(bars))
        if manual_levels:
            all_levels.extend(manual_levels)

        # Deep copy levels so replay is stateless across runs
        levels = [replace(level) for level in all_levels]
        events: list[ReplayEvent] = []
        summary = ReplaySummary(total_bars=len(bars))

        for bar in bars:
            atr_m5 = atr_series[bar.index]
            if atr_m5 is None:
                continue

            candidates = active_levels_at(
                levels,
                bar.time,
                self.config.levels.level_quality_threshold,
                self.config.levels.max_armed_levels,
            )
            summary.levels_armed = max(summary.levels_armed, len(candidates))

            for level in candidates:
                bar_events = detect_sweep_on_bar(level, bar, atr_m5, self.config.structure)
                for event in bar_events:
                    events.append(event)
                    if event.event_type == "SWEEP_START":
                        summary.sweep_starts += 1
                    elif event.event_type == "SWEEP_TOO_DEEP":
                        summary.sweep_too_deep += 1

                if level.state == LevelState.SWEEP_DETECTED:
                    if sweep_window_expired(
                        level, bar, self.config.structure.sweep_window_bars
                    ):
                        level.state = LevelState.EXPIRED
                        events.append(
                            ReplayEvent(
                                timestamp=bar.time,
                                event_type="SWEEP_TIMEOUT",
                                level_id=level.level_id,
                                level_price=level.price,
                                bar_index=bar.index,
                                atr_m5=atr_m5,
                                sweep_extreme=level.sweep_extreme,
                                message="Sweep window expired without reclaim",
                            )
                        )
                        summary.sweep_timeouts += 1
                        continue

                    if reclaim_ttl_expired(
                        level, bar, self.config.structure.reclaim_ttl_seconds
                    ):
                        level.state = LevelState.EXPIRED
                        events.append(
                            ReplayEvent(
                                timestamp=bar.time,
                                event_type="RECLAIM_TTL_EXPIRED",
                                level_id=level.level_id,
                                level_price=level.price,
                                bar_index=bar.index,
                                atr_m5=atr_m5,
                                sweep_extreme=level.sweep_extreme,
                                message="Reclaim TTL expired",
                            )
                        )
                        summary.reclaim_ttl_expired += 1
                        continue

                    reclaim_event = detect_reclaim_on_bar_close(
                        level, bar, atr_m5, self.config.structure
                    )
                    if reclaim_event:
                        events.append(reclaim_event)
                        summary.reclaims += 1

                if level.state == LevelState.RECLAIM_CONFIRMED:
                    inv_event = detect_invalidation_on_bar_close(
                        level, bar, atr_m5, self.config.structure
                    )
                    if inv_event:
                        events.append(inv_event)
                        summary.invalidations += 1

        summary.events = events
        return summary
