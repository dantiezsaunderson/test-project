//+------------------------------------------------------------------+
//| Types.mqh — RLVR core types (spec §4)                            |
//+------------------------------------------------------------------+
#ifndef __RLVR_TYPES_MQH__
#define __RLVR_TYPES_MQH__

#define RLVR_MAX_LEVELS          64
#define RLVR_MAX_EVENTS_PER_BAR  8
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
