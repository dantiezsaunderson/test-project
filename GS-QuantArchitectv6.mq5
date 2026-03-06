//+------------------------------------------------------------------+
//|                                            GS_QuantArchitect.mq5 |
//|                        Goldman Sachs Quant Strategy Architect     |
//|                Multi-Strategy Institutional EA for XAU/USD & All  |
//+------------------------------------------------------------------+
#property copyright "GS Quant Desk - Systematic Alpha Division"
#property link      "https://github.com/gs-quant"
#property version   "3.10"
#property description "Multi-Strategy Quantitative EA implementing 8 alpha strategies"
#property description "with institutional risk management, regime detection, and"
#property description "adaptive position sizing. Optimized for XAU/USD, universal deployment."
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                      |
//+------------------------------------------------------------------+
enum ENUM_STRATEGY_ID
{
   STRAT_NONE            = 0,
   STRAT_TREND_FOLLOW    = 1,   // S1: Trend Following
   STRAT_MEAN_REVERT     = 2,   // S2: Mean Reversion
   STRAT_BREAKOUT        = 3,   // S3: Breakout Detection
   STRAT_SCALP_MOMENTUM  = 4,   // S4: Momentum Scalping
   STRAT_GRID_RECOVERY   = 5,   // S5: Smart Grid
   STRAT_SWING_MACRO     = 6,   // S6: Swing Macro
   STRAT_ORDER_FLOW      = 7,   // S7: Order Flow / SMC
   STRAT_VOLATILITY_ARB  = 8    // S8: Volatility Arb
};

enum ENUM_MARKET_REGIME
{
   REGIME_STRONG_TREND_UP    = 0,
   REGIME_WEAK_TREND_UP      = 1,
   REGIME_RANGING            = 2,
   REGIME_WEAK_TREND_DOWN    = 3,
   REGIME_STRONG_TREND_DOWN  = 4,
   REGIME_HIGH_VOLATILITY    = 5,
   REGIME_LOW_VOLATILITY     = 6
};

enum ENUM_RISK_LEVEL
{
   RISK_CONSERVATIVE = 0,  // Conservative (0.5%)
   RISK_MODERATE     = 1,  // Moderate (1.0%)
   RISK_AGGRESSIVE   = 2   // Aggressive (2.0%)
};

enum ENUM_SESSION_FILTER
{
   SESSION_ALL       = 0,  // All Sessions
   SESSION_LONDON    = 1,  // London Only
   SESSION_NEWYORK   = 2,  // New York Only
   SESSION_OVERLAP   = 3,  // London-NY Overlap
   SESSION_ASIAN     = 4,  // Asian Session
   SESSION_NO_ASIAN  = 5   // Exclude Asian
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "═══════════ GLOBAL SETTINGS ═══════════"
input int      InpMagicNumber         = 20250226;    // Magic Number
input string   InpTradeComment        = "GS_Quant";  // Trade Comment Prefix
input int      InpMaxSlippage         = 30;          // Max Slippage (points)
input bool     InpDebugMode           = true;        // Debug Logging

input group "═══════════ STRATEGY ACTIVATION ═══════════"
input bool     InpEnableTrendFollow   = true;   // [S1] Trend Following
input bool     InpEnableMeanRevert    = true;   // [S2] Mean Reversion
input bool     InpEnableBreakout      = true;   // [S3] Breakout Detection
input bool     InpEnableScalping      = true;   // [S4] Momentum Scalping
input bool     InpEnableGrid          = false;  // [S5] Smart Grid Recovery
input bool     InpEnableSwing         = true;   // [S6] Swing / Macro
input bool     InpEnableOrderFlow     = true;   // [S7] Order Flow / SMC
input bool     InpEnableVolatility    = true;   // [S8] Volatility Arbitrage
input bool     InpUseRegimeFilter     = true;   // Market Regime Filter

input group "═══════════ RISK MANAGEMENT ═══════════"
input ENUM_RISK_LEVEL InpRiskLevel    = RISK_MODERATE;
input double   InpMaxDailyDrawdown    = 5.0;     // Max Daily DD % (circuit breaker)
input double   InpMaxTotalDrawdown    = 15.0;    // Max Total DD % (kill switch)
input int      InpMaxOpenTrades       = 8;       // Max Open Trades
input int      InpMaxTradesPerStrat   = 3;       // Max Per Strategy

input group "═══════════ SESSION FILTERS ═══════════"
input ENUM_SESSION_FILTER InpSessionFilter = SESSION_ALL;
input int      InpLondonStart = 8;
input int      InpLondonEnd   = 16;
input int      InpNYStart     = 13;
input int      InpNYEnd       = 21;
input int      InpAsianStart  = 0;
input int      InpAsianEnd    = 8;
input bool     InpNoTradeFriday = false;

input group "═══════════ S1: TREND FOLLOWING ═══════════"
input int      InpTF_FastEMA       = 21;
input int      InpTF_SlowEMA       = 55;
input int      InpTF_TrendEMA      = 200;
input double   InpTF_ADXThreshold  = 20.0;    // ADX Min Threshold
input double   InpTF_RRRatio       = 2.5;     // Reward:Risk
input double   InpTF_TrailATRMult  = 2.0;     // Trail ATR Multiple
input ENUM_TIMEFRAMES InpTF_TF     = PERIOD_H1;

input group "═══════════ S2: MEAN REVERSION ═══════════"
input int      InpMR_BBPeriod      = 20;
input double   InpMR_BBDev         = 2.0;
input double   InpMR_RSIOversold   = 35.0;    // RSI Oversold (relaxed)
input double   InpMR_RSIOverbought = 65.0;    // RSI Overbought (relaxed)
input ENUM_TIMEFRAMES InpMR_TF     = PERIOD_M30;

input group "═══════════ S3: BREAKOUT ═══════════"
input int      InpBO_Lookback      = 20;
input double   InpBO_RRRatio       = 3.0;
input bool     InpBO_RetestEntry   = true;
input ENUM_TIMEFRAMES InpBO_TF     = PERIOD_H1;

input group "═══════════ S4: SCALPING ═══════════"
input int      InpSC_RSIPeriod     = 7;
input int      InpSC_MACDFast      = 8;
input int      InpSC_MACDSlow      = 17;
input int      InpSC_MACDSignal    = 9;
input int      InpSC_StochK        = 5;
input int      InpSC_StochD        = 3;
input int      InpSC_StochSlow     = 3;
input double   InpSC_ATRTPMult     = 1.0;
input double   InpSC_ATRSLMult     = 0.75;
input ENUM_TIMEFRAMES InpSC_TF     = PERIOD_M5;

input group "═══════════ S5: GRID ═══════════"
input double   InpGR_SpacingATR    = 1.0;
input int      InpGR_MaxLevels     = 5;
input double   InpGR_LotMult       = 1.3;
input double   InpGR_MaxRisk       = 5.0;
input double   InpGR_TPProfitATR   = 0.5;

input group "═══════════ S6: SWING ═══════════"
input int      InpSW_FastMA        = 20;
input int      InpSW_SlowMA        = 50;
input double   InpSW_ATRSLMult     = 3.0;
input double   InpSW_RRRatio       = 3.0;
input bool     InpSW_UseWeeklyBias = true;
input ENUM_TIMEFRAMES InpSW_TF     = PERIOD_H4;

input group "═══════════ S7: SMC / ORDER FLOW ═══════════"
input int      InpOF_StructBars    = 50;
input int      InpOF_OBLookback    = 10;
input double   InpOF_FVGMinSize    = 0.3;
input double   InpOF_RRRatio       = 3.0;
input ENUM_TIMEFRAMES InpOF_TF     = PERIOD_M15;

input group "═══════════ S8: VOLATILITY ═══════════"
input int      InpVA_ATRFast       = 7;
input int      InpVA_ATRSlow       = 50;
input double   InpVA_VolContraction= 0.6;
input double   InpVA_VolExpansion  = 1.5;
input double   InpVA_RRRatio       = 2.0;
input ENUM_TIMEFRAMES InpVA_TF     = PERIOD_M30;

input group "═══════════ ADVANCED ═══════════"
input bool     InpLogTrades        = true;
input bool     InpShowDashboard    = true;
input int      InpATRPeriod        = 14;
input double   InpSpreadFilter     = 0;
input int      InpWarmupBars       = 50;

//+------------------------------------------------------------------+
//| STRUCTURES                                                        |
//+------------------------------------------------------------------+
struct StrategyState
{
   bool     enabled;
   int      openPositions;
   int      consecutiveLosses;
   int      totalTrades;
   double   totalProfit;
   datetime lastTradeTime;
   int      signalsGenerated;
};

//+------------------------------------------------------------------+
//| GLOBALS                                                           |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  posInfo;
CSymbolInfo    symInfo;
CAccountInfo   accInfo;

StrategyState  strats[9];

// Indicator handles
int h_ATR, h_ATR_Fast, h_ATR_Slow, h_ATR_H4;
int h_EMA21, h_EMA55, h_EMA200, h_EMA200_H4, h_EMA50_W1;
int h_RSI, h_MACD, h_Stoch, h_BB, h_ADX;

// Market data cache
double g_bid, g_ask, g_spread, g_mid;
double g_atr, g_atrFast, g_atrSlow, g_atrRatio;
double g_ema21, g_ema55, g_ema200;
double g_rsi, g_macdMain, g_macdSig, g_macdHist;
double g_stochK, g_stochD;
double g_bbUp, g_bbMid, g_bbLow;
double g_adx, g_diP, g_diM;
double g_trendStr;
double g_volRatio;
ENUM_MARKET_REGIME g_regime;

// State
double   g_dayEquity, g_peakEquity;
int      g_warmup;
bool     g_ready;
int      g_totalOpen;
datetime g_lastWarmupBar;
datetime g_lastBarS1, g_lastBarS2, g_lastBarS3, g_lastBarS4;
datetime g_lastBarS5, g_lastBarS6, g_lastBarS7, g_lastBarS8;

// Symbol
double   g_point, g_tickSz, g_tickVal, g_lotStep, g_minLot, g_maxLot;
int      g_digits;
int      g_stopsLevelPts, g_freezeLevelPts;
double   g_minStopDist;

//+------------------------------------------------------------------+
//| Helper: per-timeframe new bar check                              |
//+------------------------------------------------------------------+
bool IsNewBarTF(ENUM_TIMEFRAMES tf, datetime &lastBarTime)
{
   datetime cur = iTime(_Symbol, tf, 0);
   if(cur <= 0) return false;
   if(cur != lastBarTime)
   {
      lastBarTime = cur;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| INIT                                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("═══════════════════════════════════════════");
   Print("  GS QUANT ARCHITECT v3.10 INIT");
   Print("═══════════════════════════════════════════");
   
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpMaxSlippage);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   trade.SetTypeFillingBySymbol(_Symbol);
   
   symInfo.Name(_Symbol);
   symInfo.Refresh();
   g_point   = symInfo.Point();
   g_tickSz  = symInfo.TickSize();
   g_tickVal = symInfo.TickValue();
   g_lotStep = symInfo.LotsStep();
   g_minLot  = symInfo.LotsMin();
   g_maxLot  = symInfo.LotsMax();
   g_digits  = (int)symInfo.Digits();
   g_stopsLevelPts  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   g_freezeLevelPts = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   g_minStopDist    = MathMax(g_stopsLevelPts, g_freezeLevelPts + 1) * g_point;
   
   PrintFormat("Symbol: %s | Point:%g TickVal:%g TickSz:%g MinLot:%g Digits:%d Stops:%d Freeze:%d MinStop:%g",
               _Symbol, g_point, g_tickVal, g_tickSz, g_minLot, g_digits,
               g_stopsLevelPts, g_freezeLevelPts, g_minStopDist);
   
   // Create handles
   h_ATR      = iATR(_Symbol, PERIOD_M15, InpATRPeriod);
   h_ATR_Fast = iATR(_Symbol, PERIOD_M15, InpVA_ATRFast);
   h_ATR_Slow = iATR(_Symbol, PERIOD_M15, InpVA_ATRSlow);
   h_ATR_H4   = iATR(_Symbol, PERIOD_H4, 14);
   h_EMA21    = iMA(_Symbol, InpTF_TF, InpTF_FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   h_EMA55    = iMA(_Symbol, InpTF_TF, InpTF_SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   h_EMA200   = iMA(_Symbol, InpTF_TF, InpTF_TrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   h_EMA200_H4= iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
   h_EMA50_W1 = iMA(_Symbol, PERIOD_W1, 50, 0, MODE_EMA, PRICE_CLOSE);
   h_RSI      = iRSI(_Symbol, InpTF_TF, 14, PRICE_CLOSE);
   h_MACD     = iMACD(_Symbol, InpTF_TF, 12, 26, 9, PRICE_CLOSE);
   h_Stoch    = iStochastic(_Symbol, InpSC_TF, InpSC_StochK, InpSC_StochD, InpSC_StochSlow, MODE_SMA, STO_LOWHIGH);
   h_BB       = iBands(_Symbol, InpMR_TF, InpMR_BBPeriod, 0, InpMR_BBDev, PRICE_CLOSE);
   h_ADX      = iADX(_Symbol, InpTF_TF, 14);
   
   if(h_ATR==INVALID_HANDLE || h_EMA21==INVALID_HANDLE || h_RSI==INVALID_HANDLE || 
      h_MACD==INVALID_HANDLE || h_BB==INVALID_HANDLE || h_ADX==INVALID_HANDLE)
   {
      Print("FATAL: Indicator handle creation failed!");
      return INIT_FAILED;
   }
   Print("All indicator handles OK");
   
   // Init strategies
   for(int i=0; i<9; i++)
   {
      strats[i].enabled = false;
      strats[i].openPositions = 0;
      strats[i].consecutiveLosses = 0;
      strats[i].totalTrades = 0;
      strats[i].totalProfit = 0;
      strats[i].lastTradeTime = 0;
      strats[i].signalsGenerated = 0;
   }
   strats[1].enabled = InpEnableTrendFollow;
   strats[2].enabled = InpEnableMeanRevert;
   strats[3].enabled = InpEnableBreakout;
   strats[4].enabled = InpEnableScalping;
   strats[5].enabled = InpEnableGrid;
   strats[6].enabled = InpEnableSwing;
   strats[7].enabled = InpEnableOrderFlow;
   strats[8].enabled = InpEnableVolatility;
   
   g_warmup     = 0;
   g_ready      = false;
   g_lastWarmupBar = 0;
   g_lastBarS1 = 0; g_lastBarS2 = 0; g_lastBarS3 = 0; g_lastBarS4 = 0;
   g_lastBarS5 = 0; g_lastBarS6 = 0; g_lastBarS7 = 0; g_lastBarS8 = 0;
   g_peakEquity = accInfo.Equity();
   g_dayEquity  = g_peakEquity;
   
   int cnt = 0;
   for(int i=1; i<=8; i++) if(strats[i].enabled) cnt++;
   PrintFormat("Active strategies: %d | Risk: %s | Warmup: %d bars", cnt, EnumToString(InpRiskLevel), InpWarmupBars);
   Print("═══ INIT COMPLETE ═══");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| DEINIT                                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(h_ATR); IndicatorRelease(h_ATR_Fast); IndicatorRelease(h_ATR_Slow);
   IndicatorRelease(h_ATR_H4); IndicatorRelease(h_EMA21); IndicatorRelease(h_EMA55);
   IndicatorRelease(h_EMA200); IndicatorRelease(h_EMA200_H4); IndicatorRelease(h_EMA50_W1);
   IndicatorRelease(h_RSI); IndicatorRelease(h_MACD); IndicatorRelease(h_Stoch);
   IndicatorRelease(h_BB); IndicatorRelease(h_ADX);
   
   PrintFinalSummary();
   if(InpShowDashboard) ObjectsDeleteAll(0, "GS_");
}

//+------------------------------------------------------------------+
//| Helper: safe buffer read                                          |
//+------------------------------------------------------------------+
double IndVal(int handle, int buffer=0, int shift=0)
{
   if(handle == INVALID_HANDLE) return 0;
   double buf[1];
   if(CopyBuffer(handle, buffer, shift, 1, buf) > 0) return buf[0];
   return 0;
}

//+------------------------------------------------------------------+
//| TICK                                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Price update
   symInfo.Refresh();
   g_bid = symInfo.Bid();
   g_ask = symInfo.Ask();
   if(g_bid <= 0 || g_ask <= 0) return;
   g_spread = g_ask - g_bid;
   g_mid = (g_bid + g_ask) / 2.0;
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tv > 0) g_tickVal = tv;
   g_stopsLevelPts  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   g_freezeLevelPts = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   g_minStopDist    = MathMax(g_stopsLevelPts, g_freezeLevelPts + 1) * g_point;
   
   // Warmup
   if(!g_ready)
   {
      if(IsNewBarTF(PERIOD_M15, g_lastWarmupBar)) g_warmup++;
      if(g_warmup >= InpWarmupBars)
      {
         g_ready = true;
         Print("✅ WARMUP DONE after ", g_warmup, " bars. TRADING ENABLED.");
      }
      return;
   }
   
   // New day
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   static int prevDay = -1;
   if(dt.day != prevDay) { prevDay = dt.day; g_dayEquity = accInfo.Equity(); }
   
   // Load indicators (soft fail)
   LoadData();
   
   // Risk
   double equity = accInfo.Equity();
   if(equity > g_peakEquity) g_peakEquity = equity;
   double dd = (g_peakEquity > 0) ? (g_peakEquity - equity) / g_peakEquity * 100.0 : 0;
   double dailyPnl = (g_dayEquity > 0) ? (equity - g_dayEquity) / g_dayEquity * 100.0 : 0;
   
   if(dd >= InpMaxTotalDrawdown) { CloseAll("KILL SWITCH"); return; }
   if(dailyPnl <= -InpMaxDailyDrawdown) { return; }  // No new trades
   
   // Spread filter
   if(InpSpreadFilter > 0 && g_spread > InpSpreadFilter * g_point) return;
   
   // Regime
   if(InpUseRegimeFilter) DetectRegime();
   else g_regime = REGIME_RANGING;
   
   // Session
   if(!SessionOK(dt)) return;
   if(InpNoTradeFriday && dt.day_of_week == 5 && dt.hour >= 18) return;
   
   // Count positions
   CountPositions();
   
   // Manage existing
   ManagePositions();
   
   // Run each strategy on its own timeframe bar, not chart timeframe
   if(strats[1].enabled && IsNewBarTF(InpTF_TF, g_lastBarS1)) S1_TrendFollowing();
   if(strats[2].enabled && IsNewBarTF(InpMR_TF, g_lastBarS2)) S2_MeanReversion();
   if(strats[3].enabled && IsNewBarTF(InpBO_TF, g_lastBarS3)) S3_Breakout();
   if(strats[4].enabled && IsNewBarTF(InpSC_TF, g_lastBarS4)) S4_Scalping();
   if(strats[5].enabled && IsNewBarTF(PERIOD_M15, g_lastBarS5)) S5_Grid();
   if(strats[6].enabled && IsNewBarTF(InpSW_TF, g_lastBarS6)) S6_Swing();
   if(strats[7].enabled && IsNewBarTF(InpOF_TF, g_lastBarS7)) S7_OrderFlow();
   if(strats[8].enabled && IsNewBarTF(InpVA_TF, g_lastBarS8)) S8_VolatilityArb();
   
   if(InpShowDashboard) DrawDashboard(dd, dailyPnl);
}

//+------------------------------------------------------------------+
//| Load indicator data                                               |
//+------------------------------------------------------------------+
void LoadData()
{
   g_atr     = IndVal(h_ATR, 0, 1);
   g_atrFast = IndVal(h_ATR_Fast, 0, 1);
   g_atrSlow = IndVal(h_ATR_Slow, 0, 1);
   g_atrRatio= (g_atrSlow > 0) ? g_atrFast / g_atrSlow : 1.0;
   
   g_ema21  = IndVal(h_EMA21, 0, 1);
   g_ema55  = IndVal(h_EMA55, 0, 1);
   g_ema200 = IndVal(h_EMA200, 0, 1);
   
   g_rsi = IndVal(h_RSI, 0, 1);
   g_macdMain = IndVal(h_MACD, 0, 1); g_macdSig = IndVal(h_MACD, 1, 1);
   g_macdHist = g_macdMain - g_macdSig;
   g_stochK = IndVal(h_Stoch, 0, 1); g_stochD = IndVal(h_Stoch, 1, 1);
   
   g_bbMid = IndVal(h_BB, 0, 1); g_bbUp = IndVal(h_BB, 1, 1); g_bbLow = IndVal(h_BB, 2, 1);
   g_adx = IndVal(h_ADX, 0, 1); g_diP = IndVal(h_ADX, 1, 1); g_diM = IndVal(h_ADX, 2, 1);
   
   // Volume ratio
   double vNow = (double)iVolume(_Symbol, PERIOD_M15, 1);
   double vSum = 0;
   for(int i=2; i<=21; i++) vSum += (double)iVolume(_Symbol, PERIOD_M15, i);
   g_volRatio = (vSum > 0) ? vNow / (vSum/20.0) : 1.0;
   
   // Trend strength
   g_trendStr = 0;
   if(g_ema21 > 0 && g_ema55 > 0)
   {
      if(g_mid > g_ema21)  g_trendStr += 0.25; else g_trendStr -= 0.25;
      if(g_mid > g_ema55)  g_trendStr += 0.25; else g_trendStr -= 0.25;
      if(g_ema200 > 0) { if(g_mid > g_ema200) g_trendStr += 0.3; else g_trendStr -= 0.3; }
      if(g_diP > g_diM) g_trendStr += 0.2; else g_trendStr -= 0.2;
   }
   
   static bool logged = false;
   if(!logged && g_atr > 0)
   {
      PrintFormat("📊 First data: ATR=%.5f EMA21=%.2f EMA55=%.2f EMA200=%.2f RSI=%.1f ADX=%.1f",
                  g_atr, g_ema21, g_ema55, g_ema200, g_rsi, g_adx);
      logged = true;
   }
}

//+------------------------------------------------------------------+
//| Regime detection                                                  |
//+------------------------------------------------------------------+
void DetectRegime()
{
   if(g_atrRatio > 1.5 && g_adx < 25)       g_regime = REGIME_HIGH_VOLATILITY;
   else if(g_atrRatio < 0.6 && g_adx < 20)  g_regime = REGIME_LOW_VOLATILITY;
   else if(g_adx > 25 && g_trendStr > 0.4)  g_regime = REGIME_STRONG_TREND_UP;
   else if(g_adx > 25 && g_trendStr < -0.4) g_regime = REGIME_STRONG_TREND_DOWN;
   else if(g_trendStr > 0.2)                 g_regime = REGIME_WEAK_TREND_UP;
   else if(g_trendStr < -0.2)               g_regime = REGIME_WEAK_TREND_DOWN;
   else                                       g_regime = REGIME_RANGING;
}

//+------------------------------------------------------------------+
//| Position sizing                                                   |
//+------------------------------------------------------------------+
double CalcLots(double slDist, double strength, int sid)
{
   if(slDist <= 0 || g_tickSz <= 0 || g_tickVal <= 0) return g_minLot;
   
   double riskPct;
   switch(InpRiskLevel)
   {
      case RISK_CONSERVATIVE: riskPct = 0.5; break;
      case RISK_MODERATE:     riskPct = 1.0; break;
      case RISK_AGGRESSIVE:   riskPct = 2.0; break;
      default:                riskPct = 1.0; break;
   }
   
   riskPct *= (0.6 + strength * 0.6);
   if(strats[sid].consecutiveLosses >= 3) riskPct *= 0.5;
   if(g_totalOpen >= InpMaxOpenTrades / 2) riskPct *= 0.6;
   
   double riskAmt = accInfo.Equity() * riskPct / 100.0;
   double ticks   = slDist / g_tickSz;
   if(ticks <= 0) return g_minLot;
   
   double lots = riskAmt / (ticks * g_tickVal);
   lots = MathFloor(lots / g_lotStep) * g_lotStep;
   lots = MathMax(g_minLot, MathMin(g_maxLot, lots));
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Count positions                                                   |
//+------------------------------------------------------------------+
void CountPositions()
{
   for(int i=0; i<9; i++) strats[i].openPositions = 0;
   g_totalOpen = 0;
   
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Magic() == InpMagicNumber && posInfo.Symbol() == _Symbol)
         {
            g_totalOpen++;
            int sid = GetStratID(posInfo.Comment());
            if(sid > 0 && sid <= 8) strats[sid].openPositions++;
         }
      }
   }
}

int GetStratID(string comment)
{
   if(StringFind(comment,"_S1_")>=0) return 1;
   if(StringFind(comment,"_S2_")>=0) return 2;
   if(StringFind(comment,"_S3_")>=0) return 3;
   if(StringFind(comment,"_S4_")>=0) return 4;
   if(StringFind(comment,"_S5_")>=0) return 5;
   if(StringFind(comment,"_S6_")>=0) return 6;
   if(StringFind(comment,"_S7_")>=0) return 7;
   if(StringFind(comment,"_S8_")>=0) return 8;
   return 0;
}

//+------------------------------------------------------------------+
//| Session filter                                                    |
//+------------------------------------------------------------------+
bool SessionOK(MqlDateTime &dt)
{
   if(InpSessionFilter == SESSION_ALL) return true;
   int h = dt.hour;
   switch(InpSessionFilter)
   {
      case SESSION_LONDON:   return (h >= InpLondonStart && h < InpLondonEnd);
      case SESSION_NEWYORK:  return (h >= InpNYStart && h < InpNYEnd);
      case SESSION_OVERLAP:  return (h >= InpNYStart && h < InpLondonEnd);
      case SESSION_ASIAN:    return (h >= InpAsianStart && h < InpAsianEnd);
      case SESSION_NO_ASIAN: return !(h >= InpAsianStart && h < InpAsianEnd);
   }
   return true;
}

double NormalizeLots(double lots)
{
   if(g_lotStep <= 0) return g_minLot;
   double nLots = MathFloor((lots + 1e-10) / g_lotStep) * g_lotStep;
   nLots = MathMax(g_minLot, MathMin(g_maxLot, nLots));
   int lotDigits = (g_lotStep >= 1.0) ? 0 : (int)MathRound(-MathLog10(g_lotStep));
   lotDigits = MathMax(0, MathMin(8, lotDigits));
   return NormalizeDouble(nLots, lotDigits);
}

bool CanTradeDirection(bool isBuy)
{
   long mode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(mode == SYMBOL_TRADE_MODE_DISABLED || mode == SYMBOL_TRADE_MODE_CLOSEONLY) return false;
   if(isBuy && mode == SYMBOL_TRADE_MODE_SHORTONLY) return false;
   if(!isBuy && mode == SYMBOL_TRADE_MODE_LONGONLY) return false;
   return true;
}

double MinStopDistance()
{
   g_stopsLevelPts  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   g_freezeLevelPts = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   g_minStopDist    = MathMax(g_stopsLevelPts, g_freezeLevelPts + 1) * g_point;
   return g_minStopDist;
}

bool PrepareOrder(bool isBuy, double &lots, double &sl, double &tp, string &why)
{
   symInfo.Refresh();
   g_bid = symInfo.Bid();
   g_ask = symInfo.Ask();
   if(g_bid <= 0 || g_ask <= 0) { why = "No valid bid/ask"; return false; }
   
   if(!CanTradeDirection(isBuy))
   {
      why = isBuy ? "BUY blocked by symbol trade mode" : "SELL blocked by symbol trade mode";
      return false;
   }
   
   lots = NormalizeLots(lots);
   if(lots < g_minLot - (g_lotStep * 0.5))
   {
      why = StringFormat("Volume %.4f below min %.4f", lots, g_minLot);
      return false;
   }
   
   double minDist = MinStopDistance();
   
   if(isBuy)
   {
      if(sl > 0)
      {
         double maxSL = g_bid - minDist;
         if(maxSL > 0) sl = MathMin(sl, maxSL);
         if(sl >= g_bid) sl = 0;
      }
      if(tp > 0)
      {
         double minTP = g_ask + minDist;
         tp = MathMax(tp, minTP);
      }
      if(tp > 0 && tp <= g_ask) { why = "Buy TP invalid after normalization"; return false; }
   }
   else
   {
      if(sl > 0)
      {
         double minSL = g_ask + minDist;
         sl = MathMax(sl, minSL);
      }
      if(tp > 0)
      {
         double maxTP = g_bid - minDist;
         if(maxTP > 0) tp = MathMin(tp, maxTP);
         if(tp >= g_bid) tp = 0;
      }
      if(tp > 0 && tp >= g_bid) { why = "Sell TP invalid after normalization"; return false; }
   }
   
   if(sl > 0) sl = NormalizeDouble(sl, g_digits);
   if(tp > 0) tp = NormalizeDouble(tp, g_digits);
   return true;
}

bool ExecMarketFallback(bool isBuy, double lots, string comment, int sid, double plannedSL, double plannedTP)
{
   bool ok = isBuy
             ? trade.Buy(lots, _Symbol, 0, 0, 0, comment)
             : trade.Sell(lots, _Symbol, 0, 0, 0, comment);
   if(!ok) return false;
   
   strats[sid].lastTradeTime = TimeCurrent();
   strats[sid].signalsGenerated++;
   strats[sid].openPositions++;
   g_totalOpen++;
   
   if(InpLogTrades)
      PrintFormat("⚠️ %s OPENED (no SL/TP due stops rule) | Lots:%.2f PlannedSL:%.2f PlannedTP:%.2f",
                  comment, lots, plannedSL, plannedTP);
   return true;
}

//+------------------------------------------------------------------+
//| Execute trade helper                                              |
//+------------------------------------------------------------------+
bool ExecBuy(double lots, double sl, double tp, string comment, int sid)
{
   string why = "";
   if(!PrepareOrder(true, lots, sl, tp, why))
   {
      if(InpDebugMode) PrintFormat("⏭️ %s SKIP: %s", comment, why);
      return false;
   }
   
   if(trade.Buy(lots, _Symbol, 0, sl, tp, comment))
   {
      strats[sid].lastTradeTime = TimeCurrent();
      strats[sid].signalsGenerated++;
      strats[sid].openPositions++;
      g_totalOpen++;
      if(InpLogTrades) PrintFormat("✅ %s | Lots:%.2f SL:%.2f TP:%.2f", comment, lots, sl, tp);
      return true;
   }
   uint rc = (uint)trade.ResultRetcode();
   if(rc == TRADE_RETCODE_INVALID_STOPS)
   {
      if(ExecMarketFallback(true, lots, comment, sid, sl, tp)) return true;
   }
   if(InpDebugMode)
      PrintFormat("❌ %s FAIL: %d %s | Bid:%.2f Ask:%.2f Stops:%d Freeze:%d MinStop:%.2f",
                  comment, rc, trade.ResultRetcodeDescription(), g_bid, g_ask,
                  g_stopsLevelPts, g_freezeLevelPts, g_minStopDist);
   return false;
}

bool ExecSell(double lots, double sl, double tp, string comment, int sid)
{
   string why = "";
   if(!PrepareOrder(false, lots, sl, tp, why))
   {
      if(InpDebugMode) PrintFormat("⏭️ %s SKIP: %s", comment, why);
      return false;
   }
   
   if(trade.Sell(lots, _Symbol, 0, sl, tp, comment))
   {
      strats[sid].lastTradeTime = TimeCurrent();
      strats[sid].signalsGenerated++;
      strats[sid].openPositions++;
      g_totalOpen++;
      if(InpLogTrades) PrintFormat("✅ %s | Lots:%.2f SL:%.2f TP:%.2f", comment, lots, sl, tp);
      return true;
   }
   uint rc = (uint)trade.ResultRetcode();
   if(rc == TRADE_RETCODE_INVALID_STOPS)
   {
      if(ExecMarketFallback(false, lots, comment, sid, sl, tp)) return true;
   }
   if(InpDebugMode)
      PrintFormat("❌ %s FAIL: %d %s | Bid:%.2f Ask:%.2f Stops:%d Freeze:%d MinStop:%.2f",
                  comment, rc, trade.ResultRetcodeDescription(), g_bid, g_ask,
                  g_stopsLevelPts, g_freezeLevelPts, g_minStopDist);
   return false;
}

//+------------------------------------------------------------------+
//| S1: TREND FOLLOWING                                               |
//+------------------------------------------------------------------+
void S1_TrendFollowing()
{
   if(strats[1].openPositions >= InpMaxTradesPerStrat || g_totalOpen >= InpMaxOpenTrades) return;
   if(g_atr <= 0) return;
   if(InpUseRegimeFilter && g_regime == REGIME_RANGING) return;
   
   double f0 = IndVal(h_EMA21, 0, 1), f1 = IndVal(h_EMA21, 0, 2);
   double s0 = IndVal(h_EMA55, 0, 1), s1 = IndVal(h_EMA55, 0, 2);
   double t0 = IndVal(h_EMA200, 0, 1);
   if(f0<=0 || s0<=0 || f1<=0 || s1<=0) return;
   
   bool bullX = (f0 > s0 && f1 <= s1);
   bool bearX = (f0 < s0 && f1 >= s1);
   bool adxOK = (g_adx >= InpTF_ADXThreshold);
   
   double slD = g_atr * InpTF_TrailATRMult;
   double str = MathMin(1.0, 0.5 + (g_adx - InpTF_ADXThreshold) / 30.0);
   
   if(bullX && adxOK && (t0 <= 0 || g_mid > t0))
   {
      double lots = CalcLots(slD, str, 1);
      ExecBuy(lots, g_ask - slD, g_ask + slD * InpTF_RRRatio, InpTradeComment+"_S1_BUY", 1);
   }
   if(bearX && adxOK && (t0 <= 0 || g_mid < t0))
   {
      double lots = CalcLots(slD, str, 1);
      ExecSell(lots, g_bid + slD, g_bid - slD * InpTF_RRRatio, InpTradeComment+"_S1_SELL", 1);
   }
}

//+------------------------------------------------------------------+
//| S2: MEAN REVERSION                                                |
//+------------------------------------------------------------------+
void S2_MeanReversion()
{
   if(strats[2].openPositions >= InpMaxTradesPerStrat || g_totalOpen >= InpMaxOpenTrades) return;
   if(g_atr <= 0) return;
   if(InpUseRegimeFilter && (g_regime==REGIME_STRONG_TREND_UP || g_regime==REGIME_STRONG_TREND_DOWN)) return;
   
   double bU0=IndVal(h_BB,1,1), bM0=IndVal(h_BB,0,1), bL0=IndVal(h_BB,2,1);
   double bL1=IndVal(h_BB,2,2), bU1=IndVal(h_BB,1,2);
   if(bU0<=0 || bL0<=0) return;
   
   double rsi0=IndVal(h_RSI,0,1), rsi1=IndVal(h_RSI,0,2);
   double c0 = iClose(_Symbol, InpMR_TF, 1);
   double c1 = iClose(_Symbol, InpMR_TF, 2);
   
   // BUY: touched lower BB + RSI oversold + bounce
   if(c1 <= bL1 && c0 > bL0 && rsi1 <= InpMR_RSIOversold && rsi0 > rsi1)
   {
      double sl = bL0 - g_atr * 0.5;
      double slD = g_ask - sl;
      double tp = bM0;
      if(slD > 0 && tp > g_ask)
      {
         double lots = CalcLots(slD, 0.7, 2);
         ExecBuy(lots, sl, tp, InpTradeComment+"_S2_BUY", 2);
      }
   }
   
   // SELL: touched upper BB + RSI overbought + rejection
   if(c1 >= bU1 && c0 < bU0 && rsi1 >= InpMR_RSIOverbought && rsi0 < rsi1)
   {
      double sl = bU0 + g_atr * 0.5;
      double slD = sl - g_bid;
      double tp = bM0;
      if(slD > 0 && tp < g_bid)
      {
         double lots = CalcLots(slD, 0.7, 2);
         ExecSell(lots, sl, tp, InpTradeComment+"_S2_SELL", 2);
      }
   }
}

//+------------------------------------------------------------------+
//| S3: BREAKOUT                                                      |
//+------------------------------------------------------------------+
void S3_Breakout()
{
   if(strats[3].openPositions >= InpMaxTradesPerStrat || g_totalOpen >= InpMaxOpenTrades) return;
   if(g_atr <= 0) return;
   
   int bars = InpBO_Lookback;
   double hi[], lo[], cl[];
   ArraySetAsSeries(hi,true); ArraySetAsSeries(lo,true); ArraySetAsSeries(cl,true);
   if(CopyHigh(_Symbol,InpBO_TF,0,bars+2,hi)<bars+2) return;
   if(CopyLow(_Symbol,InpBO_TF,0,bars+2,lo)<bars+2) return;
   if(CopyClose(_Symbol,InpBO_TF,0,bars+2,cl)<bars+2) return;
   
   double rangeH = hi[2], rangeL = lo[2];
   for(int i=3; i<=bars+1; i++) { if(hi[i]>rangeH) rangeH=hi[i]; if(lo[i]<rangeL) rangeL=lo[i]; }
   
   // BULL breakout
   if(cl[1] > rangeH)
   {
      double sl = InpBO_RetestEntry ? rangeH - g_atr*0.5 : rangeL;
      double slD = g_ask - sl;
      if(slD > 0)
      {
         double lots = CalcLots(slD, 0.7, 3);
         ExecBuy(lots, sl, g_ask + slD * InpBO_RRRatio, InpTradeComment+"_S3_BUY", 3);
      }
   }
   // BEAR breakout
   if(cl[1] < rangeL)
   {
      double sl = InpBO_RetestEntry ? rangeL + g_atr*0.5 : rangeH;
      double slD = sl - g_bid;
      if(slD > 0)
      {
         double lots = CalcLots(slD, 0.7, 3);
         ExecSell(lots, sl, g_bid - slD * InpBO_RRRatio, InpTradeComment+"_S3_SELL", 3);
      }
   }
}

//+------------------------------------------------------------------+
//| S4: SCALPING                                                      |
//+------------------------------------------------------------------+
void S4_Scalping()
{
   if(strats[4].openPositions >= InpMaxTradesPerStrat || g_totalOpen >= InpMaxOpenTrades) return;
   if(g_atr <= 0) return;
   if(TimeCurrent() - strats[4].lastTradeTime < PeriodSeconds(InpSC_TF)*2) return;
   
   // Create temp handles for scalp TF
   int hR = iRSI(_Symbol, InpSC_TF, InpSC_RSIPeriod, PRICE_CLOSE);
   int hM = iMACD(_Symbol, InpSC_TF, InpSC_MACDFast, InpSC_MACDSlow, InpSC_MACDSignal, PRICE_CLOSE);
   int hS = iStochastic(_Symbol, InpSC_TF, InpSC_StochK, InpSC_StochD, InpSC_StochSlow, MODE_SMA, STO_LOWHIGH);
   
   if(hR==INVALID_HANDLE||hM==INVALID_HANDLE||hS==INVALID_HANDLE)
   { IndicatorRelease(hR); IndicatorRelease(hM); IndicatorRelease(hS); return; }
   
   double r[2],mM[2],mS[2],sK[2],sD[2];
   bool ok = CopyBuffer(hR,0,1,2,r)>=2 && CopyBuffer(hM,0,1,2,mM)>=2 &&
             CopyBuffer(hM,1,1,2,mS)>=2 && CopyBuffer(hS,0,1,2,sK)>=2 && CopyBuffer(hS,1,1,2,sD)>=2;
   IndicatorRelease(hR); IndicatorRelease(hM); IndicatorRelease(hS);
   if(!ok) return;
   
   double h0=mM[0]-mS[0], h1=mM[1]-mS[1];
   
   int bull = (r[0]>50&&r[0]<75&&r[0]>r[1]?1:0) + (h0>0&&h0>h1?1:0) + (sK[0]>sD[0]&&sK[1]<=sD[1]&&sK[0]<80?1:0);
   int bear = (r[0]<50&&r[0]>25&&r[0]<r[1]?1:0) + (h0<0&&h0<h1?1:0) + (sK[0]<sD[0]&&sK[1]>=sD[1]&&sK[0]>20?1:0);
   
   double slD = g_atr * InpSC_ATRSLMult;
   double tpD = g_atr * InpSC_ATRTPMult;
   
   if(bull >= 2)
   {
      double lots = CalcLots(slD, bull/3.0, 4);
      ExecBuy(lots, g_ask-slD, g_ask+tpD, InpTradeComment+"_S4_BUY", 4);
   }
   if(bear >= 2)
   {
      double lots = CalcLots(slD, bear/3.0, 4);
      ExecSell(lots, g_bid+slD, g_bid-tpD, InpTradeComment+"_S4_SELL", 4);
   }
}

//+------------------------------------------------------------------+
//| S5: GRID                                                          |
//+------------------------------------------------------------------+
void S5_Grid()
{
   if(g_totalOpen >= InpMaxOpenTrades || g_atr <= 0) return;
   
   int gridCount = 0;
   double lowestPrice = 999999;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()!=InpMagicNumber || posInfo.Symbol()!=_Symbol) continue;
      if(StringFind(posInfo.Comment(),"_S5_")<0) continue;
      gridCount++;
      if(posInfo.PriceOpen() < lowestPrice) lowestPrice = posInfo.PriceOpen();
   }
   
   if(gridCount >= InpGR_MaxLevels) return;
   
   double spacing = g_atr * InpGR_SpacingATR;
   bool shouldAdd = false;
   
   if(gridCount == 0)
      shouldAdd = (g_trendStr > 0.1);
   else
      shouldAdd = (lowestPrice < 999999 && g_bid <= lowestPrice - spacing);
   
   if(shouldAdd)
   {
      double baseLot = CalcLots(spacing*2, 0.5, 5);
      double gridLot = baseLot * MathPow(InpGR_LotMult, gridCount);
      gridLot = MathMax(g_minLot, MathMin(g_maxLot, NormalizeDouble(gridLot/g_lotStep,0)*g_lotStep));
      double tp = g_ask + g_atr * InpGR_TPProfitATR;
      ExecBuy(gridLot, 0, tp, InpTradeComment+"_S5_BUY_L"+IntegerToString(gridCount), 5);
   }
}

//+------------------------------------------------------------------+
//| S6: SWING                                                         |
//+------------------------------------------------------------------+
void S6_Swing()
{
   if(strats[6].openPositions >= InpMaxTradesPerStrat || g_totalOpen >= InpMaxOpenTrades) return;
   if(g_atr <= 0) return;
   if(TimeCurrent() - strats[6].lastTradeTime < PeriodSeconds(PERIOD_H4)) return;
   
   int hF = iMA(_Symbol, InpSW_TF, InpSW_FastMA, 0, MODE_EMA, PRICE_CLOSE);
   int hS = iMA(_Symbol, InpSW_TF, InpSW_SlowMA, 0, MODE_EMA, PRICE_CLOSE);
   if(hF==INVALID_HANDLE||hS==INVALID_HANDLE) { IndicatorRelease(hF); IndicatorRelease(hS); return; }
   
   double f[2], s[2];
   bool ok = CopyBuffer(hF,0,1,2,f)>=2 && CopyBuffer(hS,0,1,2,s)>=2;
   IndicatorRelease(hF); IndicatorRelease(hS);
   if(!ok) return;
   
   bool bullX = (f[0]>s[0] && f[1]<=s[1]);
   bool bearX = (f[0]<s[0] && f[1]>=s[1]);
   
   bool wkBull=true, wkBear=true;
   if(InpSW_UseWeeklyBias)
   {
      double wma = IndVal(h_EMA50_W1, 0, 1);
      if(wma > 0) { wkBull = (g_mid > wma); wkBear = (g_mid < wma); }
   }
   
   double h4atr = IndVal(h_ATR_H4, 0, 1);
   if(h4atr <= 0) h4atr = g_atr * 4;
   double slD = h4atr * InpSW_ATRSLMult;
   
   if(bullX && wkBull)
   {
      double lots = CalcLots(slD, 0.7, 6);
      ExecBuy(lots, g_ask-slD, g_ask+slD*InpSW_RRRatio, InpTradeComment+"_S6_BUY", 6);
   }
   if(bearX && wkBear)
   {
      double lots = CalcLots(slD, 0.7, 6);
      ExecSell(lots, g_bid+slD, g_bid-slD*InpSW_RRRatio, InpTradeComment+"_S6_SELL", 6);
   }
}

//+------------------------------------------------------------------+
//| S7: ORDER FLOW / SMC                                              |
//+------------------------------------------------------------------+
void S7_OrderFlow()
{
   if(strats[7].openPositions >= InpMaxTradesPerStrat || g_totalOpen >= InpMaxOpenTrades) return;
   if(g_atr <= 0) return;
   if(TimeCurrent() - strats[7].lastTradeTime < PeriodSeconds(InpOF_TF)*3) return;
   
   int bars = InpOF_StructBars;
   double hi[],lo[],op[],cl[];
   ArraySetAsSeries(hi,true); ArraySetAsSeries(lo,true);
   ArraySetAsSeries(op,true); ArraySetAsSeries(cl,true);
   if(CopyHigh(_Symbol,InpOF_TF,0,bars,hi)<bars) return;
   if(CopyLow(_Symbol,InpOF_TF,0,bars,lo)<bars) return;
   if(CopyOpen(_Symbol,InpOF_TF,0,bars,op)<bars) return;
   if(CopyClose(_Symbol,InpOF_TF,0,bars,cl)<bars) return;
   
   // HTF bias
   double htfE = IndVal(h_EMA200_H4, 0, 1);
   bool htfBull = (htfE > 0) ? (g_mid > htfE) : true;
   bool htfBear = (htfE > 0) ? (g_mid < htfE) : true;
   
   // Swing points
   double swH=0, swL=999999;
   for(int i=2; i<bars-2; i++)
   {
      if(hi[i]>hi[i-1]&&hi[i]>hi[i-2]&&hi[i]>hi[i+1]&&hi[i]>hi[i+2]) if(hi[i]>swH) swH=hi[i];
      if(lo[i]<lo[i-1]&&lo[i]<lo[i-2]&&lo[i]<lo[i+1]&&lo[i]<lo[i+2]) if(lo[i]<swL) swL=lo[i];
   }
   
   // Order blocks
   double bOBt=0, bOBb=0;
   for(int i=1; i<InpOF_OBLookback && i<bars-1; i++)
   {
      if(cl[i+1]<op[i+1] && cl[i]>op[i]) // bearish then bullish
      {
         if((cl[i]-op[i]) > (op[i+1]-cl[i+1])*1.3 && (cl[i]-op[i]) > g_atr*0.3)
         { bOBt=op[i+1]; bOBb=cl[i+1]; break; }
      }
   }
   
   // Liquidity sweep
   bool bullSweep = (swL<999999 && lo[1]<swL && cl[1]>swL);
   bool bearSweep = (swH>0 && hi[1]>swH && cl[1]<swH);
   
   // BULL
   double bullStr = 0;
   if(htfBull)
   {
      if(bOBb>0 && g_bid>=bOBb && g_bid<=bOBt) bullStr += 0.5;
      if(bullSweep) bullStr += 0.5;
   }
   if(bullStr >= 0.4)
   {
      double sl = (bOBb>0) ? bOBb-g_atr*0.5 : (swL<999999) ? swL-g_atr*0.3 : g_ask-g_atr*1.5;
      double slD = g_ask - sl;
      if(slD > 0)
      {
         double lots = CalcLots(slD, MathMin(1.0,bullStr), 7);
         ExecBuy(lots, sl, g_ask+slD*InpOF_RRRatio, InpTradeComment+"_S7_BUY", 7);
      }
   }
   
   // BEAR (mirror)
   double bearOBt=0, bearOBb=0;
   for(int i=1; i<InpOF_OBLookback && i<bars-1; i++)
   {
      if(cl[i+1]>op[i+1] && cl[i]<op[i])
      {
         if((op[i]-cl[i]) > (cl[i+1]-op[i+1])*1.3 && (op[i]-cl[i]) > g_atr*0.3)
         { bearOBt=cl[i+1]; bearOBb=op[i+1]; break; }
      }
   }
   
   double bearStr = 0;
   if(htfBear)
   {
      if(bearOBt>0 && g_ask>=bearOBb && g_ask<=bearOBt) bearStr += 0.5;
      if(bearSweep) bearStr += 0.5;
   }
   if(bearStr >= 0.4)
   {
      double sl = (bearOBt>0) ? bearOBt+g_atr*0.5 : (swH>0) ? swH+g_atr*0.3 : g_bid+g_atr*1.5;
      double slD = sl - g_bid;
      if(slD > 0)
      {
         double lots = CalcLots(slD, MathMin(1.0,bearStr), 7);
         ExecSell(lots, sl, g_bid-slD*InpOF_RRRatio, InpTradeComment+"_S7_SELL", 7);
      }
   }
}

//+------------------------------------------------------------------+
//| S8: VOLATILITY ARB                                                |
//+------------------------------------------------------------------+
void S8_VolatilityArb()
{
   if(strats[8].openPositions >= InpMaxTradesPerStrat || g_totalOpen >= InpMaxOpenTrades) return;
   if(g_atr <= 0 || g_atrSlow <= 0) return;
   if(TimeCurrent() - strats[8].lastTradeTime < PeriodSeconds(InpVA_TF)*2) return;
   
   bool squeeze = (g_atrRatio < InpVA_VolContraction);
   bool expansion = (g_atrRatio > InpVA_VolExpansion);
   
   bool momBull = (g_macdHist > 0 && g_rsi > 50);
   bool momBear = (g_macdHist < 0 && g_rsi < 50);
   
   double slD = g_atr * 1.5;
   double tpD = slD * InpVA_RRRatio;
   
   if(squeeze)
   {
      if(momBull) { double lots=CalcLots(slD,0.7,8); ExecBuy(lots, g_ask-slD, g_ask+tpD, InpTradeComment+"_S8_BUY_SQZ", 8); }
      if(momBear) { double lots=CalcLots(slD,0.7,8); ExecSell(lots, g_bid+slD, g_bid-tpD, InpTradeComment+"_S8_SELL_SQZ", 8); }
   }
   
   if(expansion && g_atrRatio > 2.0)
   {
      double c1 = iClose(_Symbol, InpVA_TF, 1);
      double c3 = iClose(_Symbol, InpVA_TF, 3);
      double fadeSL = g_atr * 2.0;
      double fadeTP = fadeSL * 1.5;
      
      if(c1 > c3 + g_atr) { double lots=CalcLots(fadeSL,0.6,8); ExecSell(lots, g_bid+fadeSL, g_bid-fadeTP, InpTradeComment+"_S8_SELL_EXP", 8); }
      if(c1 < c3 - g_atr) { double lots=CalcLots(fadeSL,0.6,8); ExecBuy(lots, g_ask-fadeSL, g_ask+fadeTP, InpTradeComment+"_S8_BUY_EXP", 8); }
   }
}

//+------------------------------------------------------------------+
//| POSITION MANAGEMENT                                               |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()!=InpMagicNumber || posInfo.Symbol()!=_Symbol) continue;
      
      int sid = GetStratID(posInfo.Comment());
      ulong ticket = posInfo.Ticket();
      
      if(sid==1) TrailATR(ticket, InpTF_TrailATRMult);
      if(sid==6) TrailATR(ticket, InpSW_ATRSLMult * 0.75);
      if(sid==3 || sid==7) MoveToBE(ticket);
      if(sid==4 && TimeCurrent()-posInfo.Time() > 7200) { trade.PositionClose(ticket); }
   }
}

void TrailATR(ulong ticket, double mult)
{
   if(!posInfo.SelectByTicket(ticket) || g_atr<=0) return;
   double sl=posInfo.StopLoss(), op=posInfo.PriceOpen(), trail=g_atr*mult;
   
   if(posInfo.PositionType()==POSITION_TYPE_BUY)
   { double ns=g_bid-trail; if(ns>sl&&ns>op) trade.PositionModify(ticket,NormalizeDouble(ns,g_digits),posInfo.TakeProfit()); }
   else
   { double ns=g_ask+trail; if((sl==0||ns<sl)&&ns<op) trade.PositionModify(ticket,NormalizeDouble(ns,g_digits),posInfo.TakeProfit()); }
}

void MoveToBE(ulong ticket)
{
   if(!posInfo.SelectByTicket(ticket) || g_atr<=0) return;
   double sl=posInfo.StopLoss(), op=posInfo.PriceOpen(), buf=g_spread*2;
   
   if(posInfo.PositionType()==POSITION_TYPE_BUY)
   { if(g_bid-op>=g_atr && sl<op) trade.PositionModify(ticket,NormalizeDouble(op+buf,g_digits),posInfo.TakeProfit()); }
   else
   { if(op-g_ask>=g_atr && (sl>op||sl==0)) trade.PositionModify(ticket,NormalizeDouble(op-buf,g_digits),posInfo.TakeProfit()); }
}

void CloseAll(string reason)
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(posInfo.SelectByIndex(i))
         if(posInfo.Magic()==InpMagicNumber && posInfo.Symbol()==_Symbol)
         { trade.PositionClose(posInfo.Ticket()); Print("🛑 CLOSE: ",reason); }
   }
}

//+------------------------------------------------------------------+
//| OnTrade - track results                                           |
//+------------------------------------------------------------------+
void OnTrade()
{
   static int lastD = 0;
   HistorySelect(0, TimeCurrent());
   int total = HistoryDealsTotal();
   
   for(int i=lastD; i<total; i++)
   {
      ulong t = HistoryDealGetTicket(i);
      if(t<=0 || HistoryDealGetInteger(t,DEAL_MAGIC)!=InpMagicNumber) continue;
      long entry = HistoryDealGetInteger(t, DEAL_ENTRY);
      if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY)
      {
         double pnl = HistoryDealGetDouble(t,DEAL_PROFIT)+HistoryDealGetDouble(t,DEAL_SWAP)+HistoryDealGetDouble(t,DEAL_COMMISSION);
         int sid = GetStratID(HistoryDealGetString(t,DEAL_COMMENT));
         if(sid>0 && sid<=8)
         {
            strats[sid].totalTrades++;
            strats[sid].totalProfit += pnl;
            if(pnl>0) strats[sid].consecutiveLosses=0; else strats[sid].consecutiveLosses++;
         }
         if(InpLogTrades) PrintFormat("📊 CLOSED | S%d | $%.2f", sid, pnl);
      }
   }
   lastD = total;
}

//+------------------------------------------------------------------+
//| Dashboard                                                         |
//+------------------------------------------------------------------+
void DrawDashboard(double dd, double dailyPnl)
{
   int x=10, y=30, h=18;
   string p="GS_";
   DL(p+"h",x,y,"═══ GS QUANT v3.10 ═══",clrGold,10); y+=h+3;
   DL(p+"e",x,y,StringFormat("Eq:$%.0f DD:%.1f%% Day:%.1f%%",accInfo.Equity(),dd,dailyPnl),
      dailyPnl>=0?clrLime:clrRed,9); y+=h;
   DL(p+"r",x,y,StringFormat("Regime:%s Trend:%.2f ATR:%.2f",EnumToString(g_regime),g_trendStr,g_atr),clrWhite,9); y+=h;
   DL(p+"o",x,y,StringFormat("Open:%d/%d Sprd:%.1f",g_totalOpen,InpMaxOpenTrades,g_spread/g_point),clrWhite,9); y+=h+3;
   
   string nm[]={"","S1:Trnd","S2:MR","S3:BO","S4:Sclp","S5:Grid","S6:Swng","S7:SMC","S8:Vol"};
   for(int i=1;i<=8;i++)
   {
      if(strats[i].enabled)
      {
         DL(p+"s"+IntegerToString(i),x,y,StringFormat("%s T:%d Sig:%d P:$%.0f",
            nm[i],strats[i].totalTrades,strats[i].signalsGenerated,strats[i].totalProfit),
            strats[i].totalProfit>=0?clrLime:clrRed,8);
         y+=h;
      }
   }
}

void DL(string n,int x,int y,string t,color c,int sz)
{
   if(ObjectFind(0,n)<0){ ObjectCreate(0,n,OBJ_LABEL,0,0,0); ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER); }
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
   ObjectSetString(0,n,OBJPROP_TEXT,t); ObjectSetString(0,n,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,n,OBJPROP_FONTSIZE,sz); ObjectSetInteger(0,n,OBJPROP_COLOR,c);
}

//+------------------------------------------------------------------+
//| Final Summary                                                     |
//+------------------------------------------------------------------+
void PrintFinalSummary()
{
   Print("═══════════════════════════════════════════");
   Print("  GS QUANT ARCHITECT - FINAL SUMMARY");
   Print("═══════════════════════════════════════════");
   int tt=0; double tp=0;
   string nm[]={"","TREND","MEANREV","BREAKOUT","SCALP","GRID","SWING","SMC","VOLARB"};
   for(int i=1;i<=8;i++)
   {
      if(strats[i].enabled)
      {
         PrintFormat("  %s: Trades=%d Signals=%d Profit=$%.2f",nm[i],strats[i].totalTrades,strats[i].signalsGenerated,strats[i].totalProfit);
         tt+=strats[i].totalTrades; tp+=strats[i].totalProfit;
      }
   }
   Print("───────────────────────────────────────────");
   PrintFormat("  TOTAL: Trades=%d Profit=$%.2f", tt, tp);
   Print("═══════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| Tester                                                            |
//+------------------------------------------------------------------+
double OnTester()
{
   double pf=TesterStatistics(STAT_PROFIT_FACTOR);
   double t=TesterStatistics(STAT_TRADES);
   double dd=TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   if(t<10||TesterStatistics(STAT_PROFIT)<=0) return 0;
   return pf*MathSqrt(t)*(1.0-dd/100.0);
}
//+------------------------------------------------------------------+
