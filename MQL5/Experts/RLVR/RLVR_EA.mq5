//+------------------------------------------------------------------+
//| RLVR_EA.mq5 — Reclaimed Liquidity Void Reset (full build v1)     |
//+------------------------------------------------------------------+
#property copyright "RLVR"
#property version   "2.00"
#property strict

#include <RLVR/Config.mqh>
#include <RLVR/LevelsEngine.mqh>
#include <RLVR/StateMachine.mqh>
#include <RLVR/Telemetry.mqh>
#include <RLVR/AtrUtils.mqh>

//--- mode
input bool   InpDryRun              = true;
input ulong  InpMagic               = RLVR_DEFAULT_MAGIC;
input string InpTelemetryFile       = "RLVR_events.csv";

//--- levels
input bool   InpAutoPdhPdl          = true;
input bool   InpAutoSessionLevels   = true;
input bool   InpAutoRoundLevels     = true;
input bool   InpManualLevelEnable   = false;
input double InpManualLevelPrice    = 2400.0;
input string InpManualLevelId       = "MANUAL_LEVEL";
input double InpManualQuality       = 0.90;

//--- structure
input bool   InpReclaimBodyFilter   = true;
input int    InpAtrPeriod           = 14;
input double InpBaselineSpread      = 0.30;

//--- risk (prop-style defaults)
input double InpRiskPerBasket       = 0.0125;
input double InpBasketDdLimit       = 0.0125;
input double InpDailyDdLimit        = 0.025;
input double InpWeeklyDdLimit       = 0.05;
input double InpMarginLimit         = 0.25;

//--- session / regime
input bool   InpAllowAsiaTrading    = false;
input int    InpLiquidStartHour     = 7;
input int    InpLiquidEndHour       = 21;
input double InpMaxChaosAtrM15      = 0.0;

CLevelsEngine      g_levels;
CRLVRController    g_controller;
CRLVRTelemetry     g_telemetry;

SStructureConfig   g_structure;
SLevelsConfig      g_levels_cfg;
SRecoveryConfig    g_recovery;
SExitConfig        g_exit;
SRiskConfig        g_risk;
SAntiBlowupConfig  g_antiblowup;
SSessionConfig     g_session;
SRegimeConfig      g_regime;

datetime           g_last_m5_bar_time = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   RLVR_LoadDefaultStructureConfig(g_structure);
   RLVR_LoadDefaultLevelsConfig(g_levels_cfg);
   RLVR_LoadDefaultRecoveryConfig(g_recovery);
   RLVR_LoadDefaultExitConfig(g_exit);
   RLVR_LoadDefaultRiskConfig(g_risk);
   RLVR_LoadDefaultAntiBlowupConfig(g_antiblowup);
   RLVR_LoadDefaultSessionConfig(g_session);
   RLVR_LoadDefaultRegimeConfig(g_regime);

   g_structure.reclaim_body_filter = InpReclaimBodyFilter;
   g_risk.risk_per_basket          = InpRiskPerBasket;
   g_risk.basket_dd_limit          = InpBasketDdLimit;
   g_risk.daily_dd_limit           = InpDailyDdLimit;
   g_risk.weekly_dd_limit          = InpWeeklyDdLimit;
   g_risk.margin_limit             = InpMarginLimit;
   g_session.allow_asia_trading    = InpAllowAsiaTrading;
   g_session.liquid_session_start_hour = InpLiquidStartHour;
   g_session.liquid_session_end_hour   = InpLiquidEndHour;
   g_regime.max_chaos_atr_m15      = InpMaxChaosAtrM15;

   if(!g_levels.Init(_Symbol, g_levels_cfg))
      return INIT_FAILED;

   g_levels.SetAutoDiscovery(InpAutoPdhPdl, InpAutoSessionLevels, InpAutoRoundLevels);

   if(InpManualLevelEnable)
     {
      SLiquidityLevel manual;
      RLVR_InitLevel(manual);
      manual.level_id      = InpManualLevelId;
      manual.type          = RLVR_LEVEL_MANUAL;
      manual.price         = InpManualLevelPrice;
      manual.quality_score = InpManualQuality;
      manual.created_at    = TimeCurrent();
      manual.expires_at    = TimeCurrent() + 7 * 24 * 3600;
      manual.state         = RLVR_STATE_ARMED;
      g_levels.AddManualLevel(manual);
     }

   if(!g_telemetry.Open(InpTelemetryFile, true))
      return INIT_FAILED;

   g_controller.Init(g_levels, g_telemetry, _Symbol, InpMagic, InpDryRun,
                     InpBaselineSpread, g_structure, g_recovery, g_exit,
                     g_risk, g_antiblowup, g_session, g_regime);

   EventSetTimer(1);

   Print("RLVR v2 started | dry_run=", InpDryRun,
         " | magic=", InpMagic,
         " | telemetry=", InpTelemetryFile);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   g_telemetry.Close();
   Print("RLVR stopped. reason=", reason);
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   g_controller.OnTimer();
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   const datetime bar_time = iTime(_Symbol, PERIOD_M5, 0);
   if(bar_time == 0 || bar_time == g_last_m5_bar_time)
      return;

   g_last_m5_bar_time = bar_time;

   MqlRates bars[];
   ArraySetAsSeries(bars, true);
   if(CopyRates(_Symbol, PERIOD_M5, 1, 1, bars) != 1)
      return;

   const double atr_m5  = RLVR_GetAtr(_Symbol, PERIOD_M5, InpAtrPeriod, 1);
   const double atr_m15 = RLVR_GetAtr(_Symbol, PERIOD_M15, InpAtrPeriod, 1);
   const double atr_h1  = RLVR_GetAtr(_Symbol, PERIOD_H1, InpAtrPeriod, 1);
   const double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double spread  = ask - bid;

   if(atr_m5 <= 0.0)
      return;

   g_controller.OnNewM5Bar(bars[0], atr_m5, bid, ask, spread, atr_m15, atr_h1);
  }

//+------------------------------------------------------------------+
