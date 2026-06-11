"""Basket rung price + recovery eligibility (parity helpers for full build)."""

from __future__ import annotations

from dataclasses import dataclass

RUNG_LOCATIONS = [0.0, 0.25, 0.50, 0.75, 0.95]
RUNG_MULTIPLIERS = [1.0, 1.3, 1.6, 1.9, 2.2]


@dataclass
class BasketSnapshot:
    level_price: float
    sweep_extreme: float
    sweep_side: str  # "above" | "below"
    depth: int
    u0: float = 0.01


def void_width(snapshot: BasketSnapshot) -> float:
    return abs(snapshot.sweep_extreme - snapshot.level_price)


def rung_price(snapshot: BasketSnapshot, rung: int) -> float:
    L = snapshot.level_price
    E = snapshot.sweep_extreme
    vw = void_width(snapshot)
    if rung == 4:
        if snapshot.sweep_side == "above":
            return E - 0.05 * vw
        return E + 0.05 * vw
    loc = RUNG_LOCATIONS[rung]
    if snapshot.sweep_side == "above":
        return L + loc * vw
    return L - loc * vw


def next_rung_lots(snapshot: BasketSnapshot, rung: int) -> float:
    return snapshot.u0 * RUNG_MULTIPLIERS[rung]


def max_gross_lots(snapshot: BasketSnapshot) -> float:
    return snapshot.u0 * 7.0
