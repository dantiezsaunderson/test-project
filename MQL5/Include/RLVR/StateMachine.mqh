//+------------------------------------------------------------------+
//| StateMachine.mqh — full RLVR controller (spec §10)               |
//+------------------------------------------------------------------+
#ifndef __RLVR_STATE_MACHINE_MQH__
#define __RLVR_STATE_MACHINE_MQH__

#include "Types.mqh"
#include "Config.mqh"
#include "SweepDetector.mqh"
#include "ReclaimDetector.mqh"
#include "Invalidation.mqh"
#include "LevelsEngine.mqh"
#include "Telemetry.mqh"
#include "TradeUtils.mqh"
#include "RiskManager.mqh"
#include "BasketManager.mqh"
#include "EntryEngine.mqh"
#include "RecoveryEngine.mqh"
#include "ExitManager.mqh"
#include "AntiBlowup.mqh"
#include "RegimeFilter.mqh"

class CRLVRController
  {
private:
   SStructureConfig   m_structure;
   SRecoveryConfig    m_recovery;
   SExitConfig        m_exit;
   SAntiBlowupConfig  m_ab_cfg;
   CSweepDetector     m_sweep;
   CReclaimDetector   m_reclaim;
   CInvalidation      m_invalidation;
   CEntryEngine       m_entry;
   CRecoveryEngine    m_recovery_engine;
   CExitManager       m_exit_mgr;
   CAntiBlowup        m_antiblowup;
   CRegimeFilter      m_regime;
   CRiskManager       m_risk;
   CRLVRTradeUtils    m_trade;
   CBasketManager     m_basket;
   CLevelsEngine     *m_levels;
   CRLVRTelemetry    *m_telemetry;

   ENUM_RLVR_EA_STATE m_ea_state;
   int                m_bar_counter;
   bool               m_soft_invalidation;
   SLiquidityLevel    m_tracked_level;
   bool               m_has_tracked_level;

   void Emit(const SReplayEvent &event) const
     {
      m_telemetry.LogPrint(event);
      m_telemetry.LogEvent(event);
     }

   void FlattenBasket(const ENUM_RLVR_CB_REASON reason,
                      const string message_extra = "")
     {
      const double floating = m_basket.FloatingPnl(m_trade.IsDryRun());
      SReplayEvent flat;
      m_antiblowup.FlattenAll(m_trade, m_basket, m_regime, reason, flat);
      if(message_extra != "")
         flat.message = flat.message + " " + message_extra;
      Emit(flat);
      m_risk.AddClosedPnl(floating);
      m_ea_state          = RLVR_EA_COOLDOWN;
      m_has_tracked_level = false;
      m_soft_invalidation = false;
     }

   void CopyBackLevels(SLiquidityLevel &active[], const int count)
     {
      for(int i = 0; i < count; i++)
         m_levels.UpdateLevel(active[i]);
     }

   bool SoftInvalidationActive(const SRlvrBasket &basket) const
     {
      if(!basket.active)
         return false;
      const int age_limit = (int)(m_structure.reclaim_ttl_seconds * 0.5);
      if(basket.open_time <= 0 || (TimeCurrent() - basket.open_time) < age_limit)
         return false;
      const double floating = m_basket.FloatingPnl(m_trade.IsDryRun());
      const double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0.0)
         return false;
      const double dd = (-MathMin(0.0, floating)) / equity;
      return dd > 0.5 * m_risk.Config().basket_dd_limit;
     }

   void CloseBasketNormal(const string event_type, const string message)
     {
      SReplayEvent ev;
      ev.timestamp  = TimeCurrent();
      ev.event_type = event_type;
      ev.message    = message;
      Emit(ev);
      FlattenBasket(RLVR_CB_NONE, message);
     }

   void ManageBasket(const MqlRates &bar,
                     const double atr_m5,
                     const double bid,
                     const double ask,
                     const double spread)
     {
      m_basket.SyncFromMarket(m_trade.IsDryRun());
      if(!m_basket.HasActiveBasket())
        {
         if(m_ea_state == RLVR_EA_BASKET_ACTIVE)
            m_ea_state = RLVR_EA_IDLE;
         return;
        }

      m_ea_state = RLVR_EA_BASKET_ACTIVE;
      SRlvrBasket basket = m_basket.Basket();
      double floating = m_basket.FloatingPnl(m_trade.IsDryRun());

      ENUM_RLVR_CB_REASON cb = m_antiblowup.Check(m_risk, floating);
      if(cb != RLVR_CB_NONE)
        {
         FlattenBasket(cb);
         return;
        }

      if(m_has_tracked_level)
        {
         SLiquidityLevel lvl = m_tracked_level;
         SReplayEvent inv_ev;
         if(m_invalidation.Process(lvl, bar, atr_m5, m_bar_counter, inv_ev))
           {
            Emit(inv_ev);
            m_antiblowup.RecordDefensiveShutdown();
            FlattenBasket(RLVR_CB_INVALIDATION);
            m_tracked_level.state = RLVR_STATE_EXPIRED;
            m_levels.UpdateLevel(m_tracked_level);
            return;
           }
         m_tracked_level = lvl;
        }

      if(basket.entry_atr_m5 > 0.0 &&
         atr_m5 > m_ab_cfg.vol_kill_atr_mult * basket.entry_atr_m5)
        {
         m_soft_invalidation = true;
        }
      if(basket.entry_spread > 0.0 &&
         spread > m_ab_cfg.spread_kill_mult * basket.entry_spread)
        {
         m_soft_invalidation = true;
        }
      if(SoftInvalidationActive(basket))
         m_soft_invalidation = true;

      SReplayEvent ev;
      if(m_exit_mgr.PartialAtMidpoint(m_basket.Basket(), bar, floating,
                                      m_risk.Config().basket_dd_limit,
                                      m_trade, ev))
        {
         Emit(ev);
         basket = m_basket.Basket();
        }

      m_exit_mgr.UpdateTrail(m_basket.Basket(), atr_m5);
      if(m_exit_mgr.TrailStopHit(m_basket.Basket(), bid, ask, ev))
        {
         CloseBasketNormal("TRAIL_EXIT", ev.message);
         return;
        }

      if(m_exit_mgr.BasketTakeProfit(m_basket.Basket(), atr_m5, floating, ev))
        {
         CloseBasketNormal("BASKET_TP", ev.message);
         return;
        }

      if(m_exit_mgr.TimeScratchExit(m_basket.Basket(), floating,
                                      m_risk.Config().basket_dd_limit, ev))
        {
         CloseBasketNormal("TIME_EXIT", ev.message);
         return;
        }

      if(m_has_tracked_level && !m_soft_invalidation)
        {
         SLiquidityLevel lvl = m_tracked_level;
         const bool forbidden = m_recovery_engine.RecoveryForbidden(
            lvl, m_basket.Basket(), bar, atr_m5, spread,
            m_soft_invalidation, m_risk.DailyDdBreached(floating));
         if(m_recovery_engine.TryAddNextRung(lvl, m_basket, bar, atr_m5, spread,
                                             m_trade, forbidden, ev))
           {
            Emit(ev);
            m_tracked_level = lvl;
           }
        }

      floating = m_basket.FloatingPnl(m_trade.IsDryRun());
      if(floating < 0.0)
         m_basket.Basket().state = RLVR_BASKET_CONTROLLED_ADVERSE;
      else
         m_basket.Basket().state = RLVR_BASKET_PROFIT_COMPRESSION;
     }

   void ProcessStructureScan(const MqlRates &bar,
                             const double atr_m5,
                             const double bid,
                             const double spread,
                             const double atr_m15,
                             const double atr_h1,
                             const bool can_arm)
     {
      if(!can_arm)
         return;

      SLiquidityLevel active[];
      const int active_count = m_levels.GetActiveLevels(active, bar.time);
      if(active_count <= 0)
         return;

      for(int i = 0; i < active_count; i++)
        {
         if(m_basket.HasActiveBasket() &&
            active[i].state != RLVR_STATE_RECLAIM_CONFIRMED)
            continue;

         SReplayEvent batch[];
         const int sweep_events = m_sweep.Process(active[i], bar, atr_m5,
                                                  m_bar_counter, batch);
         for(int e = 0; e < sweep_events; e++)
            Emit(batch[e]);

         if(active[i].state == RLVR_STATE_SWEEP_DETECTED)
           {
            if(active[i].entry_atr_m5 <= 0.0)
              {
               active[i].entry_atr_m5 = atr_m5;
               active[i].entry_spread = spread;
              }

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
               ev.message       = "Sweep window expired without reclaim";
               Emit(ev);
               continue;
              }

            if(m_sweep.ReclaimTtlExpired(active[i], bar.time))
              {
               active[i].state = RLVR_STATE_EXPIRED;
               SReplayEvent ev;
               ev.timestamp  = bar.time;
               ev.event_type = "RECLAIM_TTL_EXPIRED";
               ev.level_id   = active[i].level_id;
               ev.message    = "Reclaim TTL expired";
               Emit(ev);
               continue;
              }

            SReplayEvent reclaim_ev;
            if(m_reclaim.Process(active[i], bar, atr_m5, m_bar_counter, reclaim_ev))
              {
               Emit(reclaim_ev);
               if(!m_basket.HasActiveBasket() && can_arm)
                 {
                  SReplayEvent r0_ev;
                  if(m_entry.OpenR0(active[i], m_basket, m_trade, m_risk,
                                    m_recovery, r0_ev))
                    {
                     r0_ev.bar_index = m_bar_counter;
                     Emit(r0_ev);
                     m_tracked_level     = active[i];
                     m_tracked_level.state = RLVR_STATE_CONSUMED;
                     m_has_tracked_level = true;
                     m_ea_state          = RLVR_EA_BASKET_ACTIVE;
                     m_soft_invalidation = false;
                    }
                 }
              }
           }

         if(active[i].state == RLVR_STATE_RECLAIM_CONFIRMED && !m_basket.HasActiveBasket())
           {
            SReplayEvent inv_ev;
            if(m_invalidation.Process(active[i], bar, atr_m5, m_bar_counter, inv_ev))
               Emit(inv_ev);
           }
        }

      CopyBackLevels(active, active_count);
     }

public:
   void Init(CLevelsEngine &levels,
             CRLVRTelemetry &telemetry,
             const string symbol,
             const ulong magic,
             const bool dry_run,
             const double baseline_spread,
             const SStructureConfig &structure,
             const SRecoveryConfig &recovery,
             const SExitConfig &exit_cfg,
             const SRiskConfig &risk_cfg,
             const SAntiBlowupConfig &ab_cfg,
             const SSessionConfig &session_cfg,
             const SRegimeConfig &regime_cfg)
     {
      m_levels      = &levels;
      m_telemetry   = &telemetry;
      m_structure   = structure;
      m_recovery    = recovery;
      m_exit        = exit_cfg;
      m_ab_cfg      = ab_cfg;

      m_sweep.Init(structure);
      m_reclaim.Init(structure);
      m_invalidation.Init(structure);
      m_entry.Init(structure);
      m_recovery_engine.Init(recovery, structure);
      m_exit_mgr.Init(exit_cfg, structure);
      m_antiblowup.Init(ab_cfg);
      m_regime.Init(symbol, session_cfg, regime_cfg, baseline_spread);
      m_risk.Init(risk_cfg);
      m_trade.Init(symbol, magic, dry_run);
      m_basket.Init(symbol, magic);

      m_ea_state          = RLVR_EA_IDLE;
      m_bar_counter       = 0;
      m_soft_invalidation = false;
      m_has_tracked_level = false;
     }

   void OnTimer()
     {
      m_risk.OnBalanceUpdate();
      m_antiblowup.ResetSessionIfNeeded();

      if(m_ea_state == RLVR_EA_DEFENSIVE_HALT || m_antiblowup.DayHalt())
         return;

      if(m_ea_state == RLVR_EA_COOLDOWN)
        {
         if(TimeCurrent() >= m_regime.CooldownUntil())
            m_ea_state = RLVR_EA_IDLE;
         return;
        }

      if(!m_basket.HasActiveBasket())
         return;

      const double floating = m_basket.FloatingPnl(m_trade.IsDryRun());
      ENUM_RLVR_CB_REASON cb = m_antiblowup.Check(m_risk, floating);
      if(cb != RLVR_CB_NONE)
         FlattenBasket(cb);
     }

   void OnNewM5Bar(const MqlRates &bar,
                   const double atr_m5,
                   const double bid,
                   const double ask,
                   const double spread,
                   const double atr_m15,
                   const double atr_h1)
     {
      m_bar_counter++;
      m_risk.OnBalanceUpdate();
      m_antiblowup.ResetSessionIfNeeded();

      if(m_ea_state == RLVR_EA_DEFENSIVE_HALT || m_antiblowup.DayHalt())
         return;

      if(m_ea_state == RLVR_EA_COOLDOWN)
        {
         if(TimeCurrent() >= m_regime.CooldownUntil())
            m_ea_state = RLVR_EA_IDLE;
         else
            return;
        }

      m_levels.OnNewM5Bar(bar.time, bid, spread, atr_m15, atr_h1);

      const double floating = m_basket.FloatingPnl(m_trade.IsDryRun());
      const bool can_arm = m_regime.CanArmNewLevels(bar.time, spread, atr_m15, atr_h1,
                                                    m_risk, floating,
                                                    m_basket.HasActiveBasket());

      if(m_basket.HasActiveBasket())
         ManageBasket(bar, atr_m5, bid, ask, spread);
      else
         ProcessStructureScan(bar, atr_m5, bid, spread, atr_m15, atr_h1, can_arm);
     }

   bool IsDryRun() const { return m_trade.IsDryRun(); }
   ENUM_RLVR_EA_STATE EaState() const { return m_ea_state; }
  };

// Backward-compatible alias
class CRLVRStateMachine : public CRLVRController {};

#endif
