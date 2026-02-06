//+------------------------------------------------------------------+
//| XAUUSD_DualStrategy_EA.mq5                                       |
//| Adapted from scalping transcript (imbalance + mean reversion).   |
//| Strategy 1: Imbalance momentum (NY session).                     |
//| Strategy 2: Mean reversion (London session).                     |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"

#include <Trade/Trade.mqh>

enum StrategyMode
  {
   STRATEGY_IMBALANCE = 0,
   STRATEGY_MEAN_REVERSION = 1
  };

input StrategyMode   InpStrategy              = STRATEGY_IMBALANCE;
input ENUM_TIMEFRAMES InpTimeframe           = PERIOD_M5;

input bool           InpUseSymbolFilter       = true;
input string         InpSymbolMatch           = "XAU";

input bool           InpUseSessionFilter      = true;
input int            InpNYStartHour           = 13;
input int            InpNYStartMinute         = 30;
input int            InpNYEndHour             = 20;
input int            InpNYEndMinute           = 0;
input int            InpLondonStartHour       = 7;
input int            InpLondonStartMinute     = 0;
input int            InpLondonEndHour         = 10;
input int            InpLondonEndMinute       = 30;

input bool           InpUseRiskPercent        = true;
input double         InpRiskPercent           = 0.5;
input double         InpFixedLots             = 0.10;
input double         InpMaxSpreadPoints       = 40.0;

input int            InpATRPeriod             = 14;
input double         InpStopLossATR           = 1.0;
input int            InpBalanceLookback       = 30;
input int            InpVolumeLookback        = 20;
input double         InpVolumeMultiplier      = 1.5;

input double         InpBreakoutBufferATR     = 0.20;
input double         InpAggressiveBodyATR     = 0.80;
input bool           InpUseTrendFilter        = true;
input int            InpTrendEMAPeriod        = 50;
input double         InpImbalanceTPRR         = 2.0;

input double         InpDeviationATR          = 1.0;
input bool           InpMeanReversionTPToMid  = true;
input double         InpMeanReversionTPRR     = 1.5;

input bool           InpUseBreakEven          = true;
input double         InpBreakEvenRR           = 0.5;
input double         InpBreakEvenOffsetPoints = 5.0;

CTrade trade;

static datetime g_lastBarTime = 0;
static int g_atrHandle = INVALID_HANDLE;
static int g_emaHandle = INVALID_HANDLE;

int OnInit()
  {
   g_atrHandle = iATR(_Symbol, InpTimeframe, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
      return INIT_FAILED;
   g_emaHandle = iMA(_Symbol, InpTimeframe, InpTrendEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(g_emaHandle == INVALID_HANDLE)
      return INIT_FAILED;
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   if(g_emaHandle != INVALID_HANDLE)
      IndicatorRelease(g_emaHandle);
  }

bool IsNewBar()
  {
   datetime barTime = iTime(_Symbol, InpTimeframe, 0);
   if(barTime == 0)
      return false;
   if(barTime != g_lastBarTime)
     {
      g_lastBarTime = barTime;
      return true;
     }
   return false;
  }

bool IsWithinSession(datetime t, int startH, int startM, int endH, int endM)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   int current = dt.hour * 60 + dt.min;
   int start = startH * 60 + startM;
   int end = endH * 60 + endM;
   if(start == end)
      return true;
   if(start < end)
      return (current >= start && current <= end);
   return (current >= start || current <= end);
  }

bool IsSessionAllowed()
  {
   if(!InpUseSessionFilter)
      return true;
   datetime now = TimeCurrent();
   if(InpStrategy == STRATEGY_IMBALANCE)
      return IsWithinSession(now, InpNYStartHour, InpNYStartMinute, InpNYEndHour, InpNYEndMinute);
   return IsWithinSession(now, InpLondonStartHour, InpLondonStartMinute, InpLondonEndHour, InpLondonEndMinute);
  }

bool IsSpreadOK()
  {
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0)
      return false;
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / point;
   return (spread <= InpMaxSpreadPoints);
  }

double GetATR()
  {
   if(g_atrHandle == INVALID_HANDLE)
      return 0.0;
   double buffer[];
   if(CopyBuffer(g_atrHandle, 0, 1, 1, buffer) != 1)
      return 0.0;
   return buffer[0];
  }

double GetEMA()
  {
   if(g_emaHandle == INVALID_HANDLE)
      return 0.0;
   double buffer[];
   if(CopyBuffer(g_emaHandle, 0, 1, 1, buffer) != 1)
      return 0.0;
   return buffer[0];
  }

double GetAverageVolume(int lookback)
  {
   if(lookback <= 0)
      return 0.0;
   long volumes[];
   int copied = CopyTickVolume(_Symbol, InpTimeframe, 1, lookback, volumes);
   if(copied <= 0)
      return 0.0;
   double sum = 0.0;
   for(int i = 0; i < copied; i++)
      sum += (double)volumes[i];
   return sum / copied;
  }

bool GetBalanceRange(int lookback, double &high, double &low, double &mid)
  {
   if(lookback <= 0)
      return false;
   double highs[];
   double lows[];
   int copiedHigh = CopyHigh(_Symbol, InpTimeframe, 1, lookback, highs);
   int copiedLow = CopyLow(_Symbol, InpTimeframe, 1, lookback, lows);
   if(copiedHigh <= 0 || copiedLow <= 0)
      return false;
   int idxHigh = ArrayMaximum(highs, 0, copiedHigh);
   int idxLow = ArrayMinimum(lows, 0, copiedLow);
   high = highs[idxHigh];
   low = lows[idxLow];
   mid = (high + low) / 2.0;
   return true;
  }

double NormalizeLots(double lots)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0)
      step = 0.01;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   lots = MathFloor(lots / step) * step;
   if(lots < minLot)
      lots = minLot;
   return lots;
  }

double CalculateLots(double stopDistance)
  {
   if(!InpUseRiskPercent)
      return NormalizeLots(InpFixedLots);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0.0 || stopDistance <= 0.0)
      return NormalizeLots(InpFixedLots);
   double riskMoney = balance * (InpRiskPercent / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0)
      return NormalizeLots(InpFixedLots);
   double valuePerPrice = tickValue / tickSize;
   double costPerLot = stopDistance * valuePerPrice;
   if(costPerLot <= 0.0)
      return NormalizeLots(InpFixedLots);
   double lots = riskMoney / costPerLot;
   return NormalizeLots(lots);
  }

void ManageBreakEven()
  {
   if(!InpUseBreakEven)
      return;
   if(!PositionSelect(_Symbol))
      return;
   long type = PositionGetInteger(POSITION_TYPE);
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);
   if(sl <= 0.0 || entry <= 0.0)
      return;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double current = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double risk = (type == POSITION_TYPE_BUY) ? (entry - sl) : (sl - entry);
   if(risk <= 0.0)
      return;
   double move = (type == POSITION_TYPE_BUY) ? (current - entry) : (entry - current);
   if(move < risk * InpBreakEvenRR)
      return;
   double offset = InpBreakEvenOffsetPoints * point;
   double newSL = (type == POSITION_TYPE_BUY) ? (entry + offset) : (entry - offset);
   if(type == POSITION_TYPE_BUY && newSL > sl)
      trade.PositionModify(_Symbol, newSL, tp);
   if(type == POSITION_TYPE_SELL && newSL < sl)
      trade.PositionModify(_Symbol, newSL, tp);
  }

bool CanTrade()
  {
   if(InpUseSymbolFilter && StringFind(_Symbol, InpSymbolMatch) < 0)
      return false;
   if(!IsSessionAllowed())
      return false;
   if(!IsSpreadOK())
      return false;
   if(PositionSelect(_Symbol))
      return false;
   return true;
  }

void EnterTrade(bool isBuy, double sl, double tp, string reason)
  {
   double price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopDistance = MathAbs(price - sl);
   double lots = CalculateLots(stopDistance);
   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minStop = stopsLevel * point;
   if(stopDistance < minStop)
     {
      if(isBuy)
         sl = price - minStop;
      else
         sl = price + minStop;
     }
   if(isBuy)
      trade.Buy(lots, _Symbol, 0.0, sl, tp, reason);
   else
      trade.Sell(lots, _Symbol, 0.0, sl, tp, reason);
  }

void CheckImbalance()
  {
   if(!CanTrade())
      return;
   double atr = GetATR();
   if(atr <= 0.0)
      return;
   double balanceHigh, balanceLow, balanceMid;
   if(!GetBalanceRange(InpBalanceLookback, balanceHigh, balanceLow, balanceMid))
      return;
   MqlRates rates[2];
   if(CopyRates(_Symbol, InpTimeframe, 1, 2, rates) < 2)
      return;
   double body = MathAbs(rates[0].close - rates[0].open);
   bool aggressive = (body >= atr * InpAggressiveBodyATR);
   double avgVol = GetAverageVolume(InpVolumeLookback);
   bool volumeOk = (avgVol > 0.0 && rates[0].tick_volume >= avgVol * InpVolumeMultiplier);
   if(!aggressive || !volumeOk)
      return;
   double buffer = atr * InpBreakoutBufferATR;
   double ema = GetEMA();
   if(InpUseTrendFilter && ema <= 0.0)
      return;
   bool aboveEMA = (rates[0].close > ema);
   bool belowEMA = (rates[0].close < ema);

   if(rates[0].close > balanceHigh + buffer)
     {
      if(InpUseTrendFilter && !aboveEMA)
         return;
      double sl = rates[0].low - atr * InpStopLossATR;
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(sl >= entry)
         sl = entry - atr * InpStopLossATR;
      double tp = entry + (entry - sl) * InpImbalanceTPRR;
      EnterTrade(true, sl, tp, "Imbalance buy");
     }
   else if(rates[0].close < balanceLow - buffer)
     {
      if(InpUseTrendFilter && !belowEMA)
         return;
      double sl = rates[0].high + atr * InpStopLossATR;
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(sl <= entry)
         sl = entry + atr * InpStopLossATR;
      double tp = entry - (sl - entry) * InpImbalanceTPRR;
      EnterTrade(false, sl, tp, "Imbalance sell");
     }
  }

void CheckMeanReversion()
  {
   if(!CanTrade())
      return;
   double atr = GetATR();
   if(atr <= 0.0)
      return;
   double balanceHigh, balanceLow, balanceMid;
   if(!GetBalanceRange(InpBalanceLookback, balanceHigh, balanceLow, balanceMid))
      return;
   MqlRates rates[3];
   if(CopyRates(_Symbol, InpTimeframe, 1, 3, rates) < 3)
      return;
   double avgVol = GetAverageVolume(InpVolumeLookback);
   bool volumeOk = (avgVol > 0.0 && rates[0].tick_volume >= avgVol * InpVolumeMultiplier);
   if(!volumeOk)
      return;

   double deviation = atr * InpDeviationATR;
   bool breakoutDown = (rates[1].close < balanceLow - deviation);
   bool breakoutUp = (rates[1].close > balanceHigh + deviation);
   bool reentry = (rates[0].close > balanceLow && rates[0].close < balanceHigh);

   if(breakoutDown && reentry)
     {
      double sl = MathMin(rates[0].low, rates[1].low) - atr * InpStopLossATR;
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(sl >= entry)
         sl = entry - atr * InpStopLossATR;
      double tp = entry + (entry - sl) * InpMeanReversionTPRR;
      if(InpMeanReversionTPToMid && balanceMid > entry)
         tp = balanceMid;
      EnterTrade(true, sl, tp, "Mean reversion buy");
     }
   else if(breakoutUp && reentry)
     {
      double sl = MathMax(rates[0].high, rates[1].high) + atr * InpStopLossATR;
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(sl <= entry)
         sl = entry + atr * InpStopLossATR;
      double tp = entry - (sl - entry) * InpMeanReversionTPRR;
      if(InpMeanReversionTPToMid && balanceMid < entry)
         tp = balanceMid;
      EnterTrade(false, sl, tp, "Mean reversion sell");
     }
  }

void OnTick()
  {
   ManageBreakEven();
   if(!IsNewBar())
      return;
   if(InpStrategy == STRATEGY_IMBALANCE)
      CheckImbalance();
   else
      CheckMeanReversion();
  }
