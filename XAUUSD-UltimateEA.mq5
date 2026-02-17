//+------------------------------------------------------------------+
//|                                          XAUUSD_UltimateEA.mq5   |
//|                        Multi-Strategy Adaptive Gold Trading EA    |
//|                                                                    |
//|  Strategies: Trend Following, Mean Reversion, Breakout,           |
//|              Momentum Scalping, Smart Money Concepts               |
//|  Regime Detection: Trending / Ranging / Volatile / Quiet          |
//+------------------------------------------------------------------+
#property copyright "Ultimate XAUUSD EA"
#property version   "2.10"
#property description "Multi-Strategy Adaptive Gold Trading Expert Advisor v2"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMS                                                              |
//+------------------------------------------------------------------+
enum ENUM_MARKET_REGIME
{
   REGIME_STRONG_TREND_UP,    // Strong Uptrend
   REGIME_WEAK_TREND_UP,      // Weak Uptrend
   REGIME_RANGING,            // Ranging/Consolidation
   REGIME_WEAK_TREND_DOWN,    // Weak Downtrend
   REGIME_STRONG_TREND_DOWN,  // Strong Downtrend
   REGIME_VOLATILE,           // High Volatility
   REGIME_QUIET               // Low Volatility / Quiet
};

enum ENUM_STRATEGY
{
   STRAT_TREND_FOLLOW,        // Trend Following
   STRAT_MEAN_REVERSION,      // Mean Reversion
   STRAT_BREAKOUT,            // Breakout
   STRAT_MOMENTUM_SCALP,      // Momentum Scalping
   STRAT_SMC                  // Smart Money Concepts
};

enum ENUM_RISK_MODE
{
   RISK_FIXED_LOT,            // Fixed Lot Size
   RISK_PERCENT,              // Percent of Balance
   RISK_DYNAMIC               // Dynamic (ATR-based)
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                   |
//+------------------------------------------------------------------+
// ===== General Settings =====
input group "=== General Settings ==="
input string         InpSymbol            = "XAUUSD";       // Symbol (leave blank for current)
input ENUM_TIMEFRAMES InpTimeframe        = PERIOD_M15;     // Primary Timeframe
input ENUM_TIMEFRAMES InpHTFTimeframe     = PERIOD_H1;      // Higher Timeframe (Bias)
input int            InpMagicNumber       = 777777;         // Magic Number
input string         InpComment           = "XAUUSD_UltEA"; // Order Comment
input bool           InpTradeOnNewBarOnly = true;            // Trade on New Bar Only

// ===== Strategy Activation =====
input group "=== Strategy Activation ==="
input bool           InpUseTrendFollow    = true;            // Enable Trend Following
input bool           InpUseMeanReversion  = true;            // Enable Mean Reversion
input bool           InpUseBreakout       = true;            // Enable Breakout
input bool           InpUseMomentumScalp  = true;            // Enable Momentum Scalping
input bool           InpUseSMC            = true;            // Enable Smart Money Concepts
input bool           InpAdaptiveMode      = true;            // Adaptive Mode (auto-select strategy)

// ===== Risk Management =====
input group "=== Risk Management ==="
input ENUM_RISK_MODE InpRiskMode          = RISK_PERCENT;    // Risk Mode
input double         InpFixedLot          = 0.01;            // Fixed Lot Size
input double         InpRiskPercent       = 1.0;             // Risk Per Trade (%)
input double         InpMaxDrawdownPct    = 10.0;            // Max Drawdown % (pause trading)
input int            InpMaxOpenTrades     = 3;               // Max Simultaneous Trades
input double         InpMaxDailyLossPct   = 3.0;             // Max Daily Loss % (stop trading)
input bool           InpUseTrailingStop   = true;            // Use Trailing Stop
input double         InpTrailingATRMult   = 1.5;             // Trailing Stop ATR Multiplier
input bool           InpUseBreakeven      = true;            // Move to Breakeven
input double         InpBreakevenATRMult  = 1.0;             // Breakeven Trigger ATR Multiplier
input double         InpMaxSpreadPoints   = 0;               // Max spread in points for new entries (0=disabled)
input double         InpMinRewardRisk     = 1.0;             // Minimum reward:risk for entries
input int            InpMinMinutesBetweenTrades = 0;         // Cooldown between new trades

// ===== Trend Following Parameters =====
input group "=== Trend Following ==="
input int            InpFastMA            = 21;              // Fast MA Period
input int            InpSlowMA            = 50;              // Slow MA Period
input int            InpTrendMA           = 200;             // Trend Filter MA Period
input ENUM_MA_METHOD InpMAMethod          = MODE_EMA;        // MA Method
input double         InpTF_SL_ATRMult     = 2.0;             // SL ATR Multiplier
input double         InpTF_TP_ATRMult     = 3.0;             // TP ATR Multiplier

// ===== Mean Reversion Parameters =====
input group "=== Mean Reversion ==="
input int            InpBBPeriod          = 20;              // Bollinger Band Period
input double         InpBBDeviation       = 2.0;             // BB Deviation
input int            InpRSIPeriod         = 14;              // RSI Period
input int            InpRSIOverbought     = 70;              // RSI Overbought
input int            InpRSIOversold       = 30;              // RSI Oversold
input double         InpMR_SL_ATRMult     = 1.5;             // SL ATR Multiplier
input double         InpMR_TP_ATRMult     = 2.0;             // TP ATR Multiplier

// ===== Breakout Parameters =====
input group "=== Breakout ==="
input int            InpBreakoutPeriod    = 20;              // Breakout Lookback Period
input double         InpBreakoutATRFilter = 1.2;             // ATR Breakout Filter Multiplier
input int            InpVolumePeriod      = 20;              // Volume Average Period
input double         InpVolumeMultiplier  = 1.5;             // Volume Spike Multiplier
input double         InpBO_SL_ATRMult     = 1.5;             // SL ATR Multiplier
input double         InpBO_TP_ATRMult     = 3.0;             // TP ATR Multiplier

// ===== Momentum Scalping Parameters =====
input group "=== Momentum Scalping ==="
input int            InpMACDFast          = 12;              // MACD Fast
input int            InpMACDSlow          = 26;              // MACD Slow
input int            InpMACDSignal        = 9;               // MACD Signal
input int            InpStochK            = 14;              // Stochastic %K
input int            InpStochD            = 3;               // Stochastic %D
input int            InpStochSlowing      = 3;               // Stochastic Slowing
input double         InpMS_SL_ATRMult     = 1.0;             // SL ATR Multiplier
input double         InpMS_TP_ATRMult     = 1.5;             // TP ATR Multiplier

// ===== Smart Money Concepts =====
input group "=== Smart Money Concepts ==="
input int            InpSMC_SwingLookback = 10;              // Swing Point Lookback
input int            InpSMC_OBLookback    = 50;              // Order Block Lookback
input double         InpSMC_FVGMinSize    = 2.0;             // FVG Min Size (points)
input double         InpSMC_SL_ATRMult    = 2.0;             // SL ATR Multiplier
input double         InpSMC_TP_ATRMult    = 4.0;             // TP ATR Multiplier

// ===== Market Regime Detection =====
input group "=== Regime Detection ==="
input int            InpADXPeriod         = 14;              // ADX Period
input int            InpATRPeriod         = 14;              // ATR Period
input double         InpADXTrendThreshold = 25.0;            // ADX Trend Threshold
input double         InpADXStrongThreshold= 40.0;            // ADX Strong Trend Threshold
input double         InpVolatilityHigh    = 1.5;             // High Volatility ATR Multiplier
input double         InpVolatilityLow     = 0.5;             // Low Volatility ATR Multiplier

// ===== Session Filters =====
input group "=== Session Filters ==="
input bool           InpUseSessions       = false;           // Filter by Trading Sessions
input bool           InpTradeLondon       = true;            // Trade London Session
input bool           InpTradeNewYork      = true;            // Trade New York Session
input bool           InpTradeAsian        = false;           // Trade Asian Session
input int            InpLondonStart       = 8;               // London Start Hour (Server)
input int            InpLondonEnd         = 16;              // London End Hour (Server)
input int            InpNewYorkStart      = 13;              // New York Start Hour (Server)
input int            InpNewYorkEnd        = 21;              // New York End Hour (Server)
input int            InpAsianStart        = 0;               // Asian Start Hour (Server)
input int            InpAsianEnd          = 8;               // Asian End Hour (Server)

// ===== News Filter =====
input group "=== News Filter ==="
input bool           InpAvoidHighImpact   = true;            // Avoid High Impact News
input int            InpNewsPauseMins     = 30;              // Minutes Before/After News

// ===== Display =====
input group "=== Display ==="
input bool           InpShowDashboard     = true;            // Show Dashboard Panel
input color          InpDashBG            = clrBlack;        // Dashboard Background
input color          InpDashText          = clrWhite;        // Dashboard Text Color
input int            InpDashFontSize      = 9;               // Dashboard Font Size

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                   |
//+------------------------------------------------------------------+
CTrade         m_trade;
CPositionInfo  m_position;
COrderInfo     m_order;
CAccountInfo   m_account;
CSymbolInfo    m_symbol;

string         g_symbol;
ENUM_MARKET_REGIME g_currentRegime;
ENUM_STRATEGY  g_activeStrategy;

// Indicator handles
int h_fastMA, h_slowMA, h_trendMA;
int h_BB;
int h_RSI;
int h_MACD;
int h_Stoch;
int h_ADX;
int h_ATR;
int h_ATR_HTF;
int h_fastMA_HTF, h_slowMA_HTF;

// Tracking
datetime g_lastBarTime;
double   g_dailyPL;
datetime g_lastDay;
int      g_totalTrades;
int      g_winTrades;
int      g_lossTrades;
double   g_totalProfit;
double   g_totalLoss;
double   g_peakBalance;
double   g_maxDrawdown;
double   g_strategyScores[5]; // Score for each strategy
double   g_dayStartBalance;
datetime g_lastTradeTime;
datetime g_lastProcessedDealTime;
ulong    g_lastProcessedDealTicket;

// SMC structures
struct OrderBlock
{
   double priceHigh;
   double priceLow;
   datetime time;
   bool isBullish;
   bool isValid;
};

struct FairValueGap
{
   double high;
   double low;
   datetime time;
   bool isBullish;
   bool isValid;
};

OrderBlock    g_orderBlocks[];
FairValueGap  g_fvgs[];

//+------------------------------------------------------------------+
//| Expert initialization                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!InpUseTrendFollow && !InpUseMeanReversion && !InpUseBreakout && !InpUseMomentumScalp && !InpUseSMC)
   {
      Print("ERROR: No strategy is enabled. Enable at least one strategy.");
      return INIT_PARAMETERS_INCORRECT;
   }

   // Determine symbol and resolve common broker suffix/prefix variants.
   string requestedSymbol = (InpSymbol == "") ? _Symbol : InpSymbol;
   g_symbol = requestedSymbol;

   bool symbolReady = SymbolSelect(g_symbol, true) && m_symbol.Name(g_symbol);

   if(!symbolReady && InpSymbol != "" && StringFind(_Symbol, InpSymbol) >= 0)
   {
      g_symbol = _Symbol;
      symbolReady = SymbolSelect(g_symbol, true) && m_symbol.Name(g_symbol);
   }

   if(!symbolReady && InpSymbol != "")
   {
      int symbolsCount = SymbolsTotal(false);
      for(int i = 0; i < symbolsCount; i++)
      {
         string candidate = SymbolName(i, false);
         if(StringFind(candidate, InpSymbol) < 0) continue;

         g_symbol = candidate;
         if(SymbolSelect(g_symbol, true) && m_symbol.Name(g_symbol))
         {
            symbolReady = true;
            break;
         }
      }
   }

   if(!symbolReady)
   {
      Print("ERROR: Failed to resolve tradable symbol for input '", requestedSymbol, "'");
      return INIT_FAILED;
   }
   
   // Setup trade object
   m_trade.SetExpertMagicNumber(InpMagicNumber);
   m_trade.SetDeviationInPoints(50); // XAUUSD can be volatile
   if(!m_trade.SetTypeFillingBySymbol(g_symbol))
      m_trade.SetTypeFilling(ORDER_FILLING_FOK);
   m_trade.SetMarginMode();
   
   // Initialize indicators - Primary Timeframe
   h_fastMA   = iMA(g_symbol, InpTimeframe, InpFastMA, 0, InpMAMethod, PRICE_CLOSE);
   h_slowMA   = iMA(g_symbol, InpTimeframe, InpSlowMA, 0, InpMAMethod, PRICE_CLOSE);
   h_trendMA  = iMA(g_symbol, InpTimeframe, InpTrendMA, 0, InpMAMethod, PRICE_CLOSE);
   h_BB       = iBands(g_symbol, InpTimeframe, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
   h_RSI      = iRSI(g_symbol, InpTimeframe, InpRSIPeriod, PRICE_CLOSE);
   h_MACD     = iMACD(g_symbol, InpTimeframe, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE);
   h_Stoch    = iStochastic(g_symbol, InpTimeframe, InpStochK, InpStochD, InpStochSlowing, MODE_SMA, STO_LOWHIGH);
   h_ADX      = iADX(g_symbol, InpTimeframe, InpADXPeriod);
   h_ATR      = iATR(g_symbol, InpTimeframe, InpATRPeriod);
   
   // Higher Timeframe indicators
   h_ATR_HTF    = iATR(g_symbol, InpHTFTimeframe, InpATRPeriod);
   h_fastMA_HTF = iMA(g_symbol, InpHTFTimeframe, InpFastMA, 0, InpMAMethod, PRICE_CLOSE);
   h_slowMA_HTF = iMA(g_symbol, InpHTFTimeframe, InpSlowMA, 0, InpMAMethod, PRICE_CLOSE);
   
   // Validate handles
   if(h_fastMA == INVALID_HANDLE || h_slowMA == INVALID_HANDLE || h_trendMA == INVALID_HANDLE ||
      h_BB == INVALID_HANDLE || h_RSI == INVALID_HANDLE || h_MACD == INVALID_HANDLE ||
      h_Stoch == INVALID_HANDLE || h_ADX == INVALID_HANDLE || h_ATR == INVALID_HANDLE ||
      h_ATR_HTF == INVALID_HANDLE || h_fastMA_HTF == INVALID_HANDLE || h_slowMA_HTF == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicator handles");
      return INIT_FAILED;
   }
   
   // Initialize tracking
   g_lastBarTime = 0;
   g_dailyPL = 0;
   g_lastDay = 0;
   g_totalTrades = 0;
   g_winTrades = 0;
   g_lossTrades = 0;
   g_totalProfit = 0;
   g_totalLoss = 0;
   g_peakBalance = m_account.Balance();
   g_maxDrawdown = 0;
   g_dayStartBalance = g_peakBalance;
   g_lastTradeTime = 0;
   g_lastProcessedDealTime = 0;
   g_lastProcessedDealTicket = 0;
   g_currentRegime = REGIME_RANGING;
   g_activeStrategy = STRAT_TREND_FOLLOW;
   
   ArrayInitialize(g_strategyScores, 50.0); // Start with neutral score
   ArrayResize(g_orderBlocks, 0);
   ArrayResize(g_fvgs, 0);

   // Initialize day markers once at startup.
   UpdateDailyTracking();
   
   if(InpShowDashboard)
      CreateDashboard();
   
   Print("=== XAUUSD Ultimate EA Initialized ===");
   Print("Symbol: ", g_symbol, " | Primary TF: ", EnumToString(InpTimeframe));
   Print("Strategies Active: ",
         (InpUseTrendFollow ? "TrendFollow " : ""),
         (InpUseMeanReversion ? "MeanReversion " : ""),
         (InpUseBreakout ? "Breakout " : ""),
         (InpUseMomentumScalp ? "MomentumScalp " : ""),
         (InpUseSMC ? "SMC " : ""));
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   IndicatorRelease(h_fastMA);
   IndicatorRelease(h_slowMA);
   IndicatorRelease(h_trendMA);
   IndicatorRelease(h_BB);
   IndicatorRelease(h_RSI);
   IndicatorRelease(h_MACD);
   IndicatorRelease(h_Stoch);
   IndicatorRelease(h_ADX);
   IndicatorRelease(h_ATR);
   IndicatorRelease(h_ATR_HTF);
   IndicatorRelease(h_fastMA_HTF);
   IndicatorRelease(h_slowMA_HTF);
   
   ObjectsDeleteAll(0, "DASH_");
   
   Print("=== XAUUSD Ultimate EA Removed ===");
   PrintStats();
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!m_symbol.RefreshRates()) return;

   // Update daily tracking and manage existing positions on every tick.
   UpdateDailyTracking();
   ManagePositions();

   // New entry logic can still be restricted to new bars.
   if(InpTradeOnNewBarOnly && !IsNewBar())
   {
      if(InpShowDashboard) UpdateDashboard();
      return;
   }
   
   // Check drawdown limits
   if(IsDrawdownExceeded())
   {
      if(InpShowDashboard) UpdateDashboard();
      return;
   }
   
   // Check daily loss limit
   if(IsDailyLossExceeded())
   {
      if(InpShowDashboard) UpdateDashboard();
      return;
   }
   
   // Session filter
   if(InpUseSessions && !IsValidSession())
   {
      if(InpShowDashboard) UpdateDashboard();
      return;
   }
   
   // Spread filter for new entries.
   if(!IsSpreadAcceptable())
   {
      if(InpShowDashboard) UpdateDashboard();
      return;
   }
   
   // Detect market regime
   g_currentRegime = DetectMarketRegime();
   
   // Select best strategy based on regime
   if(InpAdaptiveMode)
      g_activeStrategy = SelectStrategy();
   
   // Check max open trades
   if(CountPositions() >= InpMaxOpenTrades)
   {
      if(InpShowDashboard) UpdateDashboard();
      return;
   }
   
   // Get higher timeframe bias
   int htfBias = GetHTFBias();
   
   // Execute strategies
   if(InpAdaptiveMode)
   {
      int posBefore = CountPositions();
      ExecuteStrategy(g_activeStrategy, htfBias);

      // If the preferred strategy has no setup, try other enabled strategies.
      bool opened = (CountPositions() > posBefore);
      if(!opened && InpUseTrendFollow && g_activeStrategy != STRAT_TREND_FOLLOW)
      {
         ExecuteStrategy(STRAT_TREND_FOLLOW, htfBias);
         opened = (CountPositions() > posBefore);
      }
      if(!opened && InpUseMeanReversion && g_activeStrategy != STRAT_MEAN_REVERSION)
      {
         ExecuteStrategy(STRAT_MEAN_REVERSION, htfBias);
         opened = (CountPositions() > posBefore);
      }
      if(!opened && InpUseBreakout && g_activeStrategy != STRAT_BREAKOUT)
      {
         ExecuteStrategy(STRAT_BREAKOUT, htfBias);
         opened = (CountPositions() > posBefore);
      }
      if(!opened && InpUseMomentumScalp && g_activeStrategy != STRAT_MOMENTUM_SCALP)
      {
         ExecuteStrategy(STRAT_MOMENTUM_SCALP, htfBias);
         opened = (CountPositions() > posBefore);
      }
      if(!opened && InpUseSMC && g_activeStrategy != STRAT_SMC)
      {
         ExecuteStrategy(STRAT_SMC, htfBias);
      }
   }
   else
   {
      // Run all enabled strategies
      if(InpUseTrendFollow)   ExecuteStrategy(STRAT_TREND_FOLLOW, htfBias);
      if(InpUseMeanReversion) ExecuteStrategy(STRAT_MEAN_REVERSION, htfBias);
      if(InpUseBreakout)      ExecuteStrategy(STRAT_BREAKOUT, htfBias);
      if(InpUseMomentumScalp) ExecuteStrategy(STRAT_MOMENTUM_SCALP, htfBias);
      if(InpUseSMC)           ExecuteStrategy(STRAT_SMC, htfBias);
   }
   
   if(InpShowDashboard) UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Trade event handler                                                |
//+------------------------------------------------------------------+
void OnTrade()
{
   datetime now = TimeCurrent();
   datetime fromTime = (g_lastProcessedDealTime > 0) ? (g_lastProcessedDealTime - 60) : (now - 7 * 86400);
   if(fromTime < 0) fromTime = 0;

   if(!HistorySelect(fromTime, now))
      return;

   int totalDeals = HistoryDealsTotal();

   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if(dealTime < g_lastProcessedDealTime) continue;
      if(dealTime == g_lastProcessedDealTime && ticket <= g_lastProcessedDealTicket) continue;

      if(dealTime > g_lastProcessedDealTime || (dealTime == g_lastProcessedDealTime && ticket > g_lastProcessedDealTicket))
      {
         g_lastProcessedDealTime = dealTime;
         g_lastProcessedDealTicket = ticket;
      }

      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != g_symbol) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                      HistoryDealGetDouble(ticket, DEAL_SWAP) +
                      HistoryDealGetDouble(ticket, DEAL_COMMISSION);

      g_totalTrades++;
      if(profit > 0)
      {
         g_winTrades++;
         g_totalProfit += profit;
      }
      else
      {
         g_lossTrades++;
         g_totalLoss += MathAbs(profit);
      }

      g_dailyPL += profit;

      // Update strategy scores based on result.
      string comment = HistoryDealGetString(ticket, DEAL_COMMENT);
      UpdateStrategyScore(comment, profit);
   }
   
   // Update peak balance and drawdown
   double balance = m_account.Balance();
   if(balance > g_peakBalance)
      g_peakBalance = balance;

   if(g_peakBalance > 0)
   {
      double dd = (g_peakBalance - balance) / g_peakBalance * 100.0;
      if(dd > g_maxDrawdown)
         g_maxDrawdown = dd;
   }
}

//+------------------------------------------------------------------+
//| MARKET REGIME DETECTION                                            |
//+------------------------------------------------------------------+
ENUM_MARKET_REGIME DetectMarketRegime()
{
   double adx[], plusDI[], minusDI[], atr[];
   ArraySetAsSeries(adx, true);
   ArraySetAsSeries(plusDI, true);
   ArraySetAsSeries(minusDI, true);
   ArraySetAsSeries(atr, true);
   
   if(CopyBuffer(h_ADX, 0, 0, 20, adx) < 20) return REGIME_RANGING;
   if(CopyBuffer(h_ADX, 1, 0, 20, plusDI) < 20) return REGIME_RANGING;
   if(CopyBuffer(h_ADX, 2, 0, 20, minusDI) < 20) return REGIME_RANGING;
   if(CopyBuffer(h_ATR, 0, 0, 50, atr) < 50) return REGIME_RANGING;
   
   double currentADX = adx[0];
   double currentATR = atr[0];
   
   // Calculate average ATR for comparison
   double avgATR = 0;
   for(int i = 10; i < 50; i++) avgATR += atr[i];
   avgATR /= 40.0;
   
   double atrRatio = currentATR / avgATR;
   
   // Check for extreme volatility first
   if(atrRatio > InpVolatilityHigh && currentADX < InpADXTrendThreshold)
      return REGIME_VOLATILE;
   
   // Check for quiet market
   if(atrRatio < InpVolatilityLow && currentADX < InpADXTrendThreshold)
      return REGIME_QUIET;
   
   // Trend detection
   if(currentADX >= InpADXStrongThreshold)
   {
      return (plusDI[0] > minusDI[0]) ? REGIME_STRONG_TREND_UP : REGIME_STRONG_TREND_DOWN;
   }
   else if(currentADX >= InpADXTrendThreshold)
   {
      return (plusDI[0] > minusDI[0]) ? REGIME_WEAK_TREND_UP : REGIME_WEAK_TREND_DOWN;
   }
   
   return REGIME_RANGING;
}

//+------------------------------------------------------------------+
//| SELECT BEST STRATEGY FOR CURRENT REGIME                            |
//+------------------------------------------------------------------+
ENUM_STRATEGY SelectStrategy()
{
   double scores[5];
   ArrayCopy(scores, g_strategyScores);
   
   // Apply regime multipliers to base scores
   switch(g_currentRegime)
   {
      case REGIME_STRONG_TREND_UP:
      case REGIME_STRONG_TREND_DOWN:
         scores[STRAT_TREND_FOLLOW]   *= 2.0;
         scores[STRAT_MEAN_REVERSION] *= 0.3;
         scores[STRAT_BREAKOUT]       *= 1.5;
         scores[STRAT_MOMENTUM_SCALP] *= 1.2;
         scores[STRAT_SMC]            *= 1.5;
         break;
         
      case REGIME_WEAK_TREND_UP:
      case REGIME_WEAK_TREND_DOWN:
         scores[STRAT_TREND_FOLLOW]   *= 1.5;
         scores[STRAT_MEAN_REVERSION] *= 0.8;
         scores[STRAT_BREAKOUT]       *= 1.0;
         scores[STRAT_MOMENTUM_SCALP] *= 1.3;
         scores[STRAT_SMC]            *= 1.5;
         break;
         
      case REGIME_RANGING:
         scores[STRAT_TREND_FOLLOW]   *= 0.3;
         scores[STRAT_MEAN_REVERSION] *= 2.0;
         scores[STRAT_BREAKOUT]       *= 1.2;
         scores[STRAT_MOMENTUM_SCALP] *= 1.0;
         scores[STRAT_SMC]            *= 1.3;
         break;
         
      case REGIME_VOLATILE:
         scores[STRAT_TREND_FOLLOW]   *= 0.5;
         scores[STRAT_MEAN_REVERSION] *= 0.5;
         scores[STRAT_BREAKOUT]       *= 2.0;
         scores[STRAT_MOMENTUM_SCALP] *= 1.5;
         scores[STRAT_SMC]            *= 1.0;
         break;
         
      case REGIME_QUIET:
         scores[STRAT_TREND_FOLLOW]   *= 0.5;
         scores[STRAT_MEAN_REVERSION] *= 1.5;
         scores[STRAT_BREAKOUT]       *= 0.3;
         scores[STRAT_MOMENTUM_SCALP] *= 0.5;
         scores[STRAT_SMC]            *= 1.0;
         break;
   }
   
   // Zero out disabled strategies
   if(!InpUseTrendFollow)   scores[STRAT_TREND_FOLLOW] = 0;
   if(!InpUseMeanReversion) scores[STRAT_MEAN_REVERSION] = 0;
   if(!InpUseBreakout)      scores[STRAT_BREAKOUT] = 0;
   if(!InpUseMomentumScalp) scores[STRAT_MOMENTUM_SCALP] = 0;
   if(!InpUseSMC)           scores[STRAT_SMC] = 0;
   
   // Find highest scoring strategy
   int bestIdx = 0;
   double bestScore = scores[0];
   for(int i = 1; i < 5; i++)
   {
      if(scores[i] > bestScore)
      {
         bestScore = scores[i];
         bestIdx = i;
      }
   }
   
   return (ENUM_STRATEGY)bestIdx;
}

//+------------------------------------------------------------------+
//| EXECUTE SELECTED STRATEGY                                          |
//+------------------------------------------------------------------+
void ExecuteStrategy(ENUM_STRATEGY strategy, int htfBias)
{
   switch(strategy)
   {
      case STRAT_TREND_FOLLOW:    Strategy_TrendFollow(htfBias);    break;
      case STRAT_MEAN_REVERSION:  Strategy_MeanReversion(htfBias);  break;
      case STRAT_BREAKOUT:        Strategy_Breakout(htfBias);       break;
      case STRAT_MOMENTUM_SCALP:  Strategy_MomentumScalp(htfBias);  break;
      case STRAT_SMC:             Strategy_SMC(htfBias);            break;
   }
}

//+------------------------------------------------------------------+
//| STRATEGY 1: TREND FOLLOWING (EMA Cross + ADX + 200MA Filter)      |
//+------------------------------------------------------------------+
void Strategy_TrendFollow(int htfBias)
{
   double fastMA[], slowMA[], trendMA[], atr[], adx[];
   ArraySetAsSeries(fastMA, true);
   ArraySetAsSeries(slowMA, true);
   ArraySetAsSeries(trendMA, true);
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(adx, true);
   
   if(CopyBuffer(h_fastMA, 0, 0, 3, fastMA) < 3) return;
   if(CopyBuffer(h_slowMA, 0, 0, 3, slowMA) < 3) return;
   if(CopyBuffer(h_trendMA, 0, 0, 3, trendMA) < 3) return;
   if(CopyBuffer(h_ATR, 0, 0, 3, atr) < 3) return;
   if(CopyBuffer(h_ADX, 0, 0, 3, adx) < 3) return;
   
   double ask = m_symbol.Ask();
   double bid = m_symbol.Bid();
   double currentATR = atr[1];
   double close1 = iClose(g_symbol, InpTimeframe, 1);
   
   // Confirm trend strength on the closed signal bar.
   if(adx[1] < InpADXTrendThreshold) return;
   
   // BUY: closed-bar cross up + price above trend MA + HTF agrees.
   if(fastMA[2] <= slowMA[2] && fastMA[1] > slowMA[1] &&
      close1 > trendMA[1] && htfBias >= 0)
   {
      double sl = ask - currentATR * InpTF_SL_ATRMult;
      double tp = ask + currentATR * InpTF_TP_ATRMult;
      double lot = CalculateLotSize(currentATR * InpTF_SL_ATRMult);
      
      if(!HasOpenPosition(POSITION_TYPE_BUY, "TF"))
         OpenTrade(ORDER_TYPE_BUY, lot, sl, tp, InpComment + "_TF");
   }
   
   // SELL: closed-bar cross down + price below trend MA + HTF agrees.
   if(fastMA[2] >= slowMA[2] && fastMA[1] < slowMA[1] &&
      close1 < trendMA[1] && htfBias <= 0)
   {
      double sl = bid + currentATR * InpTF_SL_ATRMult;
      double tp = bid - currentATR * InpTF_TP_ATRMult;
      double lot = CalculateLotSize(currentATR * InpTF_SL_ATRMult);
      
      if(!HasOpenPosition(POSITION_TYPE_SELL, "TF"))
         OpenTrade(ORDER_TYPE_SELL, lot, sl, tp, InpComment + "_TF");
   }
}

//+------------------------------------------------------------------+
//| STRATEGY 2: MEAN REVERSION (BB + RSI Divergence)                  |
//+------------------------------------------------------------------+
void Strategy_MeanReversion(int htfBias)
{
   double bbUpper[], bbLower[], bbMiddle[], rsi[], atr[];
   ArraySetAsSeries(bbUpper, true);
   ArraySetAsSeries(bbLower, true);
   ArraySetAsSeries(bbMiddle, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(atr, true);
   
   if(CopyBuffer(h_BB, 1, 0, 3, bbUpper) < 3) return;
   if(CopyBuffer(h_BB, 2, 0, 3, bbLower) < 3) return;
   if(CopyBuffer(h_BB, 0, 0, 3, bbMiddle) < 3) return;
   if(CopyBuffer(h_RSI, 0, 0, 5, rsi) < 5) return;
   if(CopyBuffer(h_ATR, 0, 0, 3, atr) < 3) return;
   
   double ask = m_symbol.Ask();
   double bid = m_symbol.Bid();
   double close1 = iClose(g_symbol, InpTimeframe, 1);
   double close2 = iClose(g_symbol, InpTimeframe, 2);
   double currentATR = atr[1];
   
   // Only trade in ranging/quiet markets or with HTF alignment
   if(g_currentRegime == REGIME_STRONG_TREND_UP || g_currentRegime == REGIME_STRONG_TREND_DOWN)
      return;
   
   // BUY: Price touches/pierces lower BB + RSI oversold + Bullish candle
   if(close2 <= bbLower[2] && close1 > bbLower[1] &&
      rsi[1] < InpRSIOversold && close1 > iOpen(g_symbol, InpTimeframe, 1) &&
      htfBias >= 0)
   {
      double sl = ask - currentATR * InpMR_SL_ATRMult;
      double tp = bbMiddle[1]; // Target middle band
      if(tp - ask < currentATR * 0.5) tp = ask + currentATR * InpMR_TP_ATRMult;
      double lot = CalculateLotSize(currentATR * InpMR_SL_ATRMult);
      
      if(!HasOpenPosition(POSITION_TYPE_BUY, "MR"))
         OpenTrade(ORDER_TYPE_BUY, lot, sl, tp, InpComment + "_MR");
   }
   
   // SELL: Price touches/pierces upper BB + RSI overbought + Bearish candle
   if(close2 >= bbUpper[2] && close1 < bbUpper[1] &&
      rsi[1] > InpRSIOverbought && close1 < iOpen(g_symbol, InpTimeframe, 1) &&
      htfBias <= 0)
   {
      double sl = bid + currentATR * InpMR_SL_ATRMult;
      double tp = bbMiddle[1];
      if(bid - tp < currentATR * 0.5) tp = bid - currentATR * InpMR_TP_ATRMult;
      double lot = CalculateLotSize(currentATR * InpMR_SL_ATRMult);
      
      if(!HasOpenPosition(POSITION_TYPE_SELL, "MR"))
         OpenTrade(ORDER_TYPE_SELL, lot, sl, tp, InpComment + "_MR");
   }
}

//+------------------------------------------------------------------+
//| STRATEGY 3: BREAKOUT (Range Break + Volume Confirmation)          |
//+------------------------------------------------------------------+
void Strategy_Breakout(int htfBias)
{
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(h_ATR, 0, 0, 3, atr) < 3) return;
   
   double ask = m_symbol.Ask();
   double bid = m_symbol.Bid();
   double close1 = iClose(g_symbol, InpTimeframe, 1);
   double currentATR = atr[1];
   
   // Find highest high and lowest low over lookback (exclude signal candle).
   double highestHigh = 0, lowestLow = DBL_MAX;
   for(int i = 2; i <= InpBreakoutPeriod + 1; i++)
   {
      double h = iHigh(g_symbol, InpTimeframe, i);
      double l = iLow(g_symbol, InpTimeframe, i);
      if(h > highestHigh) highestHigh = h;
      if(l < lowestLow) lowestLow = l;
   }
   
   // Volume confirmation
   bool volumeSpike = false;
   long currentVol = iVolume(g_symbol, InpTimeframe, 1);
   double avgVol = 0;
   for(int i = 2; i <= InpVolumePeriod + 1; i++)
      avgVol += iVolume(g_symbol, InpTimeframe, i);
   if(InpVolumePeriod > 0) avgVol /= InpVolumePeriod;
   if(avgVol <= 0) return;
   if(currentVol > avgVol * InpVolumeMultiplier)
      volumeSpike = true;
   
   // ATR filter - only trade breakouts with expanding volatility
   double prevATR = atr[2];
   bool atrExpanding = currentATR > prevATR * InpBreakoutATRFilter;
   
   // BUY breakout
   if(close1 > highestHigh && volumeSpike && (atrExpanding || currentATR > prevATR) && htfBias >= 0)
   {
      double sl = ask - currentATR * InpBO_SL_ATRMult;
      double tp = ask + currentATR * InpBO_TP_ATRMult;
      double lot = CalculateLotSize(currentATR * InpBO_SL_ATRMult);
      
      if(!HasOpenPosition(POSITION_TYPE_BUY, "BO"))
         OpenTrade(ORDER_TYPE_BUY, lot, sl, tp, InpComment + "_BO");
   }
   
   // SELL breakout
   if(close1 < lowestLow && volumeSpike && (atrExpanding || currentATR > prevATR) && htfBias <= 0)
   {
      double sl = bid + currentATR * InpBO_SL_ATRMult;
      double tp = bid - currentATR * InpBO_TP_ATRMult;
      double lot = CalculateLotSize(currentATR * InpBO_SL_ATRMult);
      
      if(!HasOpenPosition(POSITION_TYPE_SELL, "BO"))
         OpenTrade(ORDER_TYPE_SELL, lot, sl, tp, InpComment + "_BO");
   }
}

//+------------------------------------------------------------------+
//| STRATEGY 4: MOMENTUM SCALPING (MACD + Stochastic + RSI)          |
//+------------------------------------------------------------------+
void Strategy_MomentumScalp(int htfBias)
{
   double macdMain[], macdSignal[], stochK[], stochD[], rsi[], atr[];
   ArraySetAsSeries(macdMain, true);
   ArraySetAsSeries(macdSignal, true);
   ArraySetAsSeries(stochK, true);
   ArraySetAsSeries(stochD, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(atr, true);
   
   if(CopyBuffer(h_MACD, 0, 0, 3, macdMain) < 3) return;
   if(CopyBuffer(h_MACD, 1, 0, 3, macdSignal) < 3) return;
   if(CopyBuffer(h_Stoch, 0, 0, 3, stochK) < 3) return;
   if(CopyBuffer(h_Stoch, 1, 0, 3, stochD) < 3) return;
   if(CopyBuffer(h_RSI, 0, 0, 3, rsi) < 3) return;
   if(CopyBuffer(h_ATR, 0, 0, 3, atr) < 3) return;
   
   double ask = m_symbol.Ask();
   double bid = m_symbol.Bid();
   double currentATR = atr[1];
   
   // BUY: closed-bar MACD cross up + Stoch from oversold + RSI rising.
   bool macdBullCross = macdMain[2] <= macdSignal[2] && macdMain[1] > macdSignal[1];
   bool stochBullish = stochK[2] < 30 && stochK[1] > stochD[1];
   bool rsiBullish = rsi[1] > rsi[2] && rsi[1] > 40 && rsi[1] < 65;
   
   if(macdBullCross && stochBullish && rsiBullish && htfBias >= 0)
   {
      double sl = ask - currentATR * InpMS_SL_ATRMult;
      double tp = ask + currentATR * InpMS_TP_ATRMult;
      double lot = CalculateLotSize(currentATR * InpMS_SL_ATRMult);
      
      if(!HasOpenPosition(POSITION_TYPE_BUY, "MS"))
         OpenTrade(ORDER_TYPE_BUY, lot, sl, tp, InpComment + "_MS");
   }
   
   // SELL: closed-bar MACD cross down + Stoch from overbought + RSI falling.
   bool macdBearCross = macdMain[2] >= macdSignal[2] && macdMain[1] < macdSignal[1];
   bool stochBearish = stochK[2] > 70 && stochK[1] < stochD[1];
   bool rsiBearish = rsi[1] < rsi[2] && rsi[1] < 60 && rsi[1] > 35;
   
   if(macdBearCross && stochBearish && rsiBearish && htfBias <= 0)
   {
      double sl = bid + currentATR * InpMS_SL_ATRMult;
      double tp = bid - currentATR * InpMS_TP_ATRMult;
      double lot = CalculateLotSize(currentATR * InpMS_SL_ATRMult);
      
      if(!HasOpenPosition(POSITION_TYPE_SELL, "MS"))
         OpenTrade(ORDER_TYPE_SELL, lot, sl, tp, InpComment + "_MS");
   }
}

//+------------------------------------------------------------------+
//| STRATEGY 5: SMART MONEY CONCEPTS (Order Blocks + FVG + BOS)      |
//+------------------------------------------------------------------+
void Strategy_SMC(int htfBias)
{
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(h_ATR, 0, 0, 3, atr) < 3) return;
   
   double ask = m_symbol.Ask();
   double bid = m_symbol.Bid();
   double currentATR = atr[1];
   
   // Detect structure
   DetectOrderBlocks();
   DetectFVGs();
   
   // Check for Break of Structure
   int bosDirection = DetectBOS();
   
   // BUY: Bullish BOS + Price at bullish OB or FVG
   if(bosDirection > 0 && htfBias >= 0)
   {
      // Check if price is at a bullish order block
      for(int i = ArraySize(g_orderBlocks) - 1; i >= 0; i--)
      {
         if(!g_orderBlocks[i].isValid || !g_orderBlocks[i].isBullish) continue;
         
         if(ask >= g_orderBlocks[i].priceLow && ask <= g_orderBlocks[i].priceHigh)
         {
            double sl = g_orderBlocks[i].priceLow - currentATR * 0.5;
            double tp = ask + currentATR * InpSMC_TP_ATRMult;
            double lot = CalculateLotSize(ask - sl);
            
            if(!HasOpenPosition(POSITION_TYPE_BUY, "SMC"))
            {
               OpenTrade(ORDER_TYPE_BUY, lot, sl, tp, InpComment + "_SMC");
               g_orderBlocks[i].isValid = false; // Mark as used
            }
            break;
         }
      }
      
      // Check FVGs
      for(int i = ArraySize(g_fvgs) - 1; i >= 0; i--)
      {
         if(!g_fvgs[i].isValid || !g_fvgs[i].isBullish) continue;
         
         if(ask >= g_fvgs[i].low && ask <= g_fvgs[i].high)
         {
            double sl = g_fvgs[i].low - currentATR * 0.5;
            double tp = ask + currentATR * InpSMC_TP_ATRMult;
            double lot = CalculateLotSize(ask - sl);
            
            if(!HasOpenPosition(POSITION_TYPE_BUY, "SMC"))
            {
               OpenTrade(ORDER_TYPE_BUY, lot, sl, tp, InpComment + "_SMC");
               g_fvgs[i].isValid = false;
            }
            break;
         }
      }
   }
   
   // SELL: Bearish BOS + Price at bearish OB or FVG
   if(bosDirection < 0 && htfBias <= 0)
   {
      for(int i = ArraySize(g_orderBlocks) - 1; i >= 0; i--)
      {
         if(!g_orderBlocks[i].isValid || g_orderBlocks[i].isBullish) continue;
         
         if(bid <= g_orderBlocks[i].priceHigh && bid >= g_orderBlocks[i].priceLow)
         {
            double sl = g_orderBlocks[i].priceHigh + currentATR * 0.5;
            double tp = bid - currentATR * InpSMC_TP_ATRMult;
            double lot = CalculateLotSize(sl - bid);
            
            if(!HasOpenPosition(POSITION_TYPE_SELL, "SMC"))
            {
               OpenTrade(ORDER_TYPE_SELL, lot, sl, tp, InpComment + "_SMC");
               g_orderBlocks[i].isValid = false;
            }
            break;
         }
      }
      
      for(int i = ArraySize(g_fvgs) - 1; i >= 0; i--)
      {
         if(!g_fvgs[i].isValid || g_fvgs[i].isBullish) continue;
         
         if(bid <= g_fvgs[i].high && bid >= g_fvgs[i].low)
         {
            double sl = g_fvgs[i].high + currentATR * 0.5;
            double tp = bid - currentATR * InpSMC_TP_ATRMult;
            double lot = CalculateLotSize(sl - bid);
            
            if(!HasOpenPosition(POSITION_TYPE_SELL, "SMC"))
            {
               OpenTrade(ORDER_TYPE_SELL, lot, sl, tp, InpComment + "_SMC");
               g_fvgs[i].isValid = false;
            }
            break;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| SMC: Detect Order Blocks                                           |
//+------------------------------------------------------------------+
void DetectOrderBlocks()
{
   ArrayResize(g_orderBlocks, 0);
   
   for(int i = 1; i < InpSMC_OBLookback - 1; i++)
   {
      double open_i  = iOpen(g_symbol, InpTimeframe, i);
      double close_i = iClose(g_symbol, InpTimeframe, i);
      double high_i  = iHigh(g_symbol, InpTimeframe, i);
      double low_i   = iLow(g_symbol, InpTimeframe, i);
      
      double open_next  = iOpen(g_symbol, InpTimeframe, i - 1);
      double close_next = iClose(g_symbol, InpTimeframe, i - 1);
      
      // Bullish OB: Bearish candle followed by strong bullish move
      if(close_i < open_i && close_next > open_next)
      {
         double bodyNext = MathAbs(close_next - open_next);
         double bodyThis = MathAbs(open_i - close_i);
         
         if(bodyNext > bodyThis * 1.5) // Strong engulfing
         {
            OrderBlock ob;
            ob.priceHigh = open_i;
            ob.priceLow  = close_i;
            ob.time = iTime(g_symbol, InpTimeframe, i);
            ob.isBullish = true;
            ob.isValid = true;
            
            int size = ArraySize(g_orderBlocks);
            ArrayResize(g_orderBlocks, size + 1);
            g_orderBlocks[size] = ob;
         }
      }
      
      // Bearish OB: Bullish candle followed by strong bearish move
      if(close_i > open_i && close_next < open_next)
      {
         double bodyNext = MathAbs(open_next - close_next);
         double bodyThis = MathAbs(close_i - open_i);
         
         if(bodyNext > bodyThis * 1.5)
         {
            OrderBlock ob;
            ob.priceHigh = close_i;
            ob.priceLow  = open_i;
            ob.time = iTime(g_symbol, InpTimeframe, i);
            ob.isBullish = false;
            ob.isValid = true;
            
            int size = ArraySize(g_orderBlocks);
            ArrayResize(g_orderBlocks, size + 1);
            g_orderBlocks[size] = ob;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| SMC: Detect Fair Value Gaps                                        |
//+------------------------------------------------------------------+
void DetectFVGs()
{
   ArrayResize(g_fvgs, 0);
   
   for(int i = 2; i < InpSMC_OBLookback; i++)
   {
      double high3 = iHigh(g_symbol, InpTimeframe, i);
      double low3  = iLow(g_symbol, InpTimeframe, i);
      double high2 = iHigh(g_symbol, InpTimeframe, i - 1);
      double low2  = iLow(g_symbol, InpTimeframe, i - 1);
      double high1 = iHigh(g_symbol, InpTimeframe, i - 2);
      double low1  = iLow(g_symbol, InpTimeframe, i - 2);
      
      // Bullish FVG: Gap between candle 3's high and candle 1's low
      if(low1 > high3)
      {
         double gapSize = low1 - high3;
         if(gapSize >= InpSMC_FVGMinSize * m_symbol.Point())
         {
            FairValueGap fvg;
            fvg.high = low1;
            fvg.low  = high3;
            fvg.time = iTime(g_symbol, InpTimeframe, i - 1);
            fvg.isBullish = true;
            fvg.isValid = true;
            
            int size = ArraySize(g_fvgs);
            ArrayResize(g_fvgs, size + 1);
            g_fvgs[size] = fvg;
         }
      }
      
      // Bearish FVG
      if(high1 < low3)
      {
         double gapSize = low3 - high1;
         if(gapSize >= InpSMC_FVGMinSize * m_symbol.Point())
         {
            FairValueGap fvg;
            fvg.high = low3;
            fvg.low  = high1;
            fvg.time = iTime(g_symbol, InpTimeframe, i - 1);
            fvg.isBullish = false;
            fvg.isValid = true;
            
            int size = ArraySize(g_fvgs);
            ArrayResize(g_fvgs, size + 1);
            g_fvgs[size] = fvg;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| SMC: Detect Break of Structure                                     |
//+------------------------------------------------------------------+
int DetectBOS()
{
   // Find swing highs and lows
   double swingHigh = 0, swingLow = DBL_MAX;
   double prevSwingHigh = 0, prevSwingLow = DBL_MAX;
   
   int shIdx = -1, slIdx = -1;
   
   for(int i = InpSMC_SwingLookback; i < InpSMC_SwingLookback * 3; i++)
   {
      if(IsSwingHigh(i, InpSMC_SwingLookback))
      {
         if(shIdx == -1)
         {
            swingHigh = iHigh(g_symbol, InpTimeframe, i);
            shIdx = i;
         }
         else if(prevSwingHigh == 0)
         {
            prevSwingHigh = iHigh(g_symbol, InpTimeframe, i);
         }
      }
      
      if(IsSwingLow(i, InpSMC_SwingLookback))
      {
         if(slIdx == -1)
         {
            swingLow = iLow(g_symbol, InpTimeframe, i);
            slIdx = i;
         }
         else if(prevSwingLow == DBL_MAX)
         {
            prevSwingLow = iLow(g_symbol, InpTimeframe, i);
         }
      }
   }
   
   double currentClose = iClose(g_symbol, InpTimeframe, 0);
   
   // Bullish BOS: Price closes above recent swing high
   if(swingHigh > 0 && currentClose > swingHigh)
      return 1;
   
   // Bearish BOS: Price closes below recent swing low
   if(swingLow < DBL_MAX && currentClose < swingLow)
      return -1;
   
   return 0;
}

//+------------------------------------------------------------------+
//| Check if bar is a swing high                                       |
//+------------------------------------------------------------------+
bool IsSwingHigh(int index, int lookback)
{
   double high = iHigh(g_symbol, InpTimeframe, index);
   
   for(int i = 1; i <= lookback; i++)
   {
      if(iHigh(g_symbol, InpTimeframe, index - i) >= high) return false;
      if(iHigh(g_symbol, InpTimeframe, index + i) >= high) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Check if bar is a swing low                                        |
//+------------------------------------------------------------------+
bool IsSwingLow(int index, int lookback)
{
   double low = iLow(g_symbol, InpTimeframe, index);
   
   for(int i = 1; i <= lookback; i++)
   {
      if(iLow(g_symbol, InpTimeframe, index - i) <= low) return false;
      if(iLow(g_symbol, InpTimeframe, index + i) <= low) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| HIGHER TIMEFRAME BIAS                                              |
//+------------------------------------------------------------------+
int GetHTFBias()
{
   double fastHTF[], slowHTF[];
   ArraySetAsSeries(fastHTF, true);
   ArraySetAsSeries(slowHTF, true);
   
   if(CopyBuffer(h_fastMA_HTF, 0, 0, 3, fastHTF) < 3) return 0;
   if(CopyBuffer(h_slowMA_HTF, 0, 0, 3, slowHTF) < 3) return 0;
   
   if(fastHTF[0] > slowHTF[0] && fastHTF[1] > slowHTF[1]) return 1;   // Bullish
   if(fastHTF[0] < slowHTF[0] && fastHTF[1] < slowHTF[1]) return -1;  // Bearish
   
   return 0; // Neutral
}

//+------------------------------------------------------------------+
//| POSITION MANAGEMENT (Trailing + Breakeven)                        |
//+------------------------------------------------------------------+
void ManagePositions()
{
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(h_ATR, 0, 0, 3, atr) < 3) return;
   
   double currentATR = atr[0];
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!m_position.SelectByIndex(i)) continue;
      if(m_position.Magic() != InpMagicNumber) continue;
      if(m_position.Symbol() != g_symbol) continue;
      
      double openPrice = m_position.PriceOpen();
      double currentSL = m_position.StopLoss();
      double currentTP = m_position.TakeProfit();
      double profit    = m_position.Profit();
      
      if(m_position.PositionType() == POSITION_TYPE_BUY)
      {
         double currentBid = m_symbol.Bid();
         
         // Breakeven
         if(InpUseBreakeven && currentSL < openPrice)
         {
            if(currentBid - openPrice >= currentATR * InpBreakevenATRMult)
            {
               double newSL = openPrice + m_symbol.Spread() * m_symbol.Point();
               newSL = NormalizeDouble(newSL, m_symbol.Digits());
               if(newSL > currentSL)
                  m_trade.PositionModify(m_position.Ticket(), newSL, currentTP);
            }
         }
         
         // Trailing Stop
         if(InpUseTrailingStop && currentBid - openPrice > currentATR * InpTrailingATRMult)
         {
            double trailSL = currentBid - currentATR * InpTrailingATRMult;
            trailSL = NormalizeDouble(trailSL, m_symbol.Digits());
            if(trailSL > currentSL)
               m_trade.PositionModify(m_position.Ticket(), trailSL, currentTP);
         }
      }
      else if(m_position.PositionType() == POSITION_TYPE_SELL)
      {
         double currentAsk = m_symbol.Ask();
         
         // Breakeven
         if(InpUseBreakeven && (currentSL > openPrice || currentSL == 0))
         {
            if(openPrice - currentAsk >= currentATR * InpBreakevenATRMult)
            {
               double newSL = openPrice - m_symbol.Spread() * m_symbol.Point();
               newSL = NormalizeDouble(newSL, m_symbol.Digits());
               if(newSL < currentSL || currentSL == 0)
                  m_trade.PositionModify(m_position.Ticket(), newSL, currentTP);
            }
         }
         
         // Trailing Stop
         if(InpUseTrailingStop && openPrice - currentAsk > currentATR * InpTrailingATRMult)
         {
            double trailSL = currentAsk + currentATR * InpTrailingATRMult;
            trailSL = NormalizeDouble(trailSL, m_symbol.Digits());
            if(trailSL < currentSL || currentSL == 0)
               m_trade.PositionModify(m_position.Ticket(), trailSL, currentTP);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| LOT SIZE CALCULATOR                                                |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
{
   if(InpRiskMode == RISK_FIXED_LOT)
      return NormalizeLot(InpFixedLot);
   if(InpRiskPercent <= 0)
      return NormalizeLot(InpFixedLot);
   
   double balance = m_account.Balance();
   double riskAmount = balance * InpRiskPercent / 100.0;
   
   // For dynamic mode, adjust risk based on regime confidence
   if(InpRiskMode == RISK_DYNAMIC)
   {
      switch(g_currentRegime)
      {
         case REGIME_STRONG_TREND_UP:
         case REGIME_STRONG_TREND_DOWN:
            riskAmount *= 1.2; // Increase risk in strong trends
            break;
         case REGIME_VOLATILE:
            riskAmount *= 0.6; // Reduce risk in volatile markets
            break;
         case REGIME_QUIET:
            riskAmount *= 0.8;
            break;
         default:
            break;
      }
   }
   
   if(slDistance <= 0) return NormalizeLot(InpFixedLot);
   
   double tickValue = m_symbol.TickValue();
   double tickSize  = m_symbol.TickSize();
   
   if(tickValue <= 0 || tickSize <= 0) return NormalizeLot(InpFixedLot);
   
   double lots = riskAmount / (slDistance / tickSize * tickValue);
   
   return NormalizeLot(lots);
}

//+------------------------------------------------------------------+
//| Normalize lot size                                                 |
//+------------------------------------------------------------------+
double NormalizeLot(double lots)
{
   double minLot  = m_symbol.LotsMin();
   double maxLot  = m_symbol.LotsMax();
   double lotStep = m_symbol.LotsStep();
   if(lotStep <= 0) lotStep = minLot;
   
   lots = MathMax(lots, minLot);
   lots = MathMin(lots, maxLot);
   lots = NormalizeDouble(MathFloor(lots / lotStep) * lotStep, 2);
   
   return lots;
}

//+------------------------------------------------------------------+
//| OPEN TRADE                                                         |
//+------------------------------------------------------------------+
bool OpenTrade(ENUM_ORDER_TYPE type, double lots, double sl, double tp, string comment)
{
   if(type != ORDER_TYPE_BUY && type != ORDER_TYPE_SELL)
      return false;

   if(CountPositions() >= InpMaxOpenTrades)
      return false;

   if(!IsSpreadAcceptable())
      return false;

   if(InpMinMinutesBetweenTrades > 0 && g_lastTradeTime > 0)
   {
      if((TimeCurrent() - g_lastTradeTime) < (InpMinMinutesBetweenTrades * 60))
         return false;
   }

   if(!m_symbol.RefreshRates())
      return false;
   
   double price = (type == ORDER_TYPE_BUY) ? m_symbol.Ask() : m_symbol.Bid();

   // Validate SL/TP distances.
   double minStopLevel = m_symbol.StopsLevel() * m_symbol.Point();
   if(minStopLevel <= 0) minStopLevel = m_symbol.Spread() * m_symbol.Point() * 2;
   if(minStopLevel <= 0) minStopLevel = 2.0 * m_symbol.Point();
   
   if(type == ORDER_TYPE_BUY)
   {
      if(price - sl < minStopLevel) sl = price - minStopLevel;
      if(tp - price < minStopLevel) tp = price + minStopLevel;
   }
   else
   {
      if(sl - price < minStopLevel) sl = price + minStopLevel;
      if(price - tp < minStopLevel) tp = price - minStopLevel;
   }

   double slDistance = MathAbs(price - sl);
   if(slDistance <= 0)
      return false;

   // Enforce a minimum reward:risk profile for entries.
   double minRR = MathMax(InpMinRewardRisk, 0.1);
   if(type == ORDER_TYPE_BUY && (tp - price) < slDistance * minRR)
      tp = price + slDistance * minRR;
   if(type == ORDER_TYPE_SELL && (price - tp) < slDistance * minRR)
      tp = price - slDistance * minRR;

   sl = NormalizeDouble(sl, m_symbol.Digits());
   tp = NormalizeDouble(tp, m_symbol.Digits());

   // Recompute size from final SL distance in percent/dynamic modes.
   slDistance = MathAbs(price - sl);
   if(InpRiskMode != RISK_FIXED_LOT)
      lots = CalculateLotSize(slDistance);
   lots = NormalizeLot(lots);
   
   bool result = m_trade.PositionOpen(g_symbol, type, lots, price, sl, tp, comment);
   
   if(result)
   {
      g_lastTradeTime = TimeCurrent();
      Print("TRADE OPENED: ", comment, " | Type: ", EnumToString(type), 
            " | Lots: ", lots, " | Price: ", price, " | SL: ", sl, " | TP: ", tp,
            " | Retcode: ", m_trade.ResultRetcode());
   }
   else
   {
      Print("TRADE FAILED: ", comment, " | Error: ", GetLastError(), 
            " | Retcode: ", m_trade.ResultRetcode(),
            " | ", m_trade.ResultRetcodeDescription());
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| UTILITY FUNCTIONS                                                  |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(g_symbol, InpTimeframe, 0);
   if(currentBarTime == g_lastBarTime) return false;
   g_lastBarTime = currentBarTime;
   return true;
}

int CountPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!m_position.SelectByIndex(i)) continue;
      if(m_position.Magic() == InpMagicNumber && m_position.Symbol() == g_symbol)
         count++;
   }
   return count;
}

bool HasOpenPosition(ENUM_POSITION_TYPE type, string stratTag)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!m_position.SelectByIndex(i)) continue;
      if(m_position.Magic() != InpMagicNumber) continue;
      if(m_position.Symbol() != g_symbol) continue;
      if(m_position.PositionType() != type) continue;
      
      string comment = m_position.Comment();
      if(StringFind(comment, stratTag) >= 0) return true;
   }
   return false;
}

bool IsSpreadAcceptable()
{
   if(InpMaxSpreadPoints <= 0) return true;
   if(m_symbol.Point() <= 0) return true;

   double spreadPoints = (m_symbol.Ask() - m_symbol.Bid()) / m_symbol.Point();
   return spreadPoints <= InpMaxSpreadPoints;
}

bool IsValidSession()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   int hour = dt.hour;
   
   if(InpTradeLondon && hour >= InpLondonStart && hour < InpLondonEnd) return true;
   if(InpTradeNewYork && hour >= InpNewYorkStart && hour < InpNewYorkEnd) return true;
   if(InpTradeAsian)
   {
      if(InpAsianStart < InpAsianEnd)
      {
         if(hour >= InpAsianStart && hour < InpAsianEnd) return true;
      }
      else
      {
         if(hour >= InpAsianStart || hour < InpAsianEnd) return true;
      }
   }
   
   return false;
}

bool IsDrawdownExceeded()
{
   double balance = m_account.Balance();
   double equity  = m_account.Equity();
   
   if(balance > g_peakBalance) g_peakBalance = balance;
   if(g_peakBalance <= 0) return false;
   
   double dd = (g_peakBalance - equity) / g_peakBalance * 100.0;
   
   return dd >= InpMaxDrawdownPct;
}

bool IsDailyLossExceeded()
{
   if(g_dayStartBalance <= 0) return false;

   double equity = m_account.Equity();
   double dailyLossPct = (g_dayStartBalance - equity) / g_dayStartBalance * 100.0;

   return dailyLossPct >= InpMaxDailyLossPct;
}

void UpdateDailyTracking()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   datetime today = StringToTime(IntegerToString(dt.year) + "." + 
                                  IntegerToString(dt.mon) + "." + 
                                  IntegerToString(dt.day));
   
   if(today != g_lastDay)
   {
      g_dailyPL = 0;
      g_lastDay = today;
      g_dayStartBalance = m_account.Balance();
   }
}

void UpdateStrategyScore(string comment, double profit)
{
   int stratIdx = -1;
   if(StringFind(comment, "_TF") >= 0)  stratIdx = STRAT_TREND_FOLLOW;
   if(StringFind(comment, "_MR") >= 0)  stratIdx = STRAT_MEAN_REVERSION;
   if(StringFind(comment, "_BO") >= 0)  stratIdx = STRAT_BREAKOUT;
   if(StringFind(comment, "_MS") >= 0)  stratIdx = STRAT_MOMENTUM_SCALP;
   if(StringFind(comment, "_SMC") >= 0) stratIdx = STRAT_SMC;
   
   if(stratIdx >= 0)
   {
      // Exponential moving average scoring
      double scoreChange = (profit > 0) ? 5.0 : -3.0;
      g_strategyScores[stratIdx] = g_strategyScores[stratIdx] * 0.9 + scoreChange;
      g_strategyScores[stratIdx] = MathMax(10.0, MathMin(100.0, g_strategyScores[stratIdx]));
   }
}

void PrintStats()
{
   double winRate = (g_totalTrades > 0) ? (double)g_winTrades / g_totalTrades * 100.0 : 0;
   double profitFactor = (g_totalLoss > 0) ? g_totalProfit / g_totalLoss : 0;
   
   Print("===== PERFORMANCE STATS =====");
   Print("Total Trades: ", g_totalTrades);
   Print("Win/Loss: ", g_winTrades, "/", g_lossTrades);
   Print("Win Rate: ", DoubleToString(winRate, 1), "%");
   Print("Profit Factor: ", DoubleToString(profitFactor, 2));
   Print("Max Drawdown: ", DoubleToString(g_maxDrawdown, 2), "%");
   Print("Net Profit: $", DoubleToString(g_totalProfit - g_totalLoss, 2));
}

//+------------------------------------------------------------------+
//| DASHBOARD                                                          |
//+------------------------------------------------------------------+
void CreateDashboard()
{
   int x = 10, y = 30, w = 280, h = 400;
   
   ObjectCreate(0, "DASH_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "DASH_BG", OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, "DASH_BG", OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, "DASH_BG", OBJPROP_XSIZE, w);
   ObjectSetInteger(0, "DASH_BG", OBJPROP_YSIZE, h);
   ObjectSetInteger(0, "DASH_BG", OBJPROP_BGCOLOR, InpDashBG);
   ObjectSetInteger(0, "DASH_BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, "DASH_BG", OBJPROP_BORDER_COLOR, clrGold);
   ObjectSetInteger(0, "DASH_BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "DASH_BG", OBJPROP_BACK, false);
}

void UpdateDashboard()
{
   int x = 15, y = 35, lineH = 18;
   int line = 0;
   
   string regimeStr;
   color regimeClr;
   switch(g_currentRegime)
   {
      case REGIME_STRONG_TREND_UP:   regimeStr = "STRONG TREND UP";   regimeClr = clrLime; break;
      case REGIME_WEAK_TREND_UP:     regimeStr = "WEAK TREND UP";     regimeClr = clrGreen; break;
      case REGIME_RANGING:           regimeStr = "RANGING";           regimeClr = clrYellow; break;
      case REGIME_WEAK_TREND_DOWN:   regimeStr = "WEAK TREND DOWN";   regimeClr = clrOrange; break;
      case REGIME_STRONG_TREND_DOWN: regimeStr = "STRONG TREND DOWN"; regimeClr = clrRed; break;
      case REGIME_VOLATILE:          regimeStr = "HIGH VOLATILITY";   regimeClr = clrMagenta; break;
      case REGIME_QUIET:             regimeStr = "QUIET MARKET";      regimeClr = clrGray; break;
   }
   
   string stratStr;
   switch(g_activeStrategy)
   {
      case STRAT_TREND_FOLLOW:   stratStr = "Trend Following"; break;
      case STRAT_MEAN_REVERSION: stratStr = "Mean Reversion"; break;
      case STRAT_BREAKOUT:       stratStr = "Breakout"; break;
      case STRAT_MOMENTUM_SCALP: stratStr = "Momentum Scalp"; break;
      case STRAT_SMC:            stratStr = "Smart Money (SMC)"; break;
   }
   
   double winRate = (g_totalTrades > 0) ? (double)g_winTrades / g_totalTrades * 100.0 : 0;
   double pf = (g_totalLoss > 0) ? g_totalProfit / g_totalLoss : 0;
   double netPL = g_totalProfit - g_totalLoss;
   
   DashLabel("DASH_Title",  x, y + lineH * line++, "══ XAUUSD ULTIMATE EA ══", clrGold, InpDashFontSize + 2);
   DashLabel("DASH_Sep1",   x, y + lineH * line++, "─────────────────────────────", clrGray, InpDashFontSize);
   DashLabel("DASH_Regime", x, y + lineH * line++, "Regime: " + regimeStr, regimeClr, InpDashFontSize);
   DashLabel("DASH_Strat",  x, y + lineH * line++, "Strategy: " + stratStr, clrCyan, InpDashFontSize);
   DashLabel("DASH_Sep2",   x, y + lineH * line++, "─────────────────────────────", clrGray, InpDashFontSize);
   DashLabel("DASH_Bal",    x, y + lineH * line++, "Balance: $" + DoubleToString(m_account.Balance(), 2), InpDashText, InpDashFontSize);
   DashLabel("DASH_Eq",     x, y + lineH * line++, "Equity:  $" + DoubleToString(m_account.Equity(), 2), InpDashText, InpDashFontSize);
   DashLabel("DASH_DPL",    x, y + lineH * line++, "Daily P/L: $" + DoubleToString(g_dailyPL, 2), (g_dailyPL >= 0 ? clrLime : clrRed), InpDashFontSize);
   DashLabel("DASH_Sep3",   x, y + lineH * line++, "─────────────────────────────", clrGray, InpDashFontSize);
   DashLabel("DASH_Trades", x, y + lineH * line++, "Trades: " + IntegerToString(g_totalTrades) + " (W:" + IntegerToString(g_winTrades) + " L:" + IntegerToString(g_lossTrades) + ")", InpDashText, InpDashFontSize);
   DashLabel("DASH_WR",     x, y + lineH * line++, "Win Rate: " + DoubleToString(winRate, 1) + "%", (winRate >= 50 ? clrLime : clrOrange), InpDashFontSize);
   DashLabel("DASH_PF",     x, y + lineH * line++, "Profit Factor: " + DoubleToString(pf, 2), (pf >= 1.5 ? clrLime : clrOrange), InpDashFontSize);
   DashLabel("DASH_Net",    x, y + lineH * line++, "Net P/L: $" + DoubleToString(netPL, 2), (netPL >= 0 ? clrLime : clrRed), InpDashFontSize);
   DashLabel("DASH_DD",     x, y + lineH * line++, "Max DD: " + DoubleToString(g_maxDrawdown, 2) + "%", (g_maxDrawdown < 5 ? clrLime : clrRed), InpDashFontSize);
   DashLabel("DASH_Sep4",   x, y + lineH * line++, "─────────────────────────────", clrGray, InpDashFontSize);
   DashLabel("DASH_Open",   x, y + lineH * line++, "Open Positions: " + IntegerToString(CountPositions()) + "/" + IntegerToString(InpMaxOpenTrades), InpDashText, InpDashFontSize);
   DashLabel("DASH_Sep5",   x, y + lineH * line++, "─────────────────────────────", clrGray, InpDashFontSize);
   DashLabel("DASH_S1",     x, y + lineH * line++, "TF Score: " + DoubleToString(g_strategyScores[0], 1), clrWhite, InpDashFontSize);
   DashLabel("DASH_S2",     x, y + lineH * line++, "MR Score: " + DoubleToString(g_strategyScores[1], 1), clrWhite, InpDashFontSize);
   DashLabel("DASH_S3",     x, y + lineH * line++, "BO Score: " + DoubleToString(g_strategyScores[2], 1), clrWhite, InpDashFontSize);
   DashLabel("DASH_S4",     x, y + lineH * line++, "MS Score: " + DoubleToString(g_strategyScores[3], 1), clrWhite, InpDashFontSize);
   DashLabel("DASH_S5",     x, y + lineH * line++, "SMC Score: " + DoubleToString(g_strategyScores[4], 1), clrWhite, InpDashFontSize);
   
   ChartRedraw();
}

void DashLabel(string name, int x, int y, string text, color clr, int fontSize)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
}

//+------------------------------------------------------------------+
