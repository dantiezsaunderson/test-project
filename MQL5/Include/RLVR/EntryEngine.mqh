//+------------------------------------------------------------------+
//| EntryEngine.mqh — R0 entry (spec §11)                            |
//+------------------------------------------------------------------+
#ifndef __RLVR_ENTRY_ENGINE_MQH__
#define __RLVR_ENTRY_ENGINE_MQH__

#include "Types.mqh"
#include "TradeUtils.mqh"
#include "BasketManager.mqh"
#include "RiskManager.mqh"

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

#endif
