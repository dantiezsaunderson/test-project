"""Tests for basket rung math."""

from __future__ import annotations

import unittest

from tools.rlvr_replay.basket_sim import BasketSnapshot, rung_price, void_width


class BasketSimTest(unittest.TestCase):
    def test_upside_void_rungs(self) -> None:
        snap = BasketSnapshot(
            level_price=2400.0,
            sweep_extreme=2401.0,
            sweep_side="above",
            depth=0,
        )
        self.assertAlmostEqual(void_width(snap), 1.0)
        self.assertAlmostEqual(rung_price(snap, 2), 2400.5)
        self.assertAlmostEqual(rung_price(snap, 4), 2400.95)

    def test_downside_void_rungs(self) -> None:
        snap = BasketSnapshot(
            level_price=2400.0,
            sweep_extreme=2399.0,
            sweep_side="below",
            depth=0,
        )
        self.assertAlmostEqual(rung_price(snap, 2), 2399.5)


if __name__ == "__main__":
    unittest.main()
