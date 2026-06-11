"""Load RLVR parameters from docs/rlvr/PARAMETER-DEFAULTS.json."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path


DEFAULT_CONFIG_PATH = (
    Path(__file__).resolve().parents[2] / "docs" / "rlvr" / "PARAMETER-DEFAULTS.json"
)


@dataclass(frozen=True)
class StructureConfig:
    sweep_depth_min_atr: float
    sweep_depth_max_atr: float
    sweep_window_bars: int
    reclaim_ttl_seconds: int
    reclaim_body_filter: bool
    invalidation_buffer_atr: float
    acceptance_distance_atr: float


@dataclass(frozen=True)
class LevelsConfig:
    level_quality_threshold: float
    level_merge_distance_atr: float
    max_armed_levels: int


@dataclass(frozen=True)
class ReplayConfig:
    structure: StructureConfig
    levels: LevelsConfig
    atr_period: int = 14

    @classmethod
    def from_json(cls, path: Path | None = None) -> ReplayConfig:
        config_path = path or DEFAULT_CONFIG_PATH
        with config_path.open(encoding="utf-8") as handle:
            raw = json.load(handle)
        structure = raw["structure"]
        levels = raw["levels"]
        return cls(
            structure=StructureConfig(
                sweep_depth_min_atr=structure["sweep_depth_min_atr"],
                sweep_depth_max_atr=structure["sweep_depth_max_atr"],
                sweep_window_bars=structure["sweep_window_bars"],
                reclaim_ttl_seconds=structure["reclaim_ttl_seconds"],
                reclaim_body_filter=structure["reclaim_body_filter"],
                invalidation_buffer_atr=structure["invalidation_buffer_atr"],
                acceptance_distance_atr=structure["acceptance_distance_atr"],
            ),
            levels=LevelsConfig(
                level_quality_threshold=levels["level_quality_threshold"],
                level_merge_distance_atr=levels["level_merge_distance_atr"],
                max_armed_levels=levels["max_armed_levels"],
            ),
        )
