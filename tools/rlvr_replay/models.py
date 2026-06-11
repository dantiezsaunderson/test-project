"""RLVR replay data models — mirrors formal spec Section 4."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Optional


class LevelType(str, Enum):
    PDH = "PDH"
    PDL = "PDL"
    ASIA_H = "ASIA_H"
    ASIA_L = "ASIA_L"
    LONDON_H = "LONDON_H"
    LONDON_L = "LONDON_L"
    EQH = "EQH"
    EQL = "EQL"
    ROUND = "ROUND"
    MANUAL = "MANUAL"


class FadeDirection(str, Enum):
    FADE_SELL = "FADE_SELL"
    FADE_BUY = "FADE_BUY"


class LevelState(str, Enum):
    IDLE = "IDLE"
    ARMED = "ARMED"
    SWEEP_DETECTED = "SWEEP_DETECTED"
    RECLAIM_CONFIRMED = "RECLAIM_CONFIRMED"
    CONSUMED = "CONSUMED"
    EXPIRED = "EXPIRED"


@dataclass
class Bar:
    """Single M5 OHLC bar."""

    time: datetime
    open: float
    high: float
    low: float
    close: float
    index: int = 0


@dataclass
class LiquidityLevel:
    level_id: str
    level_type: LevelType
    price: float
    quality_score: float
    created_at: datetime
    expires_at: datetime
    state: LevelState = LevelState.ARMED
    sweep_extreme: Optional[float] = None
    sweep_start_time: Optional[datetime] = None
    sweep_start_bar_index: Optional[int] = None
    reclaim_time: Optional[datetime] = None
    direction: Optional[FadeDirection] = None
    void_midpoint: Optional[float] = None
    sweep_side: Optional[str] = None  # "above" | "below"


@dataclass
class ReplayEvent:
    timestamp: datetime
    event_type: str
    level_id: str
    level_price: float
    bar_index: int
    atr_m5: float
    sweep_extreme: Optional[float] = None
    void_midpoint: Optional[float] = None
    direction: Optional[str] = None
    penetration: Optional[float] = None
    message: str = ""


@dataclass
class ReplaySummary:
    total_bars: int = 0
    levels_armed: int = 0
    sweep_starts: int = 0
    sweep_too_deep: int = 0
    sweep_timeouts: int = 0
    reclaims: int = 0
    reclaim_ttl_expired: int = 0
    invalidations: int = 0
    events: list[ReplayEvent] = field(default_factory=list)
