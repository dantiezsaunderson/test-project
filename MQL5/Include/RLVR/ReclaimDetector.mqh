//+------------------------------------------------------------------+
//| ReclaimDetector.mqh — spec §8                                    |
//+------------------------------------------------------------------+
#ifndef __RLVR_RECLAIM_DETECTOR_MQH__
#define __RLVR_RECLAIM_DETECTOR_MQH__

#include "Types.mqh"

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

#endif
