//+------------------------------------------------------------------+
//| RLVR_AllInOne.mq5 — single-file RLVR (run merge_all_in_one.py)   |
//| Compile THIS file only — no Include/RLVR folder required.        |
//+------------------------------------------------------------------+
#property copyright "RLVR"
#property version   "2.01"
#property strict

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| MERGED MODULES
//+------------------------------------------------------------------+

// ===== BEGIN Types =====
//+------------------------------------------------------------------+
//| Types.mqh — RLVR core types (spec §4)                            |
//+------------------------------------------------------------------+

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
// ===== END Types =====

// ===== BEGIN Config =====
//+------------------------------------------------------------------+
//| Config.mqh — PARAMETER-DEFAULTS.json values                      |
//+------------------------------------------------------------------+


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
// ===== END Config =====

// ===== BEGIN AtrUtils =====
//+------------------------------------------------------------------+
//| AtrUtils.mqh — ATR helpers                                       |
//+------------------------------------------------------------------+

double RLVR_GetAtr(const string symbol,
                   const ENUM_TIMEFRAMES tf,
                   const int period,
                   const int shift = 1)
  {
   int handle = iATR(symbol, tf, period);
   if(handle == INVALID_HANDLE)
      return 0.0;

   double buffer[];
   ArraySetAsSeries(buffer, true);
   if(CopyBuffer(handle, 0, shift, 1, buffer) != 1)
     {
      IndicatorRelease(handle);
      return 0.0;
     }
   IndicatorRelease(handle);
   return buffer[0];
  }
// ===== END AtrUtils =====

// ===== BEGIN Telemetry =====
//+------------------------------------------------------------------+
//| Telemetry.mqh — CSV event log (spec §20)                          |
//+------------------------------------------------------------------+


class CRLVRTelemetry
  {
private:
   int      m_handle;
   string   m_filename;
   bool     m_enabled;

public:
            CRLVRTelemetry(): m_handle(INVALID_HANDLE), m_filename(""), m_enabled(false) {}

   bool     Open(const string filename, const bool enabled)
     {
      m_enabled  = enabled;
      m_filename = filename;
      if(!m_enabled)
         return true;

      m_handle = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
      if(m_handle == INVALID_HANDLE)
        {
         Print("RLVR Telemetry: failed to open ", filename, " err=", GetLastError());
         return false;
        }
      FileWrite(m_handle,
                "timestamp",
                "event_type",
                "level_id",
                "level_price",
                "bar_index",
                "atr_m5",
                "sweep_extreme",
                "void_midpoint",
                "direction",
                "penetration",
                "message");
      return true;
     }

   void     Close()
     {
      if(m_handle != INVALID_HANDLE)
        {
         FileClose(m_handle);
         m_handle = INVALID_HANDLE;
        }
     }

   void     LogEvent(const SReplayEvent &event)
     {
      if(!m_enabled || m_handle == INVALID_HANDLE)
         return;

      FileWrite(m_handle,
                TimeToString(event.timestamp, TIME_DATE | TIME_SECONDS),
                event.event_type,
                event.level_id,
                DoubleToString(event.level_price, _Digits),
                IntegerToString(event.bar_index),
                DoubleToString(event.atr_m5, _Digits),
                (event.sweep_extreme > 0.0 ? DoubleToString(event.sweep_extreme, _Digits) : ""),
                (event.void_midpoint > 0.0 ? DoubleToString(event.void_midpoint, _Digits) : ""),
                event.direction,
                (event.penetration > 0.0 ? DoubleToString(event.penetration, _Digits) : ""),
                event.message);
      FileFlush(m_handle);
     }

   void     LogPrint(const SReplayEvent &event)
     {
      Print("RLVR|", event.event_type,
            "|", event.level_id,
            "|bar=", event.bar_index,
            "|", event.message);
     }
  };
// ===== END Telemetry =====

// ===== BEGIN TradeUtils =====
//+------------------------------------------------------------------+
//| TradeUtils.mqh — order helpers                                   |
//+------------------------------------------------------------------+


class CRLVRTradeUtils
  {
private:
   CTrade    m_trade;
   string    m_symbol;
   ulong     m_magic;
   bool      m_dry_run;

   double TickValuePerLot() const
     {
      const double tick_size  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      const double tick_value = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tick_size <= 0.0)
         return 0.0;
      return tick_value / tick_size;
     }

public:
   void Init(const string symbol, const ulong magic, const bool dry_run)
     {
      m_symbol  = symbol;
      m_magic   = magic;
      m_dry_run = dry_run;
      m_trade.SetExpertMagicNumber((long)magic);
      m_trade.SetDeviationInPoints(30);
      m_trade.SetTypeFillingBySymbol(symbol);
     }

   double NormalizeLot(const double lots) const
     {
      const double min_lot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      const double max_lot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      const double lot_step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      if(lot_step <= 0.0)
         return lots;
      double normalized = MathFloor(lots / lot_step) * lot_step;
      if(normalized < min_lot)
         normalized = min_lot;
      if(normalized > max_lot)
         normalized = max_lot;
      return normalized;
     }

   bool OpenMarket(const ENUM_RLVR_FADE_DIR direction,
                   const double lots,
                   const string comment,
                   ulong &ticket_out,
                   double &fill_price_out)
     {
      ticket_out     = 0;
      fill_price_out = 0.0;
      const double vol = NormalizeLot(lots);
      if(vol <= 0.0)
         return false;

      if(m_dry_run)
        {
         ticket_out = (ulong)(TimeCurrent() + vol * 1000.0);
         fill_price_out = (direction == RLVR_FADE_BUY)
                          ? SymbolInfoDouble(m_symbol, SYMBOL_ASK)
                          : SymbolInfoDouble(m_symbol, SYMBOL_BID);
         return true;
        }

      bool ok = false;
      if(direction == RLVR_FADE_BUY)
         ok = m_trade.Buy(vol, m_symbol, 0.0, 0.0, 0.0, comment);
      else
         ok = m_trade.Sell(vol, m_symbol, 0.0, 0.0, 0.0, comment);

      if(!ok)
         return false;

      ticket_out     = m_trade.ResultOrder();
      fill_price_out = m_trade.ResultPrice();
      return true;
     }

   bool CloseTicket(const ulong ticket, const double volume)
     {
      if(m_dry_run)
         return true;
      if(!PositionSelectByTicket(ticket))
         return false;
      return m_trade.PositionClose(ticket, volume);
     }

   int CloseAllByMagic(double &closed_volume_out)
     {
      closed_volume_out = 0.0;
      int closed = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         const ulong ticket = PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket))
            continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;
         const double vol = PositionGetDouble(POSITION_VOLUME);
         if(m_dry_run)
           {
            closed_volume_out += vol;
            closed++;
            continue;
           }
         if(m_trade.PositionClose(ticket))
           {
            closed_volume_out += vol;
            closed++;
           }
        }
      return closed;
     }

   double EstimateLossPerLot(const double price_distance) const
     {
      return price_distance * TickValuePerLot();
     }

   bool IsDryRun() const { return m_dry_run; }
   ulong Magic() const { return m_magic; }
  };
// ===== END TradeUtils =====

// ===== BEGIN RiskManager =====
//+------------------------------------------------------------------+
//| RiskManager.mqh — spec §14                                       |
//+------------------------------------------------------------------+


class CRiskManager
  {
private:
   SRiskConfig       m_cfg;
   double            m_day_start_equity;
   int               m_day_key;
   double            m_week_start_equity;
   int               m_week_key;
   double            m_daily_closed_pnl;

public:
   void Init(const SRiskConfig &cfg)
     {
      m_cfg = cfg;
      ResetDayIfNeeded();
      ResetWeekIfNeeded();
     }

   int DayKey(const datetime t) const
     {
      MqlDateTime dt;
      TimeToStruct(t, dt);
      return dt.year * 10000 + dt.mon * 100 + dt.day;
     }

   int WeekKey(const datetime t) const
     {
      MqlDateTime dt;
      TimeToStruct(t, dt);
      return dt.year * 100 + dt.day_of_year / 7;
     }

   void ResetDayIfNeeded()
     {
      const int key = DayKey(TimeCurrent());
      if(key != m_day_key)
        {
         m_day_key           = key;
         m_day_start_equity  = AccountInfoDouble(ACCOUNT_EQUITY);
         m_daily_closed_pnl  = 0.0;
        }
     }

   void ResetWeekIfNeeded()
     {
      const int key = WeekKey(TimeCurrent());
      if(key != m_week_key)
        {
         m_week_key          = key;
         m_week_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
        }
     }

   void OnBalanceUpdate() { ResetDayIfNeeded(); ResetWeekIfNeeded(); }

   double FloatingDdPct(const double floating_pnl) const
     {
      const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0.0)
         return 0.0;
      return (-MathMin(0.0, floating_pnl)) / equity;
     }

   double DailyDdPct(const double floating_pnl) const
     {
      if(m_day_start_equity <= 0.0)
         return 0.0;
      const double total = m_daily_closed_pnl + floating_pnl;
      return (-MathMin(0.0, total)) / m_day_start_equity;
     }

   double WeeklyDdPct(const double floating_pnl) const
     {
      if(m_week_start_equity <= 0.0)
         return 0.0;
      const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      const double pnl    = equity - m_week_start_equity;
      return (-MathMin(0.0, pnl)) / m_week_start_equity;
     }

   double MarginUsage() const
     {
      const double margin = AccountInfoDouble(ACCOUNT_MARGIN);
      const double free   = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      const double total  = margin + free;
      if(total <= 0.0)
         return 0.0;
      return margin / total;
     }

   bool BasketDdBreached(const double floating_pnl) const
     {
      return FloatingDdPct(floating_pnl) >= m_cfg.basket_dd_limit;
     }

   bool DailyDdBreached(const double floating_pnl) const
     {
      return DailyDdPct(floating_pnl) >= m_cfg.daily_dd_limit;
     }

   bool WeeklyDdBreached(const double floating_pnl) const
     {
      return WeeklyDdPct(floating_pnl) >= m_cfg.weekly_dd_limit;
     }

   bool MarginBreached() const
     {
      return MarginUsage() >= m_cfg.margin_limit;
     }

   double ComputeU0(const CRLVRTradeUtils &trade,
                    const double void_width,
                    const double invalidation_buffer,
                    const SRecoveryConfig &recovery) const
     {
      const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0.0)
         return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

      const double worst_distance = void_width + invalidation_buffer;
      double worst_loss_per_u0 = 0.0;
      double gross_mult = 0.0;
      for(int i = 0; i <= recovery.max_rung_depth; i++)
         gross_mult += recovery.rung_multipliers[i];

      worst_loss_per_u0 = trade.EstimateLossPerLot(worst_distance) * gross_mult;
      if(worst_loss_per_u0 <= 0.0)
         return trade.NormalizeLot(0.01);

      const double budget = equity * m_cfg.risk_per_basket;
      const double u0     = budget / worst_loss_per_u0;
      return trade.NormalizeLot(u0);
     }

   bool PreTradeGate(const double projected_floating_dd_pct,
                     const bool margin_ok) const
     {
      if(projected_floating_dd_pct >= m_cfg.basket_dd_limit)
         return false;
      if(!margin_ok)
         return false;
      return true;
     }

   const SRiskConfig &Config() const { return m_cfg; }

   void AddClosedPnl(const double pnl) { m_daily_closed_pnl += pnl; }
  };
// ===== END RiskManager =====

// ===== BEGIN BasketManager =====
//+------------------------------------------------------------------+
//| BasketManager.mqh — basket state + position sync                   |
//+------------------------------------------------------------------+


class CBasketManager
  {
private:
   string    m_symbol;
   ulong     m_magic;
   SRlvrBasket m_basket;

   void RecomputeAggregates()
     {
      double sum_px_vol = 0.0;
      m_basket.gross_lots = 0.0;
      m_basket.depth      = -1;
      for(int i = 0; i < RLVR_MAX_LEGS; i++)
        {
         if(!m_dry_has_leg[i])
            continue;
         const double lots = m_basket.legs[i].lots;
         if(lots <= 0.0)
            continue;
         sum_px_vol += m_basket.legs[i].open_price * lots;
         m_basket.gross_lots += lots;
         if(i > m_basket.depth)
            m_basket.depth = i;
        }
      if(m_basket.gross_lots > 0.0)
         m_basket.vwap_price = sum_px_vol / m_basket.gross_lots;
      if(m_basket.depth >= 0)
         m_basket.last_fill_price = m_basket.legs[m_basket.depth].open_price;
     }

   bool     m_dry_has_leg[RLVR_MAX_LEGS];

public:
            CBasketManager(): m_symbol(""), m_magic(0)
     {
      RLVR_InitBasket(m_basket);
      ArrayInitialize(m_dry_has_leg, false);
     }

   void Init(const string symbol, const ulong magic)
     {
      m_symbol = symbol;
      m_magic  = magic;
     }

   bool HasActiveBasket() const
     {
      return m_basket.active;
     }

   SRlvrBasket &Basket() { return m_basket; }
   const SRlvrBasket &Basket() const { return m_basket; }

   void ClearBasket()
     {
      RLVR_InitBasket(m_basket);
      ArrayInitialize(m_dry_has_leg, false);
     }

   bool StartBasket(const SLiquidityLevel &level,
                    const double u0,
                    const ulong ticket,
                    const double fill_price,
                    const int rung)
     {
      RLVR_InitBasket(m_basket);
      m_basket.active          = true;
      m_basket.basket_id       = StringFormat("B_%s_%d", level.level_id, (int)TimeCurrent());
      m_basket.level_id        = level.level_id;
      m_basket.direction       = level.direction;
      m_basket.state           = RLVR_BASKET_INITIAL_ENTRY;
      m_basket.open_time       = TimeCurrent();
      m_basket.entry_atr_m5    = level.entry_atr_m5;
      m_basket.entry_spread    = level.entry_spread;
      m_basket.level_price     = level.price;
      m_basket.sweep_extreme   = level.sweep_extreme;
      m_basket.void_midpoint   = level.void_midpoint;
      m_basket.sweep_side      = level.sweep_side;
      m_basket.u0              = u0;
      return AddLeg(ticket, rung, u0 * 1.0, fill_price);
     }

   bool AddLeg(const ulong ticket,
               const int rung,
               const double lots,
               const double fill_price)
     {
      if(rung < 0 || rung >= RLVR_MAX_LEGS)
         return false;
      m_basket.legs[rung].ticket     = ticket;
      m_basket.legs[rung].rung       = rung;
      m_basket.legs[rung].lots       = lots;
      m_basket.legs[rung].open_price = fill_price;
      m_basket.legs[rung].open_time  = TimeCurrent();
      m_dry_has_leg[rung]            = true;
      RecomputeAggregates();
      if(rung > 0)
         m_basket.state = RLVR_BASKET_RESCUE_ACTIVE;
      return true;
     }

   void SyncFromMarket(const bool dry_run)
     {
      if(dry_run || !m_basket.active)
         return;

      bool found = false;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         const ulong ticket = PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket))
            continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;
         found = true;
         const string comment = PositionGetString(POSITION_COMMENT);
         int rung = 0;
         const int pos = StringFind(comment, "|R");
         if(pos >= 0)
           {
            const string rung_str = StringSubstr(comment, pos + 2, 1);
            rung = (int)StringToInteger(rung_str);
           }
         if(rung >= 0 && rung < RLVR_MAX_LEGS)
           {
            m_basket.legs[rung].ticket     = ticket;
            m_basket.legs[rung].rung       = rung;
            m_basket.legs[rung].lots       = PositionGetDouble(POSITION_VOLUME);
            m_basket.legs[rung].open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            m_basket.legs[rung].open_time  = (datetime)PositionGetInteger(POSITION_TIME);
            m_dry_has_leg[rung]            = true;
           }
        }
      if(!found)
        {
         ClearBasket();
         return;
        }
      RecomputeAggregates();
     }

   double FloatingPnl(const bool dry_run) const
     {
      if(!m_basket.active)
         return 0.0;
      if(dry_run)
        {
         const double px = (m_basket.direction == RLVR_FADE_BUY)
                           ? SymbolInfoDouble(m_symbol, SYMBOL_BID)
                           : SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         double pnl = 0.0;
         const double tick_value = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
         const double tick_size  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
         if(tick_size <= 0.0)
            return 0.0;
         for(int i = 0; i < RLVR_MAX_LEGS; i++)
           {
            if(!m_dry_has_leg[i])
               continue;
            const double diff = (m_basket.direction == RLVR_FADE_BUY)
                                  ? (px - m_basket.legs[i].open_price)
                                  : (m_basket.legs[i].open_price - px);
            pnl += (diff / tick_size) * tick_value * m_basket.legs[i].lots;
           }
         return pnl;
        }

      double pnl = 0.0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         const ulong ticket = PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket))
            continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;
         pnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
        }
      return pnl;
     }

   int AgeSeconds() const
     {
      if(!m_basket.active)
         return 0;
      return (int)(TimeCurrent() - m_basket.open_time);
     }

   string LegComment(const string level_id, const int rung, const string state_tag) const
     {
      return StringFormat("RLVR|%s|R%d|%s", level_id, rung, state_tag);
     }
  };
// ===== END BasketManager =====

// ===== BEGIN SweepDetector =====
//+------------------------------------------------------------------+
//| SweepDetector.mqh — spec §7 (parity: tools/rlvr_replay/sweep.py)|
//+------------------------------------------------------------------+


class CSweepDetector
  {
private:
   SStructureConfig m_cfg;

   double UpsidePenetration(const double high, const double level_price) const
     {
      if(high <= level_price)
         return 0.0;
      return high - level_price;
     }

   double DownsidePenetration(const double low, const double level_price) const
     {
      if(low >= level_price)
         return 0.0;
      return level_price - low;
     }

   void PushEvent(SReplayEvent &events[], int &count,
                  const string type,
                  SLiquidityLevel &level,
                  const MqlRates &bar,
                  const double atr_m5,
                  const double penetration,
                  const string direction,
                  const string message) const
     {
      if(count >= RLVR_MAX_EVENTS_PER_BAR)
         return;
      events[count].timestamp     = bar.time;
      events[count].event_type    = type;
      events[count].level_id      = level.level_id;
      events[count].level_price   = level.price;
      events[count].bar_index     = (int)bar.tick_volume; // overwritten by caller
      events[count].atr_m5        = atr_m5;
      events[count].sweep_extreme = level.sweep_extreme;
      events[count].direction     = direction;
      events[count].penetration   = penetration;
      events[count].message       = message;
      count++;
     }

public:
   void Init(const SStructureConfig &cfg) { m_cfg = cfg; }

   int Process(SLiquidityLevel &level,
               const MqlRates &bar,
               const double atr_m5,
               const int bar_index,
               SReplayEvent &events[]) const
     {
      int count = 0;
      if(atr_m5 <= 0.0)
         return 0;

      const double d_min = m_cfg.sweep_depth_min_atr * atr_m5;
      const double d_max = m_cfg.sweep_depth_max_atr * atr_m5;
      const double L     = level.price;

      if(level.state == RLVR_STATE_ARMED)
        {
         const double up   = UpsidePenetration(bar.high, L);
         const double down = DownsidePenetration(bar.low, L);

         if(up >= d_min && up >= down)
           {
            level.state                 = RLVR_STATE_SWEEP_DETECTED;
            level.sweep_side            = RLVR_SWEEP_SIDE_ABOVE;
            level.sweep_start_time      = bar.time;
            level.sweep_start_bar_index = bar_index;
            level.sweep_extreme         = bar.high;

            PushEvent(events, count, "SWEEP_START", level, bar, atr_m5, up,
                      "FADE_SELL",
                      StringFormat("Upside sweep penetration=%.2f d_min=%.2f", up, d_min));
            if(up > d_max)
              {
               level.state = RLVR_STATE_EXPIRED;
               PushEvent(events, count, "SWEEP_TOO_DEEP", level, bar, atr_m5, up, "",
                         StringFormat("Penetration %.2f > d_max %.2f", up, d_max));
              }
            for(int i = 0; i < count; i++)
               events[i].bar_index = bar_index;
            return count;
           }

         if(down >= d_min)
           {
            level.state                 = RLVR_STATE_SWEEP_DETECTED;
            level.sweep_side            = RLVR_SWEEP_SIDE_BELOW;
            level.sweep_start_time      = bar.time;
            level.sweep_start_bar_index = bar_index;
            level.sweep_extreme         = bar.low;

            PushEvent(events, count, "SWEEP_START", level, bar, atr_m5, down,
                      "FADE_BUY",
                      StringFormat("Downside sweep penetration=%.2f d_min=%.2f", down, d_min));
            if(down > d_max)
              {
               level.state = RLVR_STATE_EXPIRED;
               PushEvent(events, count, "SWEEP_TOO_DEEP", level, bar, atr_m5, down, "",
                         StringFormat("Penetration %.2f > d_max %.2f", down, d_max));
              }
            for(int i = 0; i < count; i++)
               events[i].bar_index = bar_index;
            return count;
           }
         return 0;
        }

      if(level.state != RLVR_STATE_SWEEP_DETECTED)
         return 0;

      double penetration = 0.0;
      if(level.sweep_side == RLVR_SWEEP_SIDE_ABOVE)
        {
         if(bar.high > level.sweep_extreme)
            level.sweep_extreme = bar.high;
         penetration = level.sweep_extreme - L;
        }
      else
        {
         if(bar.low < level.sweep_extreme || level.sweep_extreme == 0.0)
            level.sweep_extreme = bar.low;
         penetration = L - level.sweep_extreme;
        }

      if(penetration > d_max)
        {
         level.state = RLVR_STATE_EXPIRED;
         PushEvent(events, count, "SWEEP_TOO_DEEP", level, bar, atr_m5, penetration, "",
                   StringFormat("Penetration %.2f > d_max %.2f", penetration, d_max));
         for(int i = 0; i < count; i++)
            events[i].bar_index = bar_index;
        }
      return count;
     }

   bool SweepWindowExpired(const SLiquidityLevel &level,
                           const int bar_index) const
     {
      if(level.sweep_start_bar_index < 0)
         return false;
      return (bar_index - level.sweep_start_bar_index) > m_cfg.sweep_window_bars;
     }

   bool ReclaimTtlExpired(const SLiquidityLevel &level,
                          const datetime bar_time) const
     {
      if(level.sweep_start_time <= 0)
         return false;
      return (bar_time - level.sweep_start_time) > m_cfg.reclaim_ttl_seconds;
     }
  };
// ===== END SweepDetector =====

// ===== BEGIN ReclaimDetector =====
//+------------------------------------------------------------------+
//| ReclaimDetector.mqh — spec §8                                    |
//+------------------------------------------------------------------+


class CReclaimDetector
  {
private:
   SStructureConfig m_cfg;

   double BodyRatio(const MqlRates &bar) const
     {
      const double span = bar.high - bar.low;
      if(span <= 0.0)
         return 0.0;
      return MathAbs(bar.close - bar.open) / span;
     }

   bool CloseInOuterThirdTowardReclaimedSide(const MqlRates &bar,
                                             const bool reclaimed_above) const
     {
      const double span = bar.high - bar.low;
      if(span <= 0.0)
         return false;
      const double position = (bar.close - bar.low) / span;
      if(reclaimed_above)
         return position <= 0.30;
      return position >= 0.70;
     }

public:
   void Init(const SStructureConfig &cfg) { m_cfg = cfg; }

   bool Process(SLiquidityLevel &level,
                const MqlRates &bar,
                const double atr_m5,
                const int bar_index,
                SReplayEvent &event) const
     {
      if(level.state != RLVR_STATE_SWEEP_DETECTED)
         return false;
      if(level.sweep_side == 0 || level.sweep_extreme == 0.0)
         return false;

      const double L = level.price;
      bool reclaimed = false;
      bool reclaimed_above = false;
      ENUM_RLVR_FADE_DIR dir = RLVR_FADE_NONE;

      if(level.sweep_side == RLVR_SWEEP_SIDE_ABOVE)
        {
         reclaimed        = (bar.close < L);
         reclaimed_above  = true;
         dir              = RLVR_FADE_SELL;
        }
      else
        {
         reclaimed        = (bar.close > L);
         reclaimed_above  = false;
         dir              = RLVR_FADE_BUY;
        }

      if(!reclaimed)
         return false;

      if(m_cfg.reclaim_body_filter)
        {
         if(BodyRatio(bar) < 0.30)
            return false;
         if(!CloseInOuterThirdTowardReclaimedSide(bar, reclaimed_above))
            return false;
        }

      level.state         = RLVR_STATE_RECLAIM_CONFIRMED;
      level.reclaim_time  = bar.time;
      level.direction     = dir;
      level.void_midpoint = (L + level.sweep_extreme) / 2.0;

      event.timestamp     = bar.time;
      event.event_type    = "RECLAIM";
      event.level_id      = level.level_id;
      event.level_price   = L;
      event.bar_index     = bar_index;
      event.atr_m5        = atr_m5;
      event.sweep_extreme = level.sweep_extreme;
      event.void_midpoint = level.void_midpoint;
      event.direction     = RLVR_FadeDirToString(dir);
      event.penetration   = 0.0;
      event.message       = "M5 close reclaimed inside level";
      return true;
     }
  };
// ===== END ReclaimDetector =====

// ===== BEGIN Invalidation =====
//+------------------------------------------------------------------+
//| Invalidation.mqh — spec §9                                       |
//+------------------------------------------------------------------+


class CInvalidation
  {
private:
   SStructureConfig m_cfg;

public:
   void Init(const SStructureConfig &cfg) { m_cfg = cfg; }

   bool Process(SLiquidityLevel &level,
                const MqlRates &bar,
                const double atr_m5,
                const int bar_index,
                SReplayEvent &event) const
     {
      if(level.state != RLVR_STATE_RECLAIM_CONFIRMED)
         return false;
      if(level.sweep_extreme == 0.0 || level.sweep_side == 0)
         return false;

      const double buffer     = m_cfg.invalidation_buffer_atr * atr_m5;
      const double acceptance = m_cfg.acceptance_distance_atr * atr_m5;
      const double L          = level.price;

      event.timestamp   = bar.time;
      event.level_id    = level.level_id;
      event.level_price = L;
      event.bar_index   = bar_index;
      event.atr_m5      = atr_m5;
      event.sweep_extreme = level.sweep_extreme;
      event.penetration = 0.0;

      if(level.sweep_side == RLVR_SWEEP_SIDE_ABOVE)
        {
         if(bar.close > level.sweep_extreme + buffer)
           {
            level.state      = RLVR_STATE_EXPIRED;
            event.event_type = "INVALIDATION";
            event.message    = "INV-1: close beyond sweep extreme + buffer";
            return true;
           }
         if(bar.close > L + acceptance)
           {
            level.state      = RLVR_STATE_EXPIRED;
            event.event_type = "INVALIDATION";
            event.message    = "INV-6: re-acceptance beyond level";
            return true;
           }
        }
      else
        {
         if(bar.close < level.sweep_extreme - buffer)
           {
            level.state      = RLVR_STATE_EXPIRED;
            event.event_type = "INVALIDATION";
            event.message    = "INV-2: close beyond sweep extreme + buffer";
            return true;
           }
         if(bar.close < L - acceptance)
           {
            level.state      = RLVR_STATE_EXPIRED;
            event.event_type = "INVALIDATION";
            event.message    = "INV-6: re-acceptance beyond level";
            return true;
           }
        }
      return false;
     }
  };
// ===== END Invalidation =====

// ===== BEGIN EntryEngine =====
//+------------------------------------------------------------------+
//| EntryEngine.mqh — R0 entry (spec §11)                            |
//+------------------------------------------------------------------+


class CEntryEngine
  {
private:
   SStructureConfig m_structure;

public:
   void Init(const SStructureConfig &cfg) { m_structure = cfg; }

   bool OpenR0(SLiquidityLevel &level,
               CBasketManager &basket_mgr,
               CRLVRTradeUtils &trade,
               CRiskManager &risk,
               const SRecoveryConfig &recovery,
               SReplayEvent &event_out)
     {
      if(level.direction == RLVR_FADE_NONE)
         return false;
      if(basket_mgr.HasActiveBasket())
         return false;

      const double void_width = MathAbs(level.sweep_extreme - level.price);
      const double buffer     = m_structure.invalidation_buffer_atr * level.entry_atr_m5;
      const double u0         = risk.ComputeU0(trade, void_width, buffer, recovery);
      const double lots       = trade.NormalizeLot(u0 * recovery.rung_multipliers[0]);

      string comment = basket_mgr.LegComment(level.level_id, 0, "INITIAL_ENTRY");
      ulong ticket = 0;
      double fill  = 0.0;
      if(!trade.OpenMarket(level.direction, lots, comment, ticket, fill))
         return false;

      basket_mgr.StartBasket(level, u0, ticket, fill, 0);
      level.state = RLVR_STATE_CONSUMED;

      event_out.timestamp     = TimeCurrent();
      event_out.event_type    = "R0_OPEN";
      event_out.level_id      = level.level_id;
      event_out.level_price   = level.price;
      event_out.bar_index     = 0;
      event_out.atr_m5        = level.entry_atr_m5;
      event_out.sweep_extreme = level.sweep_extreme;
      event_out.void_midpoint = level.void_midpoint;
      event_out.direction     = RLVR_FadeDirToString(level.direction);
      event_out.penetration   = lots;
      event_out.message       = StringFormat("R0 lots=%.2f fill=%.2f", lots, fill);
      return true;
     }
  };
// ===== END EntryEngine =====

// ===== BEGIN RecoveryEngine =====
//+------------------------------------------------------------------+
//| RecoveryEngine.mqh — R1–R4 (spec §12)                            |
//+------------------------------------------------------------------+


class CRecoveryEngine
  {
private:
   SRecoveryConfig  m_cfg;
   SStructureConfig m_structure;

   double RungPrice(const SRlvrBasket &basket, const int rung) const
     {
      const double L = basket.level_price;
      const double E = basket.sweep_extreme;
      const double void_width = MathAbs(E - L);
      if(rung == 4)
        {
         if(basket.sweep_side == RLVR_SWEEP_SIDE_ABOVE)
            return E - 0.05 * void_width;
         return E + 0.05 * void_width;
        }
      const double loc = m_cfg.rung_locations[rung];
      if(basket.sweep_side == RLVR_SWEEP_SIDE_ABOVE)
         return L + loc * void_width;
      return L - loc * void_width;
     }

   bool RungHit(const SRlvrBasket &basket,
                const MqlRates &bar,
                const int rung) const
     {
      const double threshold = RungPrice(basket, rung);
      if(basket.direction == RLVR_FADE_SELL)
         return bar.high >= threshold;
      return bar.low <= threshold;
     }

public:
   void Init(const SRecoveryConfig &recovery, const SStructureConfig &structure)
     {
      m_cfg       = recovery;
      m_structure = structure;
     }

   bool RecoveryForbidden(const SLiquidityLevel &level,
                          const SRlvrBasket &basket,
                          const MqlRates &bar,
                          const double atr_m5,
                          const double spread,
                          const bool soft_invalidation,
                          const bool daily_dd_breach) const
     {
      if(level.state == RLVR_STATE_EXPIRED)
         return true;
      if(daily_dd_breach)
         return true;
      if(soft_invalidation)
         return true;
      if(basket.entry_atr_m5 > 0.0 &&
         atr_m5 > m_cfg.vol_add_max_atr_mult * basket.entry_atr_m5)
         return true;
      if(basket.entry_spread > 0.0 &&
         spread > 3.0 * basket.entry_spread)
         return true;

      CInvalidation inv;
      inv.Init(m_structure);
      SLiquidityLevel lvl = level;
      lvl.state = RLVR_STATE_RECLAIM_CONFIRMED;
      SReplayEvent ev;
      if(inv.Process(lvl, bar, atr_m5, 0, ev))
         return true;

      if((TimeCurrent() - level.sweep_start_time) > m_structure.reclaim_ttl_seconds)
         return true;
      return false;
     }

   bool TryAddNextRung(SLiquidityLevel &level,
                       CBasketManager &basket_mgr,
                       const MqlRates &bar,
                       const double atr_m5,
                       const double spread,
                       CRLVRTradeUtils &trade,
                       const bool recovery_forbidden,
                       SReplayEvent &event_out)
     {
      SRlvrBasket &basket = basket_mgr.Basket();
      if(!basket.active)
         return false;
      if(recovery_forbidden)
         return false;

      const int next_rung = basket.depth + 1;
      if(next_rung > m_cfg.max_rung_depth)
         return false;
      if(!RungHit(basket, bar, next_rung))
         return false;

      const double min_spacing = MathMax(m_cfg.min_rung_spacing_atr * atr_m5,
                                         m_cfg.min_rung_spacing_spread_mult * spread);
      if(basket.last_fill_price > 0.0)
        {
         const double dist = MathAbs(RungPrice(basket, next_rung) - basket.last_fill_price);
         if(dist < min_spacing)
            return false;
        }

      double gross = 0.0;
      for(int i = 0; i <= basket.depth; i++)
         gross += basket.legs[i].lots;
      const double new_lots = trade.NormalizeLot(basket.u0 * m_cfg.rung_multipliers[next_rung]);
      if(gross + new_lots > basket.u0 * m_cfg.max_gross_lot_mult)
         return false;

      string comment = basket_mgr.LegComment(basket.level_id, next_rung, "RESCUE_ACTIVE");
      ulong ticket = 0;
      double fill  = 0.0;
      if(!trade.OpenMarket(basket.direction, new_lots, comment, ticket, fill))
         return false;

      basket_mgr.AddLeg(ticket, next_rung, new_lots, fill);
      basket.state = RLVR_BASKET_RESCUE_ACTIVE;

      event_out.timestamp     = bar.time;
      event_out.event_type    = StringFormat("R%d_ADD", next_rung);
      event_out.level_id      = basket.level_id;
      event_out.level_price   = basket.level_price;
      event_out.bar_index     = 0;
      event_out.atr_m5        = atr_m5;
      event_out.sweep_extreme = basket.sweep_extreme;
      event_out.void_midpoint = basket.void_midpoint;
      event_out.direction     = RLVR_FadeDirToString(basket.direction);
      event_out.penetration   = new_lots;
      event_out.message       = StringFormat("Recovery rung %d @ %.2f", next_rung, fill);
      return true;
     }

   double MidpointPrice(const SRlvrBasket &basket) const
     {
      return RungPrice(basket, 2);
     }
  };
// ===== END RecoveryEngine =====

// ===== BEGIN ExitManager =====
//+------------------------------------------------------------------+
//| ExitManager.mqh — spec §13                                       |
//+------------------------------------------------------------------+


class CExitManager
  {
private:
   SExitConfig      m_cfg;
   SStructureConfig m_structure;

public:
   void Init(const SExitConfig &exit_cfg, const SStructureConfig &structure)
     {
      m_cfg       = exit_cfg;
      m_structure = structure;
     }

   bool PartialAtMidpoint(SRlvrBasket &basket,
                          const MqlRates &bar,
                          const double floating_pnl,
                          const double basket_dd_limit,
                          CRLVRTradeUtils &trade,
                          SReplayEvent &event_out)
     {
      if(!basket.active || basket.partial_done)
         return false;

      CRecoveryEngine recovery;
      SRecoveryConfig rc;
      RLVR_LoadDefaultRecoveryConfig(rc);
      recovery.Init(rc, m_structure);
      const double midpoint = recovery.MidpointPrice(basket);

      bool touched = false;
      if(basket.direction == RLVR_FADE_SELL)
         touched = bar.low <= midpoint;
      else
         touched = bar.high >= midpoint;

      if(!touched)
         return false;

      const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      const double dd_pct = (equity > 0.0) ? (-MathMin(0.0, floating_pnl) / equity) : 0.0;
      if(floating_pnl < 0.0 && dd_pct > 0.75 * basket_dd_limit)
         return false;

      const double close_vol = trade.NormalizeLot(basket.gross_lots * m_cfg.partial_close_pct);
      if(close_vol <= 0.0)
         return false;

      if(!trade.IsDryRun())
        {
         for(int i = basket.depth; i >= 0; i--)
           {
            if(basket.legs[i].ticket == 0)
               continue;
            if(basket.legs[i].lots <= close_vol)
               trade.CloseTicket(basket.legs[i].ticket, basket.legs[i].lots);
            else
               trade.CloseTicket(basket.legs[i].ticket, close_vol);
            break;
           }
        }

      basket.partial_done = true;
      basket.trail_active = true;
      basket.trail_stop   = basket.vwap_price;

      event_out.timestamp   = bar.time;
      event_out.event_type  = "PARTIAL_CLOSE";
      event_out.level_id    = basket.level_id;
      event_out.level_price = basket.level_price;
      event_out.message     = StringFormat("Partial %.0f%% at midpoint", m_cfg.partial_close_pct * 100.0);
      return true;
     }

   bool BasketTakeProfit(const SRlvrBasket &basket,
                         const double atr_m5,
                         const double floating_pnl,
                         SReplayEvent &event_out) const
     {
      if(!basket.active)
         return false;
      const double target = m_cfg.basket_tp_atr * atr_m5 *
                            basket.gross_lots *
                            SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      if(floating_pnl < target)
         return false;

      event_out.timestamp   = TimeCurrent();
      event_out.event_type  = "BASKET_TP";
      event_out.level_id    = basket.level_id;
      event_out.level_price = basket.level_price;
      event_out.message     = StringFormat("Basket TP pnl=%.2f target=%.2f", floating_pnl, target);
      return true;
     }

   bool TrailStopHit(SRlvrBasket &basket,
                     const double bid,
                     const double ask,
                     SReplayEvent &event_out) const
     {
      if(!basket.active || !basket.trail_active)
         return false;

      if(basket.direction == RLVR_FADE_SELL)
        {
         if(ask < basket.trail_stop)
           {
            event_out.event_type = "TRAIL_EXIT";
            event_out.message    = "Trail stop hit (sell basket)";
            return true;
           }
        }
      else
        {
         if(bid > basket.trail_stop)
           {
            event_out.event_type = "TRAIL_EXIT";
            event_out.message    = "Trail stop hit (buy basket)";
            return true;
           }
        }
      return false;
     }

   void UpdateTrail(SRlvrBasket &basket, const double atr_m5)
     {
      if(!basket.trail_active)
         return;
      const double buffer = m_cfg.trail_buffer_atr * atr_m5;
      if(basket.direction == RLVR_FADE_SELL)
         basket.trail_stop = MathMin(basket.trail_stop, basket.vwap_price + buffer);
      else
         basket.trail_stop = MathMax(basket.trail_stop, basket.vwap_price - buffer);
     }

   bool TimeScratchExit(const SRlvrBasket &basket,
                        const double floating_pnl,
                        const double basket_dd_limit,
                        SReplayEvent &event_out) const
     {
      if(!basket.active)
         return false;
      const int age_limit = (int)(m_structure.reclaim_ttl_seconds * m_cfg.time_exit_age_pct_of_ttl);
      if(basket.open_time <= 0 || (TimeCurrent() - basket.open_time) < age_limit)
         return false;

      const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      const double dd_pct = (equity > 0.0) ? (-MathMin(0.0, floating_pnl) / equity) : 0.0;
      if(dd_pct >= m_cfg.time_exit_max_dd_pct_of_basket_limit * basket_dd_limit)
         return false;

      event_out.timestamp  = TimeCurrent();
      event_out.event_type = "TIME_EXIT";
      event_out.level_id   = basket.level_id;
      event_out.message    = "Time-based scratch exit";
      return true;
     }
  };
// ===== END ExitManager =====

// ===== BEGIN AntiBlowup =====
//+------------------------------------------------------------------+
//| AntiBlowup.mqh — spec §15                                        |
//+------------------------------------------------------------------+


enum ENUM_RLVR_CB_REASON
  {
   RLVR_CB_NONE = 0,
   RLVR_CB_BASKET_DD,
   RLVR_CB_DAILY_DD,
   RLVR_CB_WEEKLY_DD,
   RLVR_CB_MARGIN,
   RLVR_CB_SESSION_FAILURES,
   RLVR_CB_INVALIDATION
  };

class CAntiBlowup
  {
private:
   SAntiBlowupConfig m_cfg;
   int               m_session_failures;
   int               m_session_day_key;
   bool              m_day_halt;
   bool              m_week_halt;
   datetime          m_flatten_started;

public:
            CAntiBlowup(): m_session_failures(0), m_session_day_key(-1),
                           m_day_halt(false), m_week_halt(false), m_flatten_started(0) {}

   void Init(const SAntiBlowupConfig &cfg) { m_cfg = cfg; }

   int SessionDayKey() const
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      return dt.year * 10000 + dt.mon * 100 + dt.day;
     }

   void ResetSessionIfNeeded()
     {
      const int key = SessionDayKey();
      if(key != m_session_day_key)
        {
         m_session_day_key  = key;
         m_session_failures = 0;
         m_day_halt         = false;
        }
     }

   bool DayHalt() const { return m_day_halt; }
   bool WeekHalt() const { return m_week_halt; }

   ENUM_RLVR_CB_REASON Check(const CRiskManager &risk,
                             const double floating_pnl) const
     {
      if(risk.BasketDdBreached(floating_pnl))
         return RLVR_CB_BASKET_DD;
      if(risk.DailyDdBreached(floating_pnl))
         return RLVR_CB_DAILY_DD;
      if(risk.WeeklyDdBreached(floating_pnl))
         return RLVR_CB_WEEKLY_DD;
      if(risk.MarginBreached())
         return RLVR_CB_MARGIN;
      if(m_session_failures >= m_cfg.max_session_failures_before_halt)
         return RLVR_CB_SESSION_FAILURES;
      return RLVR_CB_NONE;
     }

   int CooldownSeconds(const ENUM_RLVR_CB_REASON reason,
                       const bool emergency) const
     {
      if(reason == RLVR_CB_DAILY_DD)
         return 24 * 3600;
      if(reason == RLVR_CB_WEEKLY_DD)
         return 7 * 24 * 3600;
      if(emergency)
         return m_cfg.cooldown_after_emergency_seconds;
      return m_cfg.cooldown_after_normal_exit_seconds;
     }

   bool FlattenAll(CRLVRTradeUtils &trade,
                   CBasketManager &basket_mgr,
                   CRegimeFilter &regime,
                   const ENUM_RLVR_CB_REASON reason,
                   SReplayEvent &event_out)
     {
      double closed = 0.0;
      const int n = trade.CloseAllByMagic(closed);
      basket_mgr.ClearBasket();

      if(reason == RLVR_CB_DAILY_DD)
         m_day_halt = true;
      if(reason == RLVR_CB_WEEKLY_DD)
         m_week_halt = true;
      if(reason == RLVR_CB_INVALIDATION ||
         reason == RLVR_CB_BASKET_DD ||
         reason == RLVR_CB_MARGIN)
         m_session_failures++;

      const bool emergency = (reason != RLVR_CB_NONE);
      regime.SetCooldownUntil(TimeCurrent() + CooldownSeconds(reason, emergency));

      event_out.timestamp  = TimeCurrent();
      event_out.event_type = "FLATTEN";
      event_out.message    = StringFormat("AntiBlowup flatten reason=%d closed=%d", (int)reason, n);
      return true;
     }

   void RecordDefensiveShutdown()
     {
      m_session_failures++;
     }
  };
// ===== END AntiBlowup =====

// ===== BEGIN RegimeFilter =====
//+------------------------------------------------------------------+
//| RegimeFilter.mqh — spec §6 (simplified v1)                       |
//+------------------------------------------------------------------+


class CRegimeFilter
  {
private:
   SSessionConfig  m_session;
   SRegimeConfig   m_regime;
   string          m_symbol;
   double          m_baseline_spread;
   datetime        m_cooldown_until;

public:
   void Init(const string symbol,
             const SSessionConfig &session,
             const SRegimeConfig &regime,
             const double baseline_spread)
     {
      m_symbol          = symbol;
      m_session         = session;
      m_regime          = regime;
      m_baseline_spread = baseline_spread;
      m_cooldown_until  = 0;
     }

   void SetCooldownUntil(const datetime until) { m_cooldown_until = until; }
   datetime CooldownUntil() const { return m_cooldown_until; }

   bool SessionLiquid(const datetime t) const
     {
      MqlDateTime dt;
      TimeToStruct(t, dt);
      if(m_session.allow_asia_trading)
         return true;
      return (dt.hour >= m_session.liquid_session_start_hour &&
              dt.hour < m_session.liquid_session_end_hour);
     }

   bool RolloverLock(const datetime t) const
     {
      MqlDateTime dt;
      TimeToStruct(t, dt);
      const int mins = dt.hour * 60 + dt.min;
      const int lock = m_session.rollover_lock_minutes;
      if(mins < lock)
         return true;
      if(mins >= (24 * 60 - lock))
         return true;
      return false;
     }

   bool SpreadOk(const double spread) const
     {
      if(m_baseline_spread <= 0.0)
         return true;
      return spread <= m_regime.spread_ok_mult * m_baseline_spread;
     }

   bool VolOk(const double atr_m15) const
     {
      if(m_regime.max_chaos_atr_m15 <= 0.0)
         return true;
      return atr_m15 <= m_regime.max_chaos_atr_m15;
     }

   bool NotRunaway(const double atr_h1) const
     {
      const double price_now = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      const int shift_4h = iBarShift(m_symbol, PERIOD_H1, TimeCurrent() - 4 * 3600);
      if(shift_4h < 0)
         return true;
      const double price_then = iClose(m_symbol, PERIOD_H1, shift_4h);
      const double displacement = MathAbs(price_now - price_then);
      if(displacement <= m_regime.runaway_displacement_mult * atr_h1)
         return true;

      double extreme = price_now;
      for(int i = 0; i <= shift_4h; i++)
        {
         const double hi = iHigh(m_symbol, PERIOD_H1, i);
         const double lo = iLow(m_symbol, PERIOD_H1, i);
         if(price_now > price_then)
            extreme = MathMin(extreme, lo);
         else
            extreme = MathMax(extreme, hi);
        }
      const double pullback = MathAbs(price_now - extreme);
      return pullback >= m_regime.runaway_pullback_min_mult * atr_h1;
     }

   bool CanArmNewLevels(const datetime t,
                        const double spread,
                        const double atr_m15,
                        const double atr_h1,
                        const CRiskManager &risk,
                        const double floating_pnl,
                        const bool has_basket) const
     {
      if(TimeCurrent() < m_cooldown_until)
         return false;
      if(has_basket)
         return false;
      if(!SessionLiquid(t))
         return false;
      if(RolloverLock(t))
         return false;
      if(!SpreadOk(spread))
         return false;
      if(!VolOk(atr_m15))
         return false;
      if(!NotRunaway(atr_h1))
         return false;
      if(risk.DailyDdBreached(floating_pnl))
         return false;
      return true;
     }
  };
// ===== END RegimeFilter =====

// ===== BEGIN LevelsEngine =====
//+------------------------------------------------------------------+
//| LevelsEngine.mqh — spec §5                                       |
//+------------------------------------------------------------------+


class CLevelsEngine
  {
private:
   string         m_symbol;
   SLevelsConfig  m_cfg;
   SLiquidityLevel m_levels[];
   int            m_count;
   datetime       m_last_d1_bar;
   int            m_last_asia_day;
   int            m_last_london_day;
   bool           m_auto_pdh_pdl;
   bool           m_auto_session;
   bool           m_auto_round;

   int FindIndexById(const string id) const
     {
      for(int i = 0; i < m_count; i++)
         if(m_levels[i].level_id == id)
            return i;
      return -1;
     }

   void UpsertLevel(const SLiquidityLevel &incoming)
     {
      const int existing = FindIndexById(incoming.level_id);
      if(existing >= 0)
        {
         m_levels[existing] = incoming;
         return;
        }
      if(m_count >= RLVR_MAX_LEVELS)
         return;
      m_levels[m_count] = incoming;
      m_count++;
     }

   double MergeDistance(const double atr_m15, const double spread) const
     {
      const double by_atr = m_cfg.level_merge_distance_atr * atr_m15;
      const double by_spread = spread * 5.0;
      return MathMax(by_atr, by_spread);
     }

   void RemoveIndex(const int idx)
     {
      for(int i = idx; i < m_count - 1; i++)
         m_levels[i] = m_levels[i + 1];
      m_count--;
     }

   void ApplyMerge(const double merge_distance)
     {
      for(int i = 0; i < m_count; i++)
        {
         for(int j = i + 1; j < m_count; )
           {
            if(MathAbs(m_levels[i].price - m_levels[j].price) <= merge_distance)
              {
               const int pi = RLVR_LevelTypePriority(m_levels[i].type);
               const int pj = RLVR_LevelTypePriority(m_levels[j].type);
               if(pi < pj)
                  RemoveIndex(j);
               else if(pj < pi)
                 {
                  RemoveIndex(i);
                  i--;
                  break;
                 }
               else if(m_levels[i].quality_score >= m_levels[j].quality_score)
                  RemoveIndex(j);
               else
                 {
                  RemoveIndex(i);
                  i--;
                  break;
                 }
              }
            else
               j++;
           }
        }
     }

   void PruneExpired(const datetime now)
     {
      for(int i = m_count - 1; i >= 0; i--)
        {
         if(m_levels[i].expires_at > 0 && now >= m_levels[i].expires_at)
            RemoveIndex(i);
         else if(m_levels[i].state == RLVR_STATE_EXPIRED)
            RemoveIndex(i);
        }
     }

   datetime EndOfBrokerDay(const datetime t) const
     {
      MqlDateTime dt;
      TimeToStruct(t, dt);
      dt.hour = 23;
      dt.min  = 59;
      dt.sec  = 59;
      return StructToTime(dt);
     }

   void PublishPDHPDL(const datetime now)
     {
      const double pdh = iHigh(m_symbol, PERIOD_D1, 1);
      const double pdl = iLow(m_symbol, PERIOD_D1, 1);
      if(pdh <= 0.0 || pdl <= 0.0)
         return;

      MqlDateTime dt;
      TimeToStruct(now, dt);
      const string day = StringFormat("%04d-%02d-%02d", dt.year, dt.mon, dt.day);

      SLiquidityLevel lvl;
      RLVR_InitLevel(lvl);
      lvl.created_at    = now;
      lvl.expires_at    = EndOfBrokerDay(now);
      lvl.quality_score = 0.85;
      lvl.state         = RLVR_STATE_ARMED;

      lvl.type     = RLVR_LEVEL_PDH;
      lvl.price    = pdh;
      lvl.level_id = "PDH_" + day;
      UpsertLevel(lvl);

      RLVR_InitLevel(lvl);
      lvl.created_at    = now;
      lvl.expires_at    = EndOfBrokerDay(now);
      lvl.quality_score = 0.85;
      lvl.state         = RLVR_STATE_ARMED;
      lvl.type          = RLVR_LEVEL_PDL;
      lvl.price         = pdl;
      lvl.level_id      = "PDL_" + day;
      UpsertLevel(lvl);
     }

   bool CopySessionRange(const datetime from,
                         const datetime to,
                         double &hi,
                         double &lo) const
     {
      hi = -DBL_MAX;
      lo = DBL_MAX;
      if(to <= from)
         return false;

      MqlRates rates[];
      const int copied = CopyRates(m_symbol, PERIOD_M5, from, to, rates);
      if(copied <= 0)
         return false;

      for(int i = 0; i < copied; i++)
        {
         if(rates[i].high > hi)
            hi = rates[i].high;
         if(rates[i].low < lo)
            lo = rates[i].low;
        }
      return (hi > lo);
     }

   void PublishSessionHL(const string prefix,
                         const ENUM_RLVR_LEVEL_TYPE type_h,
                         const ENUM_RLVR_LEVEL_TYPE type_l,
                         const double hi,
                         const double lo,
                         const datetime now,
                         const datetime expires)
     {
      SLiquidityLevel lvl;
      RLVR_InitLevel(lvl);
      lvl.created_at    = now;
      lvl.expires_at    = expires;
      lvl.quality_score = 0.75;
      lvl.state         = RLVR_STATE_ARMED;

      lvl.type     = type_h;
      lvl.price    = hi;
      lvl.level_id = prefix + "_H";
      UpsertLevel(lvl);

      RLVR_InitLevel(lvl);
      lvl.type     = type_l;
      lvl.price    = lo;
      lvl.level_id = prefix + "_L";
      UpsertLevel(lvl);
     }

public:
   bool Init(const string symbol, const SLevelsConfig &cfg)
     {
      m_symbol          = symbol;
      m_cfg             = cfg;
      m_count           = 0;
      m_last_d1_bar     = 0;
      m_last_asia_day   = -1;
      m_last_london_day = -1;
      m_auto_pdh_pdl    = true;
      m_auto_session    = true;
      m_auto_round      = true;
      ArrayResize(m_levels, RLVR_MAX_LEVELS);
      return true;
     }

   void SetAutoDiscovery(const bool pdh_pdl,
                         const bool session_levels,
                         const bool round_levels)
     {
      m_auto_pdh_pdl = pdh_pdl;
      m_auto_session = session_levels;
      m_auto_round   = round_levels;
     }

   void OnNewM5Bar(const datetime bar_time,
                   const double bid,
                   const double spread,
                   const double atr_m15,
                   const double atr_h1)
     {
      PruneExpired(bar_time);

      const datetime d1_time = iTime(m_symbol, PERIOD_D1, 0);
      if(m_auto_pdh_pdl && d1_time > 0 && d1_time != m_last_d1_bar)
        {
         m_last_d1_bar = d1_time;
         PublishPDHPDL(bar_time);
        }

      MqlDateTime dt;
      TimeToStruct(bar_time, dt);
      const int day_key = dt.year * 10000 + dt.mon * 100 + dt.day;

      if(m_auto_session && dt.hour == 8 && dt.min < 5 && m_last_asia_day != day_key)
        {
         MqlDateTime start = dt;
         start.hour = 0;
         start.min  = 0;
         start.sec  = 0;
         MqlDateTime end = dt;
         end.hour = 7;
         end.min  = 59;
         end.sec  = 59;
         double hi, lo;
         if(CopySessionRange(StructToTime(start), StructToTime(end), hi, lo))
           {
            const datetime expires = StructToTime(end) + 4 * 3600;
            PublishSessionHL("ASIA", RLVR_LEVEL_ASIA_H, RLVR_LEVEL_ASIA_L,
                             hi, lo, bar_time, expires);
           }
         m_last_asia_day = day_key;
        }

      if(m_auto_session && dt.hour == 13 && dt.min < 5 && m_last_london_day != day_key)
        {
         MqlDateTime start = dt;
         start.hour = 8;
         start.min  = 0;
         start.sec  = 0;
         MqlDateTime end = dt;
         end.hour = 12;
         end.min  = 59;
         end.sec  = 59;
         double hi, lo;
         if(CopySessionRange(StructToTime(start), StructToTime(end), hi, lo))
           {
            const datetime expires = StructToTime(end) + 4 * 3600;
            PublishSessionHL("LONDON", RLVR_LEVEL_LONDON_H, RLVR_LEVEL_LONDON_L,
                             hi, lo, bar_time, expires);
           }
         m_last_london_day = day_key;
        }

      if(m_auto_round && atr_h1 > 0.0)
        {
         const double step = m_cfg.round_step;
         const double nearest = MathRound(bid / step) * step;
         if(MathAbs(bid - nearest) <= 0.5 * atr_h1)
           {
            SLiquidityLevel rnd;
            RLVR_InitLevel(rnd);
            rnd.type          = RLVR_LEVEL_ROUND;
            rnd.price         = nearest;
            rnd.level_id      = StringFormat("ROUND_%.0f", nearest);
            rnd.created_at    = bar_time;
            rnd.expires_at    = bar_time + 12 * 3600;
            rnd.quality_score = 0.60;
            rnd.state         = RLVR_STATE_ARMED;
            UpsertLevel(rnd);
           }
        }

      ApplyMerge(MergeDistance(atr_m15, spread));
     }

   bool AddManualLevel(const SLiquidityLevel &manual)
     {
      if(manual.price <= 0.0)
         return false;
      UpsertLevel(manual);
      return true;
     }

   int GetActiveLevels(SLiquidityLevel &out[],
                       const datetime now) const
     {
      int n = 0;
      for(int i = 0; i < m_count; i++)
        {
         const SLiquidityLevel lvl = m_levels[i];
         if(lvl.state != RLVR_STATE_ARMED &&
            lvl.state != RLVR_STATE_SWEEP_DETECTED &&
            lvl.state != RLVR_STATE_RECLAIM_CONFIRMED)
            continue;
         if(lvl.created_at > now || (lvl.expires_at > 0 && now >= lvl.expires_at))
            continue;
         if(lvl.quality_score < m_cfg.level_quality_threshold)
            continue;
         ArrayResize(out, n + 1);
         out[n] = lvl;
         n++;
        }

      for(int a = 0; a < n - 1; a++)
        {
         for(int b = a + 1; b < n; b++)
           {
            bool swap = false;
            if(out[b].quality_score > out[a].quality_score)
               swap = true;
            else if(out[b].quality_score == out[a].quality_score &&
                    out[b].created_at < out[a].created_at)
               swap = true;
            if(swap)
              {
               SLiquidityLevel tmp = out[a];
               out[a] = out[b];
               out[b] = tmp;
              }
           }
        }

      if(n > m_cfg.max_armed_levels)
        {
         ArrayResize(out, m_cfg.max_armed_levels);
         return m_cfg.max_armed_levels;
        }
      return n;
     }

   bool UpdateLevel(const SLiquidityLevel &level)
     {
      const int idx = FindIndexById(level.level_id);
      if(idx < 0)
         return false;
      m_levels[idx] = level;
      return true;
     }

   int RegistryCount() const { return m_count; }
  };
// ===== END LevelsEngine =====

// ===== BEGIN StateMachine =====
//+------------------------------------------------------------------+
//| StateMachine.mqh — full RLVR controller (spec §10)               |
//+------------------------------------------------------------------+


class CRLVRController
  {
private:
   SStructureConfig   m_structure;
   SRecoveryConfig    m_recovery;
   SExitConfig        m_exit;
   SAntiBlowupConfig  m_ab_cfg;
   CSweepDetector     m_sweep;
   CReclaimDetector   m_reclaim;
   CInvalidation      m_invalidation;
   CEntryEngine       m_entry;
   CRecoveryEngine    m_recovery_engine;
   CExitManager       m_exit_mgr;
   CAntiBlowup        m_antiblowup;
   CRegimeFilter      m_regime;
   CRiskManager       m_risk;
   CRLVRTradeUtils    m_trade;
   CBasketManager     m_basket;
   CLevelsEngine     *m_levels;
   CRLVRTelemetry    *m_telemetry;

   ENUM_RLVR_EA_STATE m_ea_state;
   int                m_bar_counter;
   bool               m_soft_invalidation;
   SLiquidityLevel    m_tracked_level;
   bool               m_has_tracked_level;

   void Emit(const SReplayEvent &event) const
     {
      m_telemetry.LogPrint(event);
      m_telemetry.LogEvent(event);
     }

   void FlattenBasket(const ENUM_RLVR_CB_REASON reason,
                      const string message_extra = "")
     {
      const double floating = m_basket.FloatingPnl(m_trade.IsDryRun());
      SReplayEvent flat;
      m_antiblowup.FlattenAll(m_trade, m_basket, m_regime, reason, flat);
      if(message_extra != "")
         flat.message = flat.message + " " + message_extra;
      Emit(flat);
      m_risk.AddClosedPnl(floating);
      m_ea_state          = RLVR_EA_COOLDOWN;
      m_has_tracked_level = false;
      m_soft_invalidation = false;
     }

   void CopyBackLevels(SLiquidityLevel &active[], const int count)
     {
      for(int i = 0; i < count; i++)
         m_levels.UpdateLevel(active[i]);
     }

   bool SoftInvalidationActive(const SRlvrBasket &basket) const
     {
      if(!basket.active)
         return false;
      const int age_limit = (int)(m_structure.reclaim_ttl_seconds * 0.5);
      if(basket.open_time <= 0 || (TimeCurrent() - basket.open_time) < age_limit)
         return false;
      const double floating = m_basket.FloatingPnl(m_trade.IsDryRun());
      const double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0.0)
         return false;
      const double dd = (-MathMin(0.0, floating)) / equity;
      return dd > 0.5 * m_risk.Config().basket_dd_limit;
     }

   void CloseBasketNormal(const string event_type, const string message)
     {
      SReplayEvent ev;
      ev.timestamp  = TimeCurrent();
      ev.event_type = event_type;
      ev.message    = message;
      Emit(ev);
      FlattenBasket(RLVR_CB_NONE, message);
     }

   void ManageBasket(const MqlRates &bar,
                     const double atr_m5,
                     const double bid,
                     const double ask,
                     const double spread)
     {
      m_basket.SyncFromMarket(m_trade.IsDryRun());
      if(!m_basket.HasActiveBasket())
        {
         if(m_ea_state == RLVR_EA_BASKET_ACTIVE)
            m_ea_state = RLVR_EA_IDLE;
         return;
        }

      m_ea_state = RLVR_EA_BASKET_ACTIVE;
      SRlvrBasket basket = m_basket.Basket();
      double floating = m_basket.FloatingPnl(m_trade.IsDryRun());

      ENUM_RLVR_CB_REASON cb = m_antiblowup.Check(m_risk, floating);
      if(cb != RLVR_CB_NONE)
        {
         FlattenBasket(cb);
         return;
        }

      if(m_has_tracked_level)
        {
         SLiquidityLevel lvl = m_tracked_level;
         SReplayEvent inv_ev;
         if(m_invalidation.Process(lvl, bar, atr_m5, m_bar_counter, inv_ev))
           {
            Emit(inv_ev);
            m_antiblowup.RecordDefensiveShutdown();
            FlattenBasket(RLVR_CB_INVALIDATION);
            m_tracked_level.state = RLVR_STATE_EXPIRED;
            m_levels.UpdateLevel(m_tracked_level);
            return;
           }
         m_tracked_level = lvl;
        }

      if(basket.entry_atr_m5 > 0.0 &&
         atr_m5 > m_ab_cfg.vol_kill_atr_mult * basket.entry_atr_m5)
        {
         m_soft_invalidation = true;
        }
      if(basket.entry_spread > 0.0 &&
         spread > m_ab_cfg.spread_kill_mult * basket.entry_spread)
        {
         m_soft_invalidation = true;
        }
      if(SoftInvalidationActive(basket))
         m_soft_invalidation = true;

      SReplayEvent ev;
      if(m_exit_mgr.PartialAtMidpoint(m_basket.Basket(), bar, floating,
                                      m_risk.Config().basket_dd_limit,
                                      m_trade, ev))
        {
         Emit(ev);
         basket = m_basket.Basket();
        }

      m_exit_mgr.UpdateTrail(m_basket.Basket(), atr_m5);
      if(m_exit_mgr.TrailStopHit(m_basket.Basket(), bid, ask, ev))
        {
         CloseBasketNormal("TRAIL_EXIT", ev.message);
         return;
        }

      if(m_exit_mgr.BasketTakeProfit(m_basket.Basket(), atr_m5, floating, ev))
        {
         CloseBasketNormal("BASKET_TP", ev.message);
         return;
        }

      if(m_exit_mgr.TimeScratchExit(m_basket.Basket(), floating,
                                      m_risk.Config().basket_dd_limit, ev))
        {
         CloseBasketNormal("TIME_EXIT", ev.message);
         return;
        }

      if(m_has_tracked_level && !m_soft_invalidation)
        {
         SLiquidityLevel lvl = m_tracked_level;
         const bool forbidden = m_recovery_engine.RecoveryForbidden(
            lvl, m_basket.Basket(), bar, atr_m5, spread,
            m_soft_invalidation, m_risk.DailyDdBreached(floating));
         if(m_recovery_engine.TryAddNextRung(lvl, m_basket, bar, atr_m5, spread,
                                             m_trade, forbidden, ev))
           {
            Emit(ev);
            m_tracked_level = lvl;
           }
        }

      floating = m_basket.FloatingPnl(m_trade.IsDryRun());
      if(floating < 0.0)
         m_basket.Basket().state = RLVR_BASKET_CONTROLLED_ADVERSE;
      else
         m_basket.Basket().state = RLVR_BASKET_PROFIT_COMPRESSION;
     }

   void ProcessStructureScan(const MqlRates &bar,
                             const double atr_m5,
                             const double bid,
                             const double spread,
                             const double atr_m15,
                             const double atr_h1,
                             const bool can_arm)
     {
      if(!can_arm)
         return;

      SLiquidityLevel active[];
      const int active_count = m_levels.GetActiveLevels(active, bar.time);
      if(active_count <= 0)
         return;

      for(int i = 0; i < active_count; i++)
        {
         if(m_basket.HasActiveBasket() &&
            active[i].state != RLVR_STATE_RECLAIM_CONFIRMED)
            continue;

         SReplayEvent batch[];
         const int sweep_events = m_sweep.Process(active[i], bar, atr_m5,
                                                  m_bar_counter, batch);
         for(int e = 0; e < sweep_events; e++)
            Emit(batch[e]);

         if(active[i].state == RLVR_STATE_SWEEP_DETECTED)
           {
            if(active[i].entry_atr_m5 <= 0.0)
              {
               active[i].entry_atr_m5 = atr_m5;
               active[i].entry_spread = spread;
              }

            if(m_sweep.SweepWindowExpired(active[i], m_bar_counter))
              {
               active[i].state = RLVR_STATE_EXPIRED;
               SReplayEvent ev;
               ev.timestamp     = bar.time;
               ev.event_type    = "SWEEP_TIMEOUT";
               ev.level_id      = active[i].level_id;
               ev.level_price   = active[i].price;
               ev.bar_index     = m_bar_counter;
               ev.atr_m5        = atr_m5;
               ev.message       = "Sweep window expired without reclaim";
               Emit(ev);
               continue;
              }

            if(m_sweep.ReclaimTtlExpired(active[i], bar.time))
              {
               active[i].state = RLVR_STATE_EXPIRED;
               SReplayEvent ev;
               ev.timestamp  = bar.time;
               ev.event_type = "RECLAIM_TTL_EXPIRED";
               ev.level_id   = active[i].level_id;
               ev.message    = "Reclaim TTL expired";
               Emit(ev);
               continue;
              }

            SReplayEvent reclaim_ev;
            if(m_reclaim.Process(active[i], bar, atr_m5, m_bar_counter, reclaim_ev))
              {
               Emit(reclaim_ev);
               if(!m_basket.HasActiveBasket() && can_arm)
                 {
                  SReplayEvent r0_ev;
                  if(m_entry.OpenR0(active[i], m_basket, m_trade, m_risk,
                                    m_recovery, r0_ev))
                    {
                     r0_ev.bar_index = m_bar_counter;
                     Emit(r0_ev);
                     m_tracked_level     = active[i];
                     m_tracked_level.state = RLVR_STATE_CONSUMED;
                     m_has_tracked_level = true;
                     m_ea_state          = RLVR_EA_BASKET_ACTIVE;
                     m_soft_invalidation = false;
                    }
                 }
              }
           }

         if(active[i].state == RLVR_STATE_RECLAIM_CONFIRMED && !m_basket.HasActiveBasket())
           {
            SReplayEvent inv_ev;
            if(m_invalidation.Process(active[i], bar, atr_m5, m_bar_counter, inv_ev))
               Emit(inv_ev);
           }
        }

      CopyBackLevels(active, active_count);
     }

public:
   void Init(CLevelsEngine &levels,
             CRLVRTelemetry &telemetry,
             const string symbol,
             const ulong magic,
             const bool dry_run,
             const double baseline_spread,
             const SStructureConfig &structure,
             const SRecoveryConfig &recovery,
             const SExitConfig &exit_cfg,
             const SRiskConfig &risk_cfg,
             const SAntiBlowupConfig &ab_cfg,
             const SSessionConfig &session_cfg,
             const SRegimeConfig &regime_cfg)
     {
      m_levels      = &levels;
      m_telemetry   = &telemetry;
      m_structure   = structure;
      m_recovery    = recovery;
      m_exit        = exit_cfg;
      m_ab_cfg      = ab_cfg;

      m_sweep.Init(structure);
      m_reclaim.Init(structure);
      m_invalidation.Init(structure);
      m_entry.Init(structure);
      m_recovery_engine.Init(recovery, structure);
      m_exit_mgr.Init(exit_cfg, structure);
      m_antiblowup.Init(ab_cfg);
      m_regime.Init(symbol, session_cfg, regime_cfg, baseline_spread);
      m_risk.Init(risk_cfg);
      m_trade.Init(symbol, magic, dry_run);
      m_basket.Init(symbol, magic);

      m_ea_state          = RLVR_EA_IDLE;
      m_bar_counter       = 0;
      m_soft_invalidation = false;
      m_has_tracked_level = false;
     }

   void OnTimer()
     {
      m_risk.OnBalanceUpdate();
      m_antiblowup.ResetSessionIfNeeded();

      if(m_ea_state == RLVR_EA_DEFENSIVE_HALT || m_antiblowup.DayHalt())
         return;

      if(m_ea_state == RLVR_EA_COOLDOWN)
        {
         if(TimeCurrent() >= m_regime.CooldownUntil())
            m_ea_state = RLVR_EA_IDLE;
         return;
        }

      if(!m_basket.HasActiveBasket())
         return;

      const double floating = m_basket.FloatingPnl(m_trade.IsDryRun());
      ENUM_RLVR_CB_REASON cb = m_antiblowup.Check(m_risk, floating);
      if(cb != RLVR_CB_NONE)
         FlattenBasket(cb);
     }

   void OnNewM5Bar(const MqlRates &bar,
                   const double atr_m5,
                   const double bid,
                   const double ask,
                   const double spread,
                   const double atr_m15,
                   const double atr_h1)
     {
      m_bar_counter++;
      m_risk.OnBalanceUpdate();
      m_antiblowup.ResetSessionIfNeeded();

      if(m_ea_state == RLVR_EA_DEFENSIVE_HALT || m_antiblowup.DayHalt())
         return;

      if(m_ea_state == RLVR_EA_COOLDOWN)
        {
         if(TimeCurrent() >= m_regime.CooldownUntil())
            m_ea_state = RLVR_EA_IDLE;
         else
            return;
        }

      m_levels.OnNewM5Bar(bar.time, bid, spread, atr_m15, atr_h1);

      const double floating = m_basket.FloatingPnl(m_trade.IsDryRun());
      const bool can_arm = m_regime.CanArmNewLevels(bar.time, spread, atr_m15, atr_h1,
                                                    m_risk, floating,
                                                    m_basket.HasActiveBasket());

      if(m_basket.HasActiveBasket())
         ManageBasket(bar, atr_m5, bid, ask, spread);
      else
         ProcessStructureScan(bar, atr_m5, bid, spread, atr_m15, atr_h1, can_arm);
     }

   bool IsDryRun() const { return m_trade.IsDryRun(); }
   ENUM_RLVR_EA_STATE EaState() const { return m_ea_state; }
  };

// Backward-compatible alias
class CRLVRStateMachine : public CRLVRController {};
// ===== END StateMachine =====

//+------------------------------------------------------------------+
//| EA ENTRY POINT
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| RLVR_EA.mq5 — Reclaimed Liquidity Void Reset (full build v1)     |
//+------------------------------------------------------------------+


//--- mode
input bool   InpDryRun              = true;
input ulong  InpMagic               = RLVR_DEFAULT_MAGIC;
input string InpTelemetryFile       = "RLVR_events.csv";

//--- levels
input bool   InpAutoPdhPdl          = true;
input bool   InpAutoSessionLevels   = true;
input bool   InpAutoRoundLevels     = true;
input bool   InpManualLevelEnable   = false;
input double InpManualLevelPrice    = 2400.0;
input string InpManualLevelId       = "MANUAL_LEVEL";
input double InpManualQuality       = 0.90;

//--- structure
input bool   InpReclaimBodyFilter   = true;
input int    InpAtrPeriod           = 14;
input double InpBaselineSpread      = 0.30;

//--- risk (prop-style defaults)
input double InpRiskPerBasket       = 0.0125;
input double InpBasketDdLimit       = 0.0125;
input double InpDailyDdLimit        = 0.025;
input double InpWeeklyDdLimit       = 0.05;
input double InpMarginLimit         = 0.25;

//--- session / regime
input bool   InpAllowAsiaTrading    = false;
input int    InpLiquidStartHour     = 7;
input int    InpLiquidEndHour       = 21;
input double InpMaxChaosAtrM15      = 0.0;

CLevelsEngine      g_levels;
CRLVRController    g_controller;
CRLVRTelemetry     g_telemetry;

SStructureConfig   g_structure;
SLevelsConfig      g_levels_cfg;
SRecoveryConfig    g_recovery;
SExitConfig        g_exit;
SRiskConfig        g_risk;
SAntiBlowupConfig  g_antiblowup;
SSessionConfig     g_session;
SRegimeConfig      g_regime;

datetime           g_last_m5_bar_time = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   RLVR_LoadDefaultStructureConfig(g_structure);
   RLVR_LoadDefaultLevelsConfig(g_levels_cfg);
   RLVR_LoadDefaultRecoveryConfig(g_recovery);
   RLVR_LoadDefaultExitConfig(g_exit);
   RLVR_LoadDefaultRiskConfig(g_risk);
   RLVR_LoadDefaultAntiBlowupConfig(g_antiblowup);
   RLVR_LoadDefaultSessionConfig(g_session);
   RLVR_LoadDefaultRegimeConfig(g_regime);

   g_structure.reclaim_body_filter = InpReclaimBodyFilter;
   g_risk.risk_per_basket          = InpRiskPerBasket;
   g_risk.basket_dd_limit          = InpBasketDdLimit;
   g_risk.daily_dd_limit           = InpDailyDdLimit;
   g_risk.weekly_dd_limit          = InpWeeklyDdLimit;
   g_risk.margin_limit             = InpMarginLimit;
   g_session.allow_asia_trading    = InpAllowAsiaTrading;
   g_session.liquid_session_start_hour = InpLiquidStartHour;
   g_session.liquid_session_end_hour   = InpLiquidEndHour;
   g_regime.max_chaos_atr_m15      = InpMaxChaosAtrM15;

   if(!g_levels.Init(_Symbol, g_levels_cfg))
      return INIT_FAILED;

   g_levels.SetAutoDiscovery(InpAutoPdhPdl, InpAutoSessionLevels, InpAutoRoundLevels);

   if(InpManualLevelEnable)
     {
      SLiquidityLevel manual;
      RLVR_InitLevel(manual);
      manual.level_id      = InpManualLevelId;
      manual.type          = RLVR_LEVEL_MANUAL;
      manual.price         = InpManualLevelPrice;
      manual.quality_score = InpManualQuality;
      manual.created_at    = TimeCurrent();
      manual.expires_at    = TimeCurrent() + 7 * 24 * 3600;
      manual.state         = RLVR_STATE_ARMED;
      g_levels.AddManualLevel(manual);
     }

   if(!g_telemetry.Open(InpTelemetryFile, true))
      return INIT_FAILED;

   g_controller.Init(g_levels, g_telemetry, _Symbol, InpMagic, InpDryRun,
                     InpBaselineSpread, g_structure, g_recovery, g_exit,
                     g_risk, g_antiblowup, g_session, g_regime);

   EventSetTimer(1);

   Print("RLVR v2 started | dry_run=", InpDryRun,
         " | magic=", InpMagic,
         " | telemetry=", InpTelemetryFile);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   g_telemetry.Close();
   Print("RLVR stopped. reason=", reason);
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   g_controller.OnTimer();
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   const datetime bar_time = iTime(_Symbol, PERIOD_M5, 0);
   if(bar_time == 0 || bar_time == g_last_m5_bar_time)
      return;

   g_last_m5_bar_time = bar_time;

   MqlRates bars[];
   ArraySetAsSeries(bars, true);
   if(CopyRates(_Symbol, PERIOD_M5, 1, 1, bars) != 1)
      return;

   const double atr_m5  = RLVR_GetAtr(_Symbol, PERIOD_M5, InpAtrPeriod, 1);
   const double atr_m15 = RLVR_GetAtr(_Symbol, PERIOD_M15, InpAtrPeriod, 1);
   const double atr_h1  = RLVR_GetAtr(_Symbol, PERIOD_H1, InpAtrPeriod, 1);
   const double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double spread  = ask - bid;

   if(atr_m5 <= 0.0)
      return;

   g_controller.OnNewM5Bar(bars[0], atr_m5, bid, ask, spread, atr_m15, atr_h1);
  }

//+------------------------------------------------------------------+
