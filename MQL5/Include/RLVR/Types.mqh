//+------------------------------------------------------------------+
//| Types.mqh — RLVR core types (spec §4)                            |
//+------------------------------------------------------------------+
#ifndef __RLVR_TYPES_MQH__
#define __RLVR_TYPES_MQH__

#define RLVR_MAX_LEVELS          64
#define RLVR_MAX_EVENTS_PER_BAR  16
#define RLVR_MAX_LEGS            5
#define RLVR_DEFAULT_MAGIC       20250610
#define RLVR_SWEEP_SIDE_ABOVE    1
#define RLVR_SWEEP_SIDE_BELOW    2

enum ENUM_RLVR_LEVEL_TYPE
  {
   RLVR_LEVEL_PDH = 0,
   RLVR_LEVEL_PDL,
   RLVR_LEVEL_ASIA_H,
   RLVR_LEVEL_ASIA_L,
   RLVR_LEVEL_LONDON_H,
   RLVR_LEVEL_LONDON_L,
   RLVR_LEVEL_EQH,
   RLVR_LEVEL_EQL,
   RLVR_LEVEL_ROUND,
   RLVR_LEVEL_MANUAL
  };

enum ENUM_RLVR_LEVEL_STATE
  {
   RLVR_STATE_IDLE = 0,
   RLVR_STATE_ARMED,
   RLVR_STATE_SWEEP_DETECTED,
   RLVR_STATE_RECLAIM_CONFIRMED,
   RLVR_STATE_CONSUMED,
   RLVR_STATE_EXPIRED
  };

enum ENUM_RLVR_FADE_DIR
  {
   RLVR_FADE_NONE = 0,
   RLVR_FADE_SELL,
   RLVR_FADE_BUY
  };

enum ENUM_RLVR_EA_STATE
  {
   RLVR_EA_IDLE = 0,
   RLVR_EA_BASKET_ACTIVE,
   RLVR_EA_COOLDOWN,
   RLVR_EA_DEFENSIVE_HALT
  };

enum ENUM_RLVR_BASKET_STATE
  {
   RLVR_BASKET_NONE = 0,
   RLVR_BASKET_INITIAL_ENTRY,
   RLVR_BASKET_CONTROLLED_ADVERSE,
   RLVR_BASKET_RECOVERY_ELIGIBLE,
   RLVR_BASKET_RESCUE_ACTIVE,
   RLVR_BASKET_PROFIT_COMPRESSION,
   RLVR_BASKET_EXIT,
   RLVR_BASKET_DEFENSIVE_SHUTDOWN
  };

struct SLiquidityLevel
  {
   string                 level_id;
   ENUM_RLVR_LEVEL_TYPE   type;
   double                 price;
   double                 quality_score;
   datetime               created_at;
   datetime               expires_at;
   ENUM_RLVR_LEVEL_STATE  state;
   double                 sweep_extreme;
   datetime               sweep_start_time;
   int                    sweep_start_bar_index;
   datetime               reclaim_time;
   ENUM_RLVR_FADE_DIR     direction;
   double                 void_midpoint;
   int                    sweep_side;
   double                 entry_atr_m5;
   double                 entry_spread;
  };

struct SPositionLeg
  {
   ulong                  ticket;
   int                    rung;
   double                 lots;
   double                 open_price;
   datetime               open_time;
  };

struct SRlvrBasket
  {
   bool                   active;
   string                 basket_id;
   string                 level_id;
   ENUM_RLVR_FADE_DIR     direction;
   ENUM_RLVR_BASKET_STATE state;
   datetime               open_time;
   int                    depth;
   double                 vwap_price;
   double                 gross_lots;
   double                 entry_atr_m5;
   double                 entry_spread;
   double                 last_fill_price;
   double                 level_price;
   double                 sweep_extreme;
   double                 void_midpoint;
   int                    sweep_side;
   bool                   partial_done;
   bool                   trail_active;
   double                 trail_stop;
   double                 u0;
   SPositionLeg           legs[RLVR_MAX_LEGS];
  };

struct SReplayEvent
  {
   datetime               timestamp;
   string                 event_type;
   string                 level_id;
   double                 level_price;
   int                    bar_index;
   double                 atr_m5;
   double                 sweep_extreme;
   double                 void_midpoint;
   string                 direction;
   double                 penetration;
   string                 message;
  };

struct SStructureConfig
  {
   double                 sweep_depth_min_atr;
   double                 sweep_depth_max_atr;
   int                    sweep_window_bars;
   int                    reclaim_ttl_seconds;
   bool                   reclaim_body_filter;
   double                 invalidation_buffer_atr;
   double                 acceptance_distance_atr;
  };

struct SLevelsConfig
  {
   double                 level_quality_threshold;
   double                 level_merge_distance_atr;
   double                 round_step;
   int                    max_armed_levels;
  };

struct SRecoveryConfig
  {
   int                    max_rung_depth;
   double                 rung_multipliers[RLVR_MAX_LEGS];
   double                 rung_locations[RLVR_MAX_LEGS];
   double                 min_rung_spacing_atr;
   double                 min_rung_spacing_spread_mult;
   double                 vol_add_max_atr_mult;
   double                 max_gross_lot_mult;
  };

struct SExitConfig
  {
   double                 partial_close_pct;
   double                 basket_tp_atr;
   double                 trail_buffer_atr;
   double                 time_exit_age_pct_of_ttl;
   double                 time_exit_max_dd_pct_of_basket_limit;
  };

struct SRiskConfig
  {
   double                 risk_per_basket;
   double                 basket_dd_limit;
   double                 daily_dd_limit;
   double                 weekly_dd_limit;
   double                 margin_limit;
  };

struct SAntiBlowupConfig
  {
   int                    cooldown_after_emergency_seconds;
   int                    cooldown_after_normal_exit_seconds;
   int                    max_session_failures_before_halt;
   int                    flatten_retry_count;
   int                    flatten_timeout_seconds;
   double                 vol_kill_atr_mult;
   double                 spread_kill_mult;
  };

struct SSessionConfig
  {
   bool                   allow_asia_trading;
   int                    liquid_session_start_hour;
   int                    liquid_session_end_hour;
   int                    rollover_lock_minutes;
  };

struct SRegimeConfig
  {
   double                 spread_ok_mult;
   double                 runaway_displacement_mult;
   double                 runaway_pullback_min_mult;
   double                 max_chaos_atr_m15;
  };

void RLVR_InitLevel(SLiquidityLevel &level)
  {
   level.level_id            = "";
   level.type                = RLVR_LEVEL_MANUAL;
   level.price               = 0.0;
   level.quality_score       = 0.0;
   level.created_at          = 0;
   level.expires_at          = 0;
   level.state               = RLVR_STATE_ARMED;
   level.sweep_extreme       = 0.0;
   level.sweep_start_time    = 0;
   level.sweep_start_bar_index = -1;
   level.reclaim_time        = 0;
   level.direction           = RLVR_FADE_NONE;
   level.void_midpoint       = 0.0;
   level.sweep_side          = 0;
   level.entry_atr_m5        = 0.0;
   level.entry_spread        = 0.0;
  }

void RLVR_InitBasket(SRlvrBasket &basket)
  {
   basket.active          = false;
   basket.basket_id       = "";
   basket.level_id        = "";
   basket.direction       = RLVR_FADE_NONE;
   basket.state           = RLVR_BASKET_NONE;
   basket.open_time       = 0;
   basket.depth           = -1;
   basket.vwap_price      = 0.0;
   basket.gross_lots      = 0.0;
   basket.entry_atr_m5    = 0.0;
   basket.entry_spread    = 0.0;
   basket.last_fill_price = 0.0;
   basket.level_price     = 0.0;
   basket.sweep_extreme   = 0.0;
   basket.void_midpoint   = 0.0;
   basket.sweep_side      = 0;
   basket.partial_done    = false;
   basket.trail_active    = false;
   basket.trail_stop      = 0.0;
   basket.u0              = 0.0;
   for(int i = 0; i < RLVR_MAX_LEGS; i++)
     {
      basket.legs[i].ticket     = 0;
      basket.legs[i].rung       = -1;
      basket.legs[i].lots       = 0.0;
      basket.legs[i].open_price = 0.0;
      basket.legs[i].open_time  = 0;
     }
  }

bool RLVR_IsBuyDirection(const ENUM_RLVR_FADE_DIR dir)
  {
   return dir == RLVR_FADE_BUY;
  }

string RLVR_FadeDirToString(const ENUM_RLVR_FADE_DIR dir)
  {
   if(dir == RLVR_FADE_SELL)
      return "FADE_SELL";
   if(dir == RLVR_FADE_BUY)
      return "FADE_BUY";
   return "";
  }

int RLVR_LevelTypePriority(const ENUM_RLVR_LEVEL_TYPE t)
  {
   switch(t)
     {
      case RLVR_LEVEL_PDH:
      case RLVR_LEVEL_PDL:
         return 1;
      case RLVR_LEVEL_ASIA_H:
      case RLVR_LEVEL_ASIA_L:
         return 2;
      case RLVR_LEVEL_LONDON_H:
      case RLVR_LEVEL_LONDON_L:
         return 3;
      case RLVR_LEVEL_EQH:
      case RLVR_LEVEL_EQL:
         return 4;
      case RLVR_LEVEL_ROUND:
         return 5;
      case RLVR_LEVEL_MANUAL:
         return 6;
     }
   return 99;
  }

#endif
