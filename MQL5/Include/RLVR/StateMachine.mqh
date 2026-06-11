//+------------------------------------------------------------------+
//| StateMachine.mqh — M5 bar orchestrator (parity: replay_engine.py)|
//+------------------------------------------------------------------+
#ifndef __RLVR_STATE_MACHINE_MQH__
#define __RLVR_STATE_MACHINE_MQH__

#include "Types.mqh"
#include "SweepDetector.mqh"
#include "ReclaimDetector.mqh"
#include "Invalidation.mqh"
#include "LevelsEngine.mqh"
#include "Telemetry.mqh"

class CRLVRStateMachine
  {
private:
   SStructureConfig   m_structure;
   CSweepDetector     m_sweep;
   CReclaimDetector   m_reclaim;
   CInvalidation      m_invalidation;
   CLevelsEngine     *m_levels;
   CRLVRTelemetry    *m_telemetry;
   int                m_bar_counter;

   void Emit(CRLVRTelemetry &telemetry, const SReplayEvent &event) const
     {
      telemetry.LogPrint(event);
      telemetry.LogEvent(event);
     }

   void CopyBackLevels(SLiquidityLevel &active[], const int count)
     {
      for(int i = 0; i < count; i++)
         m_levels.UpdateLevel(active[i]);
     }

public:
   void Init(CLevelsEngine &levels,
             CRLVRTelemetry &telemetry,
             const SStructureConfig &structure)
     {
      m_levels      = &levels;
      m_telemetry   = &telemetry;
      m_structure   = structure;
      m_sweep.Init(structure);
      m_reclaim.Init(structure);
      m_invalidation.Init(structure);
      m_bar_counter = 0;
     }

   void OnNewM5Bar(const MqlRates &bar,
                   const double atr_m5,
                   const double bid,
                   const double spread,
                   const double atr_m15,
                   const double atr_h1)
     {
      m_bar_counter++;
      m_levels.OnNewM5Bar(bar.time, bid, spread, atr_m15, atr_h1);

      SLiquidityLevel active[];
      const int active_count = m_levels.GetActiveLevels(active, bar.time);
      if(active_count <= 0)
         return;

      for(int i = 0; i < active_count; i++)
        {
         SReplayEvent batch[];
         const int sweep_events = m_sweep.Process(active[i], bar, atr_m5,
                                                  m_bar_counter, batch);
         for(int e = 0; e < sweep_events; e++)
            Emit(*m_telemetry, batch[e]);

         if(active[i].state == RLVR_STATE_SWEEP_DETECTED)
           {
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
               ev.sweep_extreme = active[i].sweep_extreme;
               ev.message       = "Sweep window expired without reclaim";
               Emit(*m_telemetry, ev);
               continue;
              }

            if(m_sweep.ReclaimTtlExpired(active[i], bar.time))
              {
               active[i].state = RLVR_STATE_EXPIRED;
               SReplayEvent ev;
               ev.timestamp     = bar.time;
               ev.event_type    = "RECLAIM_TTL_EXPIRED";
               ev.level_id      = active[i].level_id;
               ev.level_price   = active[i].price;
               ev.bar_index     = m_bar_counter;
               ev.atr_m5        = atr_m5;
               ev.sweep_extreme = active[i].sweep_extreme;
               ev.message       = "Reclaim TTL expired";
               Emit(*m_telemetry, ev);
               continue;
              }

            SReplayEvent reclaim_ev;
            if(m_reclaim.Process(active[i], bar, atr_m5, m_bar_counter, reclaim_ev))
               Emit(*m_telemetry, reclaim_ev);
           }

         if(active[i].state == RLVR_STATE_RECLAIM_CONFIRMED)
           {
            SReplayEvent inv_ev;
            if(m_invalidation.Process(active[i], bar, atr_m5, m_bar_counter, inv_ev))
               Emit(*m_telemetry, inv_ev);
           }
        }

      CopyBackLevels(active, active_count);
     }
  };

#endif
