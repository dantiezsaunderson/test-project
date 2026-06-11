//+------------------------------------------------------------------+
//| RecoveryEngine.mqh — R1–R4 (spec §12)                            |
//+------------------------------------------------------------------+
#ifndef __RLVR_RECOVERY_ENGINE_MQH__
#define __RLVR_RECOVERY_ENGINE_MQH__

#include "Types.mqh"
#include "TradeUtils.mqh"
#include "BasketManager.mqh"
#include "Invalidation.mqh"

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
      SRlvrBasket basket = basket_mgr.GetBasket();
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
      basket_mgr.SetState(RLVR_BASKET_RESCUE_ACTIVE);

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

#endif
