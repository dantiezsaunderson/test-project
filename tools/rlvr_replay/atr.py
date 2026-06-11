"""Wilder ATR on M5 bars."""

from __future__ import annotations

from typing import Sequence

from .models import Bar


def true_range(bar: Bar, prev_close: float | None) -> float:
    if prev_close is None:
        return bar.high - bar.low
    return max(
        bar.high - bar.low,
        abs(bar.high - prev_close),
        abs(bar.low - prev_close),
    )


def wilder_atr_series(bars: Sequence[Bar], period: int = 14) -> list[float | None]:
    """Return ATR value per bar; None until period satisfied."""
    if period < 1:
        raise ValueError("period must be >= 1")

    atr_values: list[float | None] = [None] * len(bars)
    if not bars:
        return atr_values

    tr_values: list[float] = []
    prev_close: float | None = None
    for bar in bars:
        tr_values.append(true_range(bar, prev_close))
        prev_close = bar.close

    if len(tr_values) < period:
        return atr_values

    first_atr = sum(tr_values[:period]) / period
    atr_values[period - 1] = first_atr
    prev_atr = first_atr
    for i in range(period, len(tr_values)):
        prev_atr = (prev_atr * (period - 1) + tr_values[i]) / period
        atr_values[i] = prev_atr

    return atr_values
