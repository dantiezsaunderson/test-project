//+------------------------------------------------------------------+
//| RiskManager.mqh — spec §14                                       |
//+------------------------------------------------------------------+
#ifndef __RLVR_RISK_MANAGER_MQH__
#define __RLVR_RISK_MANAGER_MQH__

#include "Types.mqh"
#include "TradeUtils.mqh"

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

   SRiskConfig Config() const { return m_cfg; }

   void AddClosedPnl(const double pnl) { m_daily_closed_pnl += pnl; }
  };

#endif
