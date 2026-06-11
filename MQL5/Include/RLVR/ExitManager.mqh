//+------------------------------------------------------------------+
//| ExitManager.mqh — spec §13                                       |
//+------------------------------------------------------------------+
#ifndef __RLVR_EXIT_MANAGER_MQH__
#define __RLVR_EXIT_MANAGER_MQH__

#include "Types.mqh"
#include "TradeUtils.mqh"
#include "BasketManager.mqh"
#include "RecoveryEngine.mqh"
#include "Config.mqh"

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

   bool PartialAtMidpoint(CBasketManager &basket_mgr,
                          const MqlRates &bar,
                          const double floating_pnl,
                          const double basket_dd_limit,
                          CRLVRTradeUtils &trade,
                          SReplayEvent &event_out)
     {
      SRlvrBasket basket = basket_mgr.GetBasket();
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

      basket_mgr.ApplyPartialClose();

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

   bool TrailStopHit(const SRlvrBasket &basket,
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

   void UpdateTrail(CBasketManager &basket_mgr, const double atr_m5)
     {
      basket_mgr.UpdateTrailStop(atr_m5, m_cfg.trail_buffer_atr);
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

#endif
