//+------------------------------------------------------------------+
//| AntiBlowup.mqh — spec §15                                        |
//+------------------------------------------------------------------+
#ifndef __RLVR_ANTI_BLOWUP_MQH__
#define __RLVR_ANTI_BLOWUP_MQH__

#include "Types.mqh"
#include "TradeUtils.mqh"
#include "RiskManager.mqh"
#include "BasketManager.mqh"
#include "RegimeFilter.mqh"

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

#endif
