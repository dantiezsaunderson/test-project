//+------------------------------------------------------------------+
//| Invalidation.mqh — spec §9                                       |
//+------------------------------------------------------------------+
#ifndef __RLVR_INVALIDATION_MQH__
#define __RLVR_INVALIDATION_MQH__

#include "Types.mqh"

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

#endif
