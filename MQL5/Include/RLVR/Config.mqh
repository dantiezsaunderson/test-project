//+------------------------------------------------------------------+
//| Config.mqh — default parameters (PARAMETER-DEFAULTS.json)        |
//+------------------------------------------------------------------+
#ifndef __RLVR_CONFIG_MQH__
#define __RLVR_CONFIG_MQH__

#include "Types.mqh"

void RLVR_LoadDefaultStructureConfig(SStructureConfig &cfg)
  {
   cfg.sweep_depth_min_atr       = 0.15;
   cfg.sweep_depth_max_atr       = 0.80;
   cfg.sweep_window_bars         = 20;
   cfg.reclaim_ttl_seconds       = 5400;
   cfg.reclaim_body_filter       = true;
   cfg.invalidation_buffer_atr   = 0.10;
   cfg.acceptance_distance_atr   = 0.20;
  }

void RLVR_LoadDefaultLevelsConfig(SLevelsConfig &cfg)
  {
   cfg.level_quality_threshold   = 0.55;
   cfg.level_merge_distance_atr  = 0.10;
   cfg.round_step                = 50.0;
   cfg.max_armed_levels          = 3;
  }

#endif
