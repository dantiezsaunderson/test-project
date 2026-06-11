"""Tests for parity_compare utility."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from tools.rlvr_replay.io_csv import write_events_csv
from tools.rlvr_replay.models import ReplayEvent
from tools.rlvr_replay.parity_compare import compare_sequences, load_events_csv, run_python_reference

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures"


class ParityCompareTest(unittest.TestCase):
    def test_identical_sequences_pass(self) -> None:
        from datetime import datetime

        events = [
            ReplayEvent(
                timestamp=datetime(2025, 6, 10, 9, 40),
                event_type="SWEEP_START",
                level_id="TEST",
                level_price=2400.0,
                bar_index=20,
                atr_m5=1.2,
                direction="FADE_SELL",
            )
        ]
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "events.csv"
            write_events_csv(path, events)
            loaded = load_events_csv(path)
            ok, messages = compare_sequences(loaded, loaded)
            self.assertTrue(ok)
            self.assertTrue(any("PARITY OK" in message for message in messages))

    def test_python_reference_on_fixture(self) -> None:
        m5 = FIXTURES / "upside_sweep_reclaim_m5.csv"
        levels = FIXTURES / "manual_level_2400.csv"
        reference = run_python_reference(m5, levels, no_pdh_pdl=True, output=None)
        self.assertGreater(len(reference), 0)
        event_types = [event.event_type for event in reference]
        self.assertIn("SWEEP_START", event_types)
        self.assertIn("RECLAIM", event_types)


if __name__ == "__main__":
    unittest.main()
