//+------------------------------------------------------------------+
//| Config.mqh — PARAMETER-DEFAULTS.json values                      |
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

void RLVR_LoadDefaultRecoveryConfig(SRecoveryConfig &cfg)
  {
   cfg.max_rung_depth                 = 4;
   cfg.rung_multipliers[0]            = 1.0;
   cfg.rung_multipliers[1]            = 1.3;
   cfg.rung_multipliers[2]            = 1.6;
   cfg.rung_multipliers[3]            = 1.9;
   cfg.rung_multipliers[4]            = 2.2;
   cfg.rung_locations[0]              = 0.0;
   cfg.rung_locations[1]              = 0.25;
   cfg.rung_locations[2]              = 0.50;
   cfg.rung_locations[3]              = 0.75;
   cfg.rung_locations[4]              = 0.95;
   cfg.min_rung_spacing_atr           = 0.20;
   cfg.min_rung_spacing_spread_mult   = 8.0;
   cfg.vol_add_max_atr_mult           = 1.5;
   cfg.max_gross_lot_mult             = 7.0;
  }

void RLVR_LoadDefaultExitConfig(SExitConfig &cfg)
  {
   cfg.partial_close_pct                    = 0.40;
   cfg.basket_tp_atr                        = 0.25;
   cfg.trail_buffer_atr                     = 0.15;
   cfg.time_exit_age_pct_of_ttl             = 0.90;
   cfg.time_exit_max_dd_pct_of_basket_limit  = 0.35;
  }

void RLVR_LoadDefaultRiskConfig(SRiskConfig &cfg)
  {
   cfg.risk_per_basket  = 0.0125;
   cfg.basket_dd_limit  = 0.0125;
   cfg.daily_dd_limit   = 0.025;
   cfg.weekly_dd_limit  = 0.05;
   cfg.margin_limit     = 0.25;
  }

void RLVR_LoadDefaultAntiBlowupConfig(SAntiBlowupConfig &cfg)
  {
   cfg.cooldown_after_emergency_seconds      = 14400;
   cfg.cooldown_after_normal_exit_seconds    = 1800;
   cfg.max_session_failures_before_halt      = 2;
   cfg.flatten_retry_count                   = 3;
   cfg.flatten_timeout_seconds               = 10;
   cfg.vol_kill_atr_mult                     = 2.0;
   cfg.spread_kill_mult                      = 3.0;
  }

void RLVR_LoadDefaultSessionConfig(SSessionConfig &cfg)
  {
   cfg.allow_asia_trading          = false;
   cfg.liquid_session_start_hour   = 7;
   cfg.liquid_session_end_hour     = 21;
   cfg.rollover_lock_minutes       = 30;
  }

void RLVR_LoadDefaultRegimeConfig(SRegimeConfig &cfg)
  {
   cfg.spread_ok_mult              = 2.5;
   cfg.runaway_displacement_mult   = 3.0;
   cfg.runaway_pullback_min_mult   = 0.5;
   cfg.max_chaos_atr_m15           = 0.0;
  }

#endif
