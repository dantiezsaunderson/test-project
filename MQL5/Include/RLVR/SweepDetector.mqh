//+------------------------------------------------------------------+
//| SweepDetector.mqh — spec §7 (parity: tools/rlvr_replay/sweep.py)|
//+------------------------------------------------------------------+
#ifndef __RLVR_SWEEP_DETECTOR_MQH__
#define __RLVR_SWEEP_DETECTOR_MQH__

#include "Types.mqh"

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
      ArrayResize(events, RLVR_MAX_EVENTS_PER_BAR);
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

#endif
