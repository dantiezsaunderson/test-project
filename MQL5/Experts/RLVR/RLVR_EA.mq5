//+------------------------------------------------------------------+
//| RLVR_EA.mq5 — Reclaimed Liquidity Void Reset (dry-run v1)        |
//| No orders in dry-run; logs sweep/reclaim/invalidation events.     |
//+------------------------------------------------------------------+
#property copyright "RLVR"
#property version   "1.00"
#property strict

#include <RLVR/Config.mqh>
#include <RLVR/LevelsEngine.mqh>
#include <RLVR/StateMachine.mqh>
#include <RLVR/Telemetry.mqh>
#include <RLVR/AtrUtils.mqh>

input bool   InpDryRun              = true;
input string InpTelemetryFile       = "RLVR_events.csv";
input bool   InpLogToTerminal       = true;

input bool   InpAutoPdhPdl          = true;
input bool   InpAutoSessionLevels   = true;
input bool   InpAutoRoundLevels     = true;

input bool   InpManualLevelEnable   = false;
input double InpManualLevelPrice    = 2400.0;
input string InpManualLevelId       = "MANUAL_LEVEL";
input double InpManualQuality       = 0.90;

input bool   InpReclaimBodyFilter   = true;
input int    InpAtrPeriod           = 14;

CLevelsEngine      g_levels;
CRLVRStateMachine  g_state;
CRLVRTelemetry     g_telemetry;
SStructureConfig   g_structure;
SLevelsConfig      g_levels_cfg;

datetime           g_last_m5_bar_time = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(!InpDryRun)
     {
      Print("RLVR v1 supports dry-run only. Set InpDryRun=true.");
      return INIT_FAILED;
     }

   RLVR_LoadDefaultStructureConfig(g_structure);
   RLVR_LoadDefaultLevelsConfig(g_levels_cfg);
   g_structure.reclaim_body_filter = InpReclaimBodyFilter;

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
      Print("RLVR manual level armed: ", manual.level_id, " @ ", manual.price);
     }

   if(!g_telemetry.Open(InpTelemetryFile, true))
      return INIT_FAILED;

   g_state.Init(g_levels, g_telemetry, g_structure);

   Print("RLVR dry-run started on ", _Symbol,
         " | telemetry=", InpTelemetryFile,
         " (FILE_COMMON)");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_telemetry.Close();
   Print("RLVR dry-run stopped. reason=", reason);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   const datetime bar_time = iTime(_Symbol, PERIOD_M5, 0);
   if(bar_time == 0 || bar_time == g_last_m5_bar_time)
      return;

   g_last_m5_bar_time = bar_time;

   MqlRates bar[];
   ArraySetAsSeries(bar, true);
   if(CopyRates(_Symbol, PERIOD_M5, 1, 1, bar) != 1)
      return;

   const double atr_m5  = RLVR_GetAtr(_Symbol, PERIOD_M5, InpAtrPeriod, 1);
   const double atr_m15 = RLVR_GetAtr(_Symbol, PERIOD_M15, InpAtrPeriod, 1);
   const double atr_h1  = RLVR_GetAtr(_Symbol, PERIOD_H1, InpAtrPeriod, 1);
   const double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double spread  = ask - bid;

   if(atr_m5 <= 0.0)
      return;

   g_state.OnNewM5Bar(bar[0], atr_m5, bid, spread, atr_m15, atr_h1);
  }

//+------------------------------------------------------------------+
