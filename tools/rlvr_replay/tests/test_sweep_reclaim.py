"""Unit tests for sweep/reclaim replay harness."""

from __future__ import annotations

import unittest
from datetime import datetime, timedelta
from pathlib import Path

from tools.rlvr_replay.config import ReplayConfig
from tools.rlvr_replay.io_csv import load_levels_csv, load_m5_csv, write_events_csv
from tools.rlvr_replay.models import Bar, LevelState, LevelType, LiquidityLevel
from tools.rlvr_replay.replay_engine import ReplayEngine

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures"


def _make_warmup_bars(
    start: datetime,
    count: int,
    base: float = 2396.0,
    span: float = 1.0,
) -> list[Bar]:
    bars: list[Bar] = []
    for i in range(count):
        t = start + timedelta(minutes=5 * i)
        low = base - span / 2
        high = base + span / 2
        bars.append(
            Bar(
                time=t,
                open=base,
                high=high,
                low=low,
                close=base,
                index=i,
            )
        )
    return bars


def _make_manual_level(
    price: float,
    start: datetime,
    *,
    active_after_bars: int = 20,
) -> LiquidityLevel:
    """Level arms on the sweep bar so warmup range does not sweep L."""
    active_from = start + timedelta(minutes=5 * active_after_bars)
    return LiquidityLevel(
        level_id="TEST_LEVEL",
        level_type=LevelType.MANUAL,
        price=price,
        quality_score=0.9,
        created_at=active_from,
        expires_at=active_from + timedelta(hours=12),
        state=LevelState.ARMED,
    )


class UpsideSweepReclaimTest(unittest.TestCase):
    def test_valid_upside_sweep_and_reclaim(self) -> None:
        start = datetime(2025, 6, 10, 8, 0, 0)
        bars = _make_warmup_bars(start, 20, base=2396.0, span=1.2)
        level_price = 2400.0

        # Sweep bar: pierce above level
        sweep_time = start + timedelta(minutes=5 * 20)
        bars.append(
            Bar(
                time=sweep_time,
                open=2399.6,
                high=2400.55,
                low=2399.85,
                close=2400.45,
                index=20,
            )
        )
        # Reclaim bar: close back below level with rejection body
        reclaim_time = sweep_time + timedelta(minutes=5)
        bars.append(
            Bar(
                time=reclaim_time,
                open=2400.6,
                high=2400.7,
                low=2399.2,
                close=2399.5,
                index=21,
            )
        )

        config = ReplayConfig.from_json()
        engine = ReplayEngine(config)
        summary = engine.run(
            bars,
            manual_levels=[_make_manual_level(level_price, start)],
            use_pdh_pdl=False,
        )

        event_types = [event.event_type for event in summary.events]
        self.assertIn("SWEEP_START", event_types)
        self.assertIn("RECLAIM", event_types)
        self.assertEqual(summary.reclaims, 1)

        reclaim_events = [e for e in summary.events if e.event_type == "RECLAIM"]
        self.assertEqual(reclaim_events[0].direction, "FADE_SELL")
        self.assertIsNotNone(reclaim_events[0].void_midpoint)


class SweepTooDeepTest(unittest.TestCase):
    def test_sweep_disqualified_when_penetration_exceeds_d_max(self) -> None:
        start = datetime(2025, 6, 10, 8, 0, 0)
        bars = _make_warmup_bars(start, 20, base=2396.0, span=1.2)
        level_price = 2400.0

        # Massive sweep — should exceed 0.80 * ATR immediately
        bars.append(
            Bar(
                time=start + timedelta(minutes=100),
                open=2399.0,
                high=2410.0,
                low=2398.8,
                close=2408.0,
                index=20,
            )
        )

        config = ReplayConfig.from_json()
        summary = ReplayEngine(config).run(
            bars,
            manual_levels=[_make_manual_level(level_price, start)],
            use_pdh_pdl=False,
        )

        self.assertGreater(summary.sweep_too_deep, 0)
        self.assertEqual(summary.reclaims, 0)


class SweepTimeoutTest(unittest.TestCase):
    def test_sweep_expires_without_reclaim(self) -> None:
        start = datetime(2025, 6, 10, 8, 0, 0)
        bars = _make_warmup_bars(start, 20, base=2396.0, span=1.2)
        level_price = 2400.0

        base_config = ReplayConfig.from_json()
        structure = base_config.structure
        long_ttl_config = ReplayConfig(
            structure=type(structure)(
                sweep_depth_min_atr=structure.sweep_depth_min_atr,
                sweep_depth_max_atr=structure.sweep_depth_max_atr,
                sweep_window_bars=structure.sweep_window_bars,
                reclaim_ttl_seconds=86400,
                reclaim_body_filter=structure.reclaim_body_filter,
                invalidation_buffer_atr=structure.invalidation_buffer_atr,
                acceptance_distance_atr=structure.acceptance_distance_atr,
            ),
            levels=base_config.levels,
        )

        sweep_index = 20
        bars.append(
            Bar(
                time=start + timedelta(minutes=5 * sweep_index),
                open=2399.9,
                high=2400.28,
                low=2399.88,
                close=2400.2,
                index=sweep_index,
            )
        )

        # Stay above level without extending sweep extreme or reclaiming
        for offset in range(1, 22):
            idx = sweep_index + offset
            bars.append(
                Bar(
                    time=start + timedelta(minutes=5 * idx),
                    open=2400.15,
                    high=2400.26,
                    low=2400.05,
                    close=2400.18,
                    index=idx,
                )
            )

        summary = ReplayEngine(long_ttl_config).run(
            bars,
            manual_levels=[_make_manual_level(level_price, start)],
            use_pdh_pdl=False,
        )

        self.assertGreater(summary.sweep_timeouts, 0)
        self.assertEqual(summary.reclaims, 0)


class DownsideSweepReclaimTest(unittest.TestCase):
    def test_valid_downside_sweep_and_reclaim(self) -> None:
        start = datetime(2025, 6, 10, 8, 0, 0)
        bars = _make_warmup_bars(start, 20, base=2398.0, span=1.2)
        level_price = 2394.0

        bars.append(
            Bar(
                time=start + timedelta(minutes=100),
                open=2394.5,
                high=2394.2,
                low=2393.45,
                close=2393.55,
                index=20,
            )
        )
        bars.append(
            Bar(
                time=start + timedelta(minutes=105),
                open=2393.6,
                high=2395.0,
                low=2393.4,
                close=2394.8,
                index=21,
            )
        )

        config = ReplayConfig.from_json()
        summary = ReplayEngine(config).run(
            bars,
            manual_levels=[_make_manual_level(level_price, start)],
            use_pdh_pdl=False,
        )

        reclaim = [e for e in summary.events if e.event_type == "RECLAIM"]
        self.assertEqual(len(reclaim), 1)
        self.assertEqual(reclaim[0].direction, "FADE_BUY")


class InvalidationTest(unittest.TestCase):
    def test_invalidation_after_reclaim_on_re_acceptance(self) -> None:
        start = datetime(2025, 6, 10, 8, 0, 0)
        bars = _make_warmup_bars(start, 20, base=2396.0, span=1.2)
        level_price = 2400.0

        bars.extend(
            [
                Bar(
                    time=start + timedelta(minutes=100),
                    open=2399.6,
                    high=2400.55,
                    low=2399.85,
                    close=2400.45,
                    index=20,
                ),
                Bar(
                    time=start + timedelta(minutes=105),
                    open=2400.6,
                    high=2400.7,
                    low=2399.2,
                    close=2399.5,
                    index=21,
                ),
                # Re-acceptance beyond level
                Bar(
                    time=start + timedelta(minutes=110),
                    open=2399.8,
                    high=2401.2,
                    low=2399.6,
                    close=2400.65,
                    index=22,
                ),
            ]
        )

        config = ReplayConfig.from_json()
        summary = ReplayEngine(config).run(
            bars,
            manual_levels=[_make_manual_level(level_price, start)],
            use_pdh_pdl=False,
        )

        self.assertEqual(summary.reclaims, 1)
        self.assertGreaterEqual(summary.invalidations, 1)


class FixtureCsvTest(unittest.TestCase):
    def test_load_fixture_csv_round_trip(self) -> None:
        fixture_path = FIXTURES / "upside_sweep_reclaim_m5.csv"
        if not fixture_path.exists():
            self.skipTest("fixture not generated")

        bars = load_m5_csv(fixture_path)
        levels = load_levels_csv(FIXTURES / "manual_level_2400.csv")
        summary = ReplayEngine(ReplayConfig.from_json()).run(
            bars, manual_levels=levels, use_pdh_pdl=False
        )
        self.assertGreater(summary.sweep_starts, 0)


class WriteEventsTest(unittest.TestCase):
    def test_events_csv_writer(self) -> None:
        start = datetime(2025, 6, 10, 8, 0, 0)
        bars = _make_warmup_bars(start, 20)
        bars.append(
            Bar(
                time=start + timedelta(minutes=100),
                open=2396.2,
                high=2397.2,
                low=2396.0,
                close=2396.8,
                index=20,
            )
        )
        summary = ReplayEngine(ReplayConfig.from_json()).run(
            bars,
            manual_levels=[_make_manual_level(2400.0, start)],
            use_pdh_pdl=False,
        )
        out = FIXTURES / "_test_events_out.csv"
        write_events_csv(out, summary.events)
        self.assertTrue(out.exists())
        out.unlink()


if __name__ == "__main__":
    unittest.main()
