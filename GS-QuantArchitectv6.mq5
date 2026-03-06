//+------------------------------------------------------------------+
//|                                         GS-QuantArchitectv6.mq5   |
//|   Rebuilt adaptive multi-strategy EA (robust MT5 execution)      |
//+------------------------------------------------------------------+
#property copyright "GS Quant Desk - Rebuilt"
#property link      "https://github.com/gs-quant"
#property version   "4.01"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

enum ENUM_RISK_LEVEL
{
   RISK_CONSERVATIVE = 0,
   RISK_MODERATE     = 1,
   RISK_AGGRESSIVE   = 2
};

enum ENUM_SESSION_FILTER
{
   SESSION_ALL       = 0,
   SESSION_LONDON    = 1,
   SESSION_NEWYORK   = 2,
   SESSION_OVERLAP   = 3,
   SESSION_ASIAN     = 4,
   SESSION_NO_ASIAN  = 5
};

input group "==== GLOBAL ===="
input int      InpMagicNumber               = 20260306;
input string   InpTradeComment              = "GSQ4";
input bool     InpDebugMode                 = true;
input bool     InpLogTrades                 = true;
input ENUM_TIMEFRAMES InpSignalTF           = PERIOD_M15;
input int      InpWarmupBars                = 20;

input group "==== EXECUTION SAFETY ===="
input int      InpMaxSlippage               = 30;     // points
input double   InpSpreadFilterPoints        = 0;      // 0 = off
input int      InpMinSecondsBetweenEntries  = 30;
input bool     InpAllowBuy                  = true;
input bool     InpAllowSell                 = true;
input bool     InpOnePositionPerDirection   = true;
input int      InpMaxOpenPositions          = 2;

input group "==== RISK ===="
input ENUM_RISK_LEVEL InpRiskLevel          = RISK_MODERATE;
input double   InpFixedLot                  = 0.00;   // 0 = risk based
input double   InpMaxDailyDrawdown          = 6.0;    // %
input double   InpMaxTotalDrawdown          = 20.0;   // %

input group "==== STRATEGY TOGGLES ===="
input bool     InpEnableTrend               = true;
input bool     InpEnableMeanReversion       = true;
input bool     InpEnableBreakout            = true;
input bool     InpEnableMomentum            = true;
input bool     InpEnableVolatility          = true;

input group "==== INDICATORS ===="
input int      InpATRPeriod                 = 14;
input int      InpEMAFast                   = 21;
input int      InpEMASlow                   = 55;
input int      InpEMATrend                  = 200;
input int      InpRSIPeriod                 = 14;
input double   InpRSIOverbought             = 68.0;
input double   InpRSIOversold               = 32.0;
input int      InpBBPeriod                  = 20;
input double   InpBBDev                     = 2.0;
input int      InpADXPeriod                 = 14;
input double   InpADXTrendMin               = 18.0;
input int      InpBreakoutLookback          = 24;
input int      InpATRFastPeriod             = 7;
input int      InpATRSlowPeriod             = 50;

input group "==== ADAPTIVE ENTRY ===="
input double   InpEntryScoreBase            = 35.0;
input double   InpEntryScoreMin             = 18.0;
input int      InpThresholdDecayBars        = 24;
input double   InpThresholdDecayStep        = 5.0;
input bool     InpGuaranteeActivity         = true;   // opens probe trade if no activity
input int      InpForceTradeBars            = 24;     // bars without trades before force

input group "==== OPTIMIZER TARGETS ===="
input double   InpOptMinProfitFactor        = 1.50;   // Custom max floor
input int      InpOptMinTrades              = 80;     // Stability floor

input group "==== EXIT / MANAGEMENT ===="
input double   InpSL_ATR_Mult               = 1.8;
input double   InpTP_RR                     = 2.2;
input double   InpTrailATR_Mult             = 1.2;
input double   InpBreakEvenATR              = 1.0;
input int      InpMaxHoldBars               = 280;    // 0 = disabled

input group "==== SESSION FILTER ===="
input ENUM_SESSION_FILTER InpSessionFilter  = SESSION_ALL;
input int      InpLondonStart               = 8;
input int      InpLondonEnd                 = 16;
input int      InpNYStart                   = 13;
input int      InpNYEnd                     = 21;
input int      InpAsianStart                = 0;
input int      InpAsianEnd                  = 8;
input bool     InpNoTradeFriday             = false;

CTrade        trade;
CPositionInfo posInfo;

// Indicator handles
int hATR = INVALID_HANDLE, hATRFast = INVALID_HANDLE, hATRSlow = INVALID_HANDLE;
int hEMAFast = INVALID_HANDLE, hEMASlow = INVALID_HANDLE, hEMATrend = INVALID_HANDLE;
int hRSI = INVALID_HANDLE, hBB = INVALID_HANDLE, hADX = INVALID_HANDLE, hMACD = INVALID_HANDLE;

// Symbol metadata
double g_point = 0.0, g_tickSize = 0.0, g_tickValue = 0.0, g_minLot = 0.01, g_maxLot = 100.0, g_lotStep = 0.01;
int    g_digits = 2, g_stopsLevelPts = 0, g_freezeLevelPts = 0;

// Market cache
double g_bid = 0.0, g_ask = 0.0, g_spread = 0.0;

// Indicator cache (closed bars)
double g_atr1 = 0.0, g_atrFast1 = 0.0, g_atrSlow1 = 0.0;
double g_emaFast1 = 0.0, g_emaFast2 = 0.0, g_emaSlow1 = 0.0, g_emaSlow2 = 0.0, g_emaTrend1 = 0.0;
double g_rsi1 = 50.0, g_rsi2 = 50.0;
double g_bbMid1 = 0.0, g_bbUp1 = 0.0, g_bbLow1 = 0.0;
double g_adx1 = 0.0, g_diPlus1 = 0.0, g_diMinus1 = 0.0;
double g_macdMain1 = 0.0, g_macdMain2 = 0.0, g_macdSig1 = 0.0, g_macdSig2 = 0.0;
double g_close1 = 0.0, g_close2 = 0.0;

// State
datetime g_lastSignalBar = 0;
datetime g_lastWarmupBar = 0;
datetime g_lastEntryTime = 0;
int      g_warmupCount = 0;
bool     g_ready = false;
bool     g_killSwitch = false;
int      g_barsSinceTrade = 0;
double   g_peakEquity = 0.0;
double   g_dayStartEquity = 0.0;
int      g_prevDay = -1;

int      g_totalOpen = 0, g_buyOpen = 0, g_sellOpen = 0;

//+------------------------------------------------------------------+
//| Helpers                                                           |
//+------------------------------------------------------------------+
bool IsNewBarTF(ENUM_TIMEFRAMES tf, datetime &lastBar)
{
   datetime t = iTime(_Symbol, tf, 0);
   if(t <= 0) return false;
   if(t != lastBar)
   {
      lastBar = t;
      return true;
   }
   return false;
}

bool GetBufVal(int handle, int buffer, int shift, double &out)
{
   if(handle == INVALID_HANDLE) return false;
   double tmp[1];
   if(CopyBuffer(handle, buffer, shift, 1, tmp) != 1) return false;
   out = tmp[0];
   return true;
}

bool RefreshSymbolMeta()
{
   g_bid      = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   g_ask      = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(g_bid <= 0 || g_ask <= 0) return false;
   g_spread   = g_ask - g_bid;
   g_point    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   g_tickValue= SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   g_minLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   g_maxLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   g_lotStep  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   g_digits   = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_stopsLevelPts  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   g_freezeLevelPts = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);

   if(g_point <= 0) g_point = 0.0001;
   if(g_tickSize <= 0) g_tickSize = g_point;
   if(g_tickValue <= 0) g_tickValue = 1.0;
   if(g_minLot <= 0) g_minLot = 0.01;
   if(g_lotStep <= 0) g_lotStep = g_minLot;
   if(g_maxLot < g_minLot) g_maxLot = g_minLot;
   return true;
}

double MinStopDistance()
{
   g_stopsLevelPts  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   g_freezeLevelPts = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   return MathMax(g_stopsLevelPts, g_freezeLevelPts + 1) * g_point;
}

double NormalizeVolume(double vol)
{
   if(vol <= 0) return 0.0;
   double n = MathFloor((vol + 1e-10) / g_lotStep) * g_lotStep;
   n = MathMax(g_minLot, MathMin(g_maxLot, n));
   int lotDigits = (g_lotStep >= 1.0) ? 0 : (int)MathRound(-MathLog10(g_lotStep));
   lotDigits = MathMax(0, MathMin(8, lotDigits));
   return NormalizeDouble(n, lotDigits);
}

bool SessionOK(const MqlDateTime &dt)
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

double BaseRiskPct()
{
   switch(InpRiskLevel)
   {
      case RISK_CONSERVATIVE: return 0.45;
      case RISK_MODERATE:     return 0.90;
      case RISK_AGGRESSIVE:   return 1.50;
   }
   return 0.90;
}

double CalcLotsByRisk(bool isBuy, double slDist, double confidence)
{
   if(InpFixedLot > 0.0) return NormalizeVolume(InpFixedLot);
   if(slDist <= 0 || g_tickSize <= 0) return g_minLot;

   double riskPct = BaseRiskPct() * (0.60 + confidence * 0.80);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = equity * riskPct / 100.0;
   if(riskAmount <= 0) return g_minLot;

   double priceOpen = isBuy ? g_ask : g_bid;
   double priceSL   = isBuy ? (priceOpen - slDist) : (priceOpen + slDist);
   double oneLotLoss = 0.0;
   bool calcOk = OrderCalcProfit(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, 1.0, priceOpen, priceSL, oneLotLoss);
   oneLotLoss = MathAbs(oneLotLoss);
   if(!calcOk || oneLotLoss <= 0.0)
   {
      double ticks = slDist / g_tickSize;
      oneLotLoss = ticks * g_tickValue;
   }
   if(oneLotLoss <= 0.0) return g_minLot;

   double lots = riskAmount / oneLotLoss;
   return NormalizeVolume(lots);
}

bool DirectionAllowedBySymbol(bool isBuy)
{
   long mode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(mode == SYMBOL_TRADE_MODE_DISABLED || mode == SYMBOL_TRADE_MODE_CLOSEONLY) return false;
   if(isBuy && mode == SYMBOL_TRADE_MODE_SHORTONLY) return false;
   if(!isBuy && mode == SYMBOL_TRADE_MODE_LONGONLY) return false;
   return true;
}

void CountPositions()
{
   g_totalOpen = 0;
   g_buyOpen = 0;
   g_sellOpen = 0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != InpMagicNumber) continue;
      g_totalOpen++;
      if(posInfo.PositionType() == POSITION_TYPE_BUY) g_buyOpen++;
      else if(posInfo.PositionType() == POSITION_TYPE_SELL) g_sellOpen++;
   }
}

bool HasDirectionOpen(bool isBuy)
{
   return isBuy ? (g_buyOpen > 0) : (g_sellOpen > 0);
}

ulong FindNewestPositionTicket(const string commentHint)
{
   ulong bestTicket = 0;
   datetime bestTime = 0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != InpMagicNumber) continue;
      if(commentHint != "" && StringFind(posInfo.Comment(), commentHint) < 0) continue;
      if(posInfo.Time() >= bestTime)
      {
         bestTime = posInfo.Time();
         bestTicket = posInfo.Ticket();
      }
   }
   return bestTicket;
}

bool LoadIndicatorData()
{
   if(Bars(_Symbol, InpSignalTF) < MathMax(InpBreakoutLookback + 5, InpEMATrend + 5)) return false;

   if(!GetBufVal(hATR, 0, 1, g_atr1)) return false;
   if(!GetBufVal(hATRFast, 0, 1, g_atrFast1)) return false;
   if(!GetBufVal(hATRSlow, 0, 1, g_atrSlow1)) return false;

   if(!GetBufVal(hEMAFast, 0, 1, g_emaFast1)) return false;
   if(!GetBufVal(hEMAFast, 0, 2, g_emaFast2)) return false;
   if(!GetBufVal(hEMASlow, 0, 1, g_emaSlow1)) return false;
   if(!GetBufVal(hEMASlow, 0, 2, g_emaSlow2)) return false;
   if(!GetBufVal(hEMATrend,0, 1, g_emaTrend1)) return false;

   if(!GetBufVal(hRSI, 0, 1, g_rsi1)) return false;
   if(!GetBufVal(hRSI, 0, 2, g_rsi2)) return false;

   if(!GetBufVal(hBB, 0, 1, g_bbMid1)) return false;
   if(!GetBufVal(hBB, 1, 1, g_bbUp1)) return false;
   if(!GetBufVal(hBB, 2, 1, g_bbLow1)) return false;

   if(!GetBufVal(hADX, 0, 1, g_adx1)) return false;
   if(!GetBufVal(hADX, 1, 1, g_diPlus1)) return false;
   if(!GetBufVal(hADX, 2, 1, g_diMinus1)) return false;

   if(!GetBufVal(hMACD, 0, 1, g_macdMain1)) return false;
   if(!GetBufVal(hMACD, 0, 2, g_macdMain2)) return false;
   if(!GetBufVal(hMACD, 1, 1, g_macdSig1)) return false;
   if(!GetBufVal(hMACD, 1, 2, g_macdSig2)) return false;

   g_close1 = iClose(_Symbol, InpSignalTF, 1);
   g_close2 = iClose(_Symbol, InpSignalTF, 2);
   if(g_close1 <= 0 || g_close2 <= 0) return false;
   return true;
}

double ScoreTrend()
{
   double s = 0.0;
   s += (g_emaFast1 > g_emaSlow1) ? 18.0 : -18.0;
   s += (g_emaFast1 > g_emaTrend1) ? 12.0 : -12.0;
   s += (g_emaFast1 > g_emaFast2) ? 8.0 : -8.0;
   s += (g_close1 > g_emaFast1) ? 5.0 : -5.0;
   if(g_adx1 >= InpADXTrendMin) s += (g_diPlus1 > g_diMinus1) ? 12.0 : -12.0;
   return s;
}

double ScoreMeanReversion()
{
   double s = 0.0;
   if(g_close1 <= g_bbLow1 && g_rsi1 <= InpRSIOversold) s += 28.0;
   if(g_close1 >= g_bbUp1  && g_rsi1 >= InpRSIOverbought) s -= 28.0;
   if(g_close2 < g_bbLow1 && g_close1 > g_close2 && g_rsi1 > g_rsi2) s += 10.0;
   if(g_close2 > g_bbUp1  && g_close1 < g_close2 && g_rsi1 < g_rsi2) s -= 10.0;
   return s;
}

double ScoreBreakout()
{
   double s = 0.0;
   int lb = MathMax(10, InpBreakoutLookback);
   double hi[], lo[];
   ArraySetAsSeries(hi, true);
   ArraySetAsSeries(lo, true);
   if(CopyHigh(_Symbol, InpSignalTF, 2, lb, hi) < lb) return 0.0;
   if(CopyLow(_Symbol, InpSignalTF, 2, lb, lo) < lb) return 0.0;

   double hh = hi[0], ll = lo[0];
   for(int i = 1; i < lb; i++)
   {
      if(hi[i] > hh) hh = hi[i];
      if(lo[i] < ll) ll = lo[i];
   }

   if(g_close1 > hh) s += 35.0;
   if(g_close1 < ll) s -= 35.0;
   if(g_close2 <= hh && g_close1 > hh) s += 8.0;
   if(g_close2 >= ll && g_close1 < ll) s -= 8.0;
   return s;
}

double ScoreMomentum()
{
   double s = 0.0;
   double h1 = g_macdMain1 - g_macdSig1;
   double h2 = g_macdMain2 - g_macdSig2;

   if(g_rsi1 > 55.0) s += 10.0;
   else if(g_rsi1 < 45.0) s -= 10.0;

   if(h1 > 0.0 && h1 > h2) s += 15.0;
   if(h1 < 0.0 && h1 < h2) s -= 15.0;

   s += (g_close1 > g_close2) ? 5.0 : -5.0;
   return s;
}

double ScoreVolatility()
{
   if(g_atrSlow1 <= 0) return 0.0;
   double ratio = g_atrFast1 / g_atrSlow1;
   double s = 0.0;

   if(ratio > 1.20)
   {
      s += (g_close1 > g_emaFast1) ? 10.0 : -10.0;
   }
   else if(ratio < 0.80)
   {
      if(g_close1 < g_bbLow1) s += 8.0;
      if(g_close1 > g_bbUp1)  s -= 8.0;
   }
   return s;
}

double CompositeScore()
{
   double score = 0.0;
   if(InpEnableTrend)         score += ScoreTrend();
   if(InpEnableMeanReversion) score += ScoreMeanReversion();
   if(InpEnableBreakout)      score += ScoreBreakout();
   if(InpEnableMomentum)      score += ScoreMomentum();
   if(InpEnableVolatility)    score += ScoreVolatility();
   return score;
}

double AdaptiveThreshold()
{
   double decayBlocks = (double)g_barsSinceTrade / (double)MathMax(1, InpThresholdDecayBars);
   double threshold = InpEntryScoreBase - decayBlocks * InpThresholdDecayStep;
   if(threshold < InpEntryScoreMin) threshold = InpEntryScoreMin;
   return threshold;
}

bool BuildStops(bool isBuy, double &sl, double &tp, double &slDist)
{
   if(g_atr1 <= 0) return false;
   double price = isBuy ? g_ask : g_bid;
   double minDist = MinStopDistance();
   slDist = MathMax(g_atr1 * InpSL_ATR_Mult, minDist * 1.2);
   double tpDist = slDist * InpTP_RR;

   sl = isBuy ? (price - slDist) : (price + slDist);
   tp = isBuy ? (price + tpDist) : (price - tpDist);

   if(isBuy)
   {
      if((price - sl) < minDist) sl = price - minDist;
      if((tp - price) < minDist) tp = price + minDist;
   }
   else
   {
      if((sl - price) < minDist) sl = price + minDist;
      if((price - tp) < minDist) tp = price - minDist;
   }

   sl = NormalizeDouble(sl, g_digits);
   tp = NormalizeDouble(tp, g_digits);
   slDist = MathAbs(price - sl);
   return (sl > 0 && tp > 0 && slDist > 0);
}

bool SendOrder(bool isBuy, double lots, double sl, double tp, const string comment)
{
   lots = NormalizeVolume(lots);
   if(lots <= 0) return false;
   
   // Use numeric retcodes for maximum MT5 build compatibility.
   const uint RC_REQUOTE       = 10004;
   const uint RC_INVALID_PRICE = 10015;
   const uint RC_INVALID_STOPS = 10016;
   const uint RC_PRICE_CHANGED = 10020;
   const uint RC_PRICE_OFF     = 10021;
   const uint RC_INVALID_FILL  = 10030;

   bool ok = isBuy ? trade.Buy(lots, _Symbol, 0.0, sl, tp, comment)
                   : trade.Sell(lots, _Symbol, 0.0, sl, tp, comment);
   if(ok)
   {
      if(InpLogTrades) PrintFormat("OPEN %s lots=%.2f sl=%.2f tp=%.2f", comment, lots, sl, tp);
      return true;
   }

   uint rc = (uint)trade.ResultRetcode();
   if(InpDebugMode)
      PrintFormat("ENTRY FAIL %s rc=%u %s | bid=%.2f ask=%.2f stops=%d freeze=%d",
                  comment, rc, trade.ResultRetcodeDescription(), g_bid, g_ask, g_stopsLevelPts, g_freezeLevelPts);

   if(rc == RC_INVALID_FILL)
   {
      ENUM_ORDER_TYPE_FILLING fills[3] = {ORDER_FILLING_FOK, ORDER_FILLING_IOC, ORDER_FILLING_RETURN};
      for(int i = 0; i < 3; i++)
      {
         trade.SetTypeFilling(fills[i]);
         ok = isBuy ? trade.Buy(lots, _Symbol, 0.0, sl, tp, comment)
                    : trade.Sell(lots, _Symbol, 0.0, sl, tp, comment);
         if(ok)
         {
            trade.SetTypeFillingBySymbol(_Symbol);
            if(InpLogTrades) PrintFormat("OPEN RETRY(fill=%d) %s lots=%.2f", (int)fills[i], comment, lots);
            return true;
         }
      }
      trade.SetTypeFillingBySymbol(_Symbol);
   }

   if(rc == RC_INVALID_STOPS ||
      rc == RC_REQUOTE ||
      rc == RC_PRICE_OFF ||
      rc == RC_PRICE_CHANGED ||
      rc == RC_INVALID_PRICE)
   {
      ok = isBuy ? trade.Buy(lots, _Symbol, 0.0, 0.0, 0.0, comment)
                 : trade.Sell(lots, _Symbol, 0.0, 0.0, 0.0, comment);
      if(ok)
      {
         ulong tk = FindNewestPositionTicket(comment);
         if(tk > 0) trade.PositionModify(tk, sl, tp); // best effort
         if(InpLogTrades) PrintFormat("OPEN FALLBACK %s lots=%.2f", comment, lots);
         return true;
      }
   }

   return false;
}

bool OpenTradeBySignal(int direction, double score, bool forced)
{
   if(direction == 0) return false;
   bool isBuy = (direction > 0);
   if(isBuy && !InpAllowBuy) return false;
   if(!isBuy && !InpAllowSell) return false;
   if(!DirectionAllowedBySymbol(isBuy)) return false;

   CountPositions();
   if(g_totalOpen >= InpMaxOpenPositions) return false;
   if(InpOnePositionPerDirection && HasDirectionOpen(isBuy)) return false;
   if((int)(TimeCurrent() - g_lastEntryTime) < InpMinSecondsBetweenEntries) return false;

   double sl = 0.0, tp = 0.0, slDist = 0.0;
   if(!BuildStops(isBuy, sl, tp, slDist)) return false;

   double confidence = MathMin(1.0, MathAbs(score) / 100.0);
   if(forced) confidence = MathMax(confidence, 0.45);

   double lots = CalcLotsByRisk(isBuy, slDist, confidence);
   if(lots < g_minLot) return false;

   string tag = forced ? "FORCED" : "SCORE";
   string cmt = InpTradeComment + "_" + (isBuy ? "BUY_" : "SELL_") + tag;
   if(SendOrder(isBuy, lots, sl, tp, cmt))
   {
      g_lastEntryTime = TimeCurrent();
      g_barsSinceTrade = 0;
      return true;
   }
   return false;
}

void CloseAllEA(const string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != InpMagicNumber) continue;
      trade.PositionClose(posInfo.Ticket());
   }
   if(InpDebugMode) Print("ALL POSITIONS CLOSED: ", reason);
}

void ManagePositions()
{
   if(!RefreshSymbolMeta()) return;
   double atr = g_atr1;
   if(atr <= 0) GetBufVal(hATR, 0, 1, atr);
   if(atr <= 0) return;

   double minDist = MinStopDistance();
   int secPerBar = MathMax(1, PeriodSeconds(InpSignalTF));

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != InpMagicNumber) continue;

      ulong ticket = posInfo.Ticket();
      bool isBuy = (posInfo.PositionType() == POSITION_TYPE_BUY);
      double openPrice = posInfo.PriceOpen();
      double sl = posInfo.StopLoss();
      double tp = posInfo.TakeProfit();

      // Time-based exit to keep system rotating
      if(InpMaxHoldBars > 0)
      {
         int heldBars = (int)((TimeCurrent() - posInfo.Time()) / secPerBar);
         if(heldBars >= InpMaxHoldBars)
         {
            trade.PositionClose(ticket);
            continue;
         }
      }

      if(isBuy)
      {
         double move = g_bid - openPrice;
         if(move >= atr * InpBreakEvenATR)
         {
            double be = NormalizeDouble(openPrice + g_spread * 0.2, g_digits);
            if((sl <= 0 || be > sl) && (g_bid - be) > minDist) trade.PositionModify(ticket, be, tp);
         }
         if(move > atr)
         {
            double trail = NormalizeDouble(g_bid - atr * InpTrailATR_Mult, g_digits);
            if(trail > openPrice && (sl <= 0 || trail > sl) && (g_bid - trail) > minDist)
               trade.PositionModify(ticket, trail, tp);
         }
      }
      else
      {
         double move = openPrice - g_ask;
         if(move >= atr * InpBreakEvenATR)
         {
            double be = NormalizeDouble(openPrice - g_spread * 0.2, g_digits);
            if((sl <= 0 || be < sl) && (be - g_ask) > minDist) trade.PositionModify(ticket, be, tp);
         }
         if(move > atr)
         {
            double trail = NormalizeDouble(g_ask + atr * InpTrailATR_Mult, g_digits);
            if(trail < openPrice && (sl <= 0 || trail < sl) && (trail - g_ask) > minDist)
               trade.PositionModify(ticket, trail, tp);
         }
      }
   }
}

void UpdateRiskState(bool &allowEntries, double &ddTotal, double &ddDaily)
{
   allowEntries = true;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > g_peakEquity) g_peakEquity = equity;
   if(g_peakEquity <= 0.0) g_peakEquity = equity;
   if(g_dayStartEquity <= 0.0) g_dayStartEquity = equity;

   ddTotal = (g_peakEquity > 0.0) ? ((g_peakEquity - equity) / g_peakEquity) * 100.0 : 0.0;
   ddDaily = (g_dayStartEquity > 0.0) ? ((g_dayStartEquity - equity) / g_dayStartEquity) * 100.0 : 0.0;

   if(ddTotal >= InpMaxTotalDrawdown)
   {
      allowEntries = false;
      if(!g_killSwitch)
      {
         g_killSwitch = true;
         CloseAllEA("TOTAL DD KILL SWITCH");
      }
      return;
   }

   if(ddDaily >= InpMaxDailyDrawdown) allowEntries = false;
}

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("===========================================");
   Print(" GS QUANT ARCHITECT v4.01 - REBUILT INIT");
   Print("===========================================");

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpMaxSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(!RefreshSymbolMeta())
   {
      Print("INIT FAILED: no valid market prices/symbol meta.");
      return INIT_FAILED;
   }

   hATR      = iATR(_Symbol, InpSignalTF, InpATRPeriod);
   hATRFast  = iATR(_Symbol, InpSignalTF, InpATRFastPeriod);
   hATRSlow  = iATR(_Symbol, InpSignalTF, InpATRSlowPeriod);
   hEMAFast  = iMA(_Symbol, InpSignalTF, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   hEMASlow  = iMA(_Symbol, InpSignalTF, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   hEMATrend = iMA(_Symbol, InpSignalTF, InpEMATrend, 0, MODE_EMA, PRICE_CLOSE);
   hRSI      = iRSI(_Symbol, InpSignalTF, InpRSIPeriod, PRICE_CLOSE);
   hBB       = iBands(_Symbol, InpSignalTF, InpBBPeriod, 0, InpBBDev, PRICE_CLOSE);
   hADX      = iADX(_Symbol, InpSignalTF, InpADXPeriod);
   hMACD     = iMACD(_Symbol, InpSignalTF, 12, 26, 9, PRICE_CLOSE);

   if(hATR == INVALID_HANDLE || hATRFast == INVALID_HANDLE || hATRSlow == INVALID_HANDLE ||
      hEMAFast == INVALID_HANDLE || hEMASlow == INVALID_HANDLE || hEMATrend == INVALID_HANDLE ||
      hRSI == INVALID_HANDLE || hBB == INVALID_HANDLE || hADX == INVALID_HANDLE || hMACD == INVALID_HANDLE)
   {
      Print("INIT FAILED: indicator handle creation failed.");
      return INIT_FAILED;
   }

   g_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayStartEquity = g_peakEquity;
   g_prevDay = -1;
   g_warmupCount = 0;
   g_ready = false;
   g_killSwitch = false;
   g_barsSinceTrade = 0;
   g_lastEntryTime = 0;
   g_lastSignalBar = 0;
   g_lastWarmupBar = 0;

   PrintFormat("Symbol=%s Digits=%d MinLot=%.2f Step=%.2f Stops=%d Freeze=%d",
               _Symbol, g_digits, g_minLot, g_lotStep, g_stopsLevelPts, g_freezeLevelPts);
   Print("INIT OK");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hATR != INVALID_HANDLE)      IndicatorRelease(hATR);
   if(hATRFast != INVALID_HANDLE)  IndicatorRelease(hATRFast);
   if(hATRSlow != INVALID_HANDLE)  IndicatorRelease(hATRSlow);
   if(hEMAFast != INVALID_HANDLE)  IndicatorRelease(hEMAFast);
   if(hEMASlow != INVALID_HANDLE)  IndicatorRelease(hEMASlow);
   if(hEMATrend != INVALID_HANDLE) IndicatorRelease(hEMATrend);
   if(hRSI != INVALID_HANDLE)      IndicatorRelease(hRSI);
   if(hBB != INVALID_HANDLE)       IndicatorRelease(hBB);
   if(hADX != INVALID_HANDLE)      IndicatorRelease(hADX);
   if(hMACD != INVALID_HANDLE)     IndicatorRelease(hMACD);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!RefreshSymbolMeta()) return;

   // Track day changes
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day != g_prevDay)
   {
      g_prevDay = dt.day;
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   }

   // Always manage existing positions
   ManagePositions();

   // Evaluate new entries only once per signal TF bar
   if(!IsNewBarTF(InpSignalTF, g_lastSignalBar)) return;

   bool allowEntries = true;
   double ddTotal = 0.0, ddDaily = 0.0;
   UpdateRiskState(allowEntries, ddTotal, ddDaily);
   if(g_killSwitch) return;

   if(!g_ready)
   {
      if(IsNewBarTF(InpSignalTF, g_lastWarmupBar)) g_warmupCount++;
      if(g_warmupCount >= InpWarmupBars)
      {
         g_ready = true;
         PrintFormat("WARMUP COMPLETE (%d bars). Trading enabled.", g_warmupCount);
      }
      return;
   }

   g_barsSinceTrade++;
   CountPositions();

   if(!allowEntries)
   {
      if(InpDebugMode) PrintFormat("ENTRY BLOCKED BY DD | daily=%.2f total=%.2f", ddDaily, ddTotal);
      return;
   }

   if(InpSpreadFilterPoints > 0.0)
   {
      double spreadPts = g_spread / g_point;
      if(spreadPts > InpSpreadFilterPoints)
      {
         if(InpDebugMode) PrintFormat("ENTRY BLOCKED BY SPREAD | spread=%.1f pts", spreadPts);
         return;
      }
   }

   if(!SessionOK(dt)) return;
   if(InpNoTradeFriday && dt.day_of_week == 5 && dt.hour >= 18) return;

   if(!LoadIndicatorData())
   {
      if(InpDebugMode) Print("Indicator data not ready; skipping bar.");
      return;
   }

   double score = CompositeScore();
   double threshold = AdaptiveThreshold();

   int direction = 0;
   bool forced = false;
   if(MathAbs(score) >= threshold)
      direction = (score > 0.0) ? 1 : -1;
   else if(InpGuaranteeActivity && g_barsSinceTrade >= InpForceTradeBars && g_totalOpen == 0)
   {
      direction = (g_emaFast1 >= g_emaSlow1) ? 1 : -1;
      forced = true;
   }

   if(InpDebugMode)
   {
      PrintFormat("BAR | score=%.1f thr=%.1f noTradeBars=%d open=%d atr=%.2f rsi=%.1f dir=%d forced=%s",
                  score, threshold, g_barsSinceTrade, g_totalOpen, g_atr1, g_rsi1, direction, forced ? "Y" : "N");
   }

   if(direction != 0) OpenTradeBySignal(direction, score, forced);
}

//+------------------------------------------------------------------+
//| Optional tester metric                                            |
//+------------------------------------------------------------------+
double OnTester()
{
   double trades = TesterStatistics(STAT_TRADES);
   double profit = TesterStatistics(STAT_PROFIT);
   double pf = TesterStatistics(STAT_PROFIT_FACTOR);
   double dd = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   if(profit <= 0.0) return 0.0;
   if(trades < InpOptMinTrades) return 0.0;
   if(pf < InpOptMinProfitFactor) return 0.0;

   // PF-first objective once floors are met.
   // Higher PF dominates, then lower DD and enough sample size.
   double pfEdge = pf - InpOptMinProfitFactor;
   return (pfEdge * 1000.0) + (pf * 100.0) - (dd * 5.0) + MathSqrt(trades);
}
//+------------------------------------------------------------------+
