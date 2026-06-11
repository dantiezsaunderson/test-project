//+------------------------------------------------------------------+
//| RegimeFilter.mqh — spec §6 (simplified v1)                       |
//+------------------------------------------------------------------+
#ifndef __RLVR_REGIME_FILTER_MQH__
#define __RLVR_REGIME_FILTER_MQH__

#include "Types.mqh"
#include "AtrUtils.mqh"
#include "RiskManager.mqh"

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

#endif
