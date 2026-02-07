//+------------------------------------------------------------------+
//| ICC Trading Strategy Expert Advisor (MT5)                        |
//| Strategy: Indication -> Correction -> Continuation               |
//| Author: OpenAI (ChatGPT)                                         |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"

#include <Trade/Trade.mqh>

//--- Inputs: Timeframes
input ENUM_TIMEFRAMES BiasTimeframe           = PERIOD_H1;
input ENUM_TIMEFRAMES HigherTimeframe         = PERIOD_H4;
input bool            UseHigherTimeframeFilter= false;
input ENUM_TIMEFRAMES EntryTimeframe          = PERIOD_M15;

//--- Inputs: Swing detection
input int             SwingLeft               = 2;
input int             SwingRight              = 2;
input int             MaxSwingBars            = 300;

//--- Inputs: Indication/Correction/Continuation
input double          IndicationBufferPoints  = 5;
input double          MinCorrectionPoints     = 100;
input double          EntryBufferPoints       = 2;
input double          StopBufferPoints        = 10;
input bool            UseImpulseFilter        = false;
input double          MinImpulsePoints        = 300;
input bool            UseCorrectionRetraceFilter = false;
input double          MinCorrectionRetracePercent = 30.0;

//--- Inputs: Reaction level (second touch)
input bool            UseSecondTouchFilter    = true;
input double          TouchTolerancePoints    = 20;

//--- Inputs: Session filter (server time)
input bool            UseSessionFilter        = true;
input string          LondonSession           = "07:00-11:00";
input string          NewYorkSession          = "13:00-17:00";
input bool            UseSessionStartDelay    = true;
input int             SessionStartDelayMinutes= 120;
input bool            AvoidFirstMinutes       = true;
input int             AvoidFirstMinutesCount  = 30;

//--- Inputs: Risk management
input bool            UseFixedLot             = false;
input double          FixedLot                = 0.10;
input double          RiskPercent             = 1.0;
input bool            UseRiskReward           = false;
input double          RiskReward              = 2.0;
input int             MaxTradesPerDay         = 1;
input int             SlippagePoints          = 10;

//--- Inputs: Trade management (multi-TP / BE / trailing)
input bool            UseMultiTP              = true;
input double          TP1RiskReward           = 1.0;
input double          TP1ClosePercent         = 50.0;
input bool            UseIndicationAsTP2      = true;
input double          TP2RiskReward           = 3.0;
input bool            MoveSLToBEOnTP1         = true;
input double          BEBufferPoints          = 2;
input bool            UseTrailingAfterTP1     = false;
input double          TrailingStartRR         = 2.0;
input double          TrailingDistancePoints  = 200;
input double          TrailingStepPoints      = 20;

//--- Inputs: Trade identifiers
input ulong           MagicNumber             = 65002;
input string          TradeComment            = "ICC_EA";

//+------------------------------------------------------------------+
//| Internal structures                                               |
//+------------------------------------------------------------------+
struct SwingPoint
{
   double   price;
   datetime time;
   int      index;
   bool     valid;
};

enum ICCState
{
   STATE_IDLE = 0,
   STATE_INDICATED,
   STATE_CORRECTING
};

enum Direction
{
   DIR_NONE = 0,
   DIR_BUY  = 1,
   DIR_SELL = -1
};

struct SessionWindow
{
   int  startMin;
   int  endMin;
   bool valid;
};

//+------------------------------------------------------------------+
//| Global variables                                                  |
//+------------------------------------------------------------------+
CTrade       g_trade;
ICCState     g_state                  = STATE_IDLE;
int          g_direction              = DIR_NONE;
double       g_indicationLevel        = 0.0;
datetime     g_indicationTime         = 0;
datetime     g_indicationSwingTime    = 0;
double       g_invalidationLevel      = 0.0;
double       g_correctionExtreme      = 0.0;
datetime     g_correctionTime         = 0;
double       g_impulseRangePoints     = 0.0;
int          g_touchCount             = 0;
bool         g_touchReady             = true;
int          g_tradesToday            = 0;
int          g_lastTradeDay           = -1;
SessionWindow g_london;
SessionWindow g_newyork;
ulong        g_positionTicket         = 0;
int          g_positionDirection      = DIR_NONE;
double       g_entryPrice             = 0.0;
double       g_initialStop            = 0.0;
double       g_initialRisk            = 0.0;
bool         g_tp1Hit                 = false;

//+------------------------------------------------------------------+
//| Utility: Parse time string "HH:MM"                                |
//+------------------------------------------------------------------+
bool ParseTimeString(const string timeStr, int &minutesOut)
{
   string parts[];
   int count = StringSplit(timeStr, ':', parts);
   if(count != 2)
      return false;

   int hour = (int)StringToInteger(parts[0]);
   int minute = (int)StringToInteger(parts[1]);
   if(hour < 0 || hour > 23 || minute < 0 || minute > 59)
      return false;

   minutesOut = hour * 60 + minute;
   return true;
}

//+------------------------------------------------------------------+
//| Utility: Parse session "HH:MM-HH:MM"                              |
//+------------------------------------------------------------------+
bool ParseSession(const string sessionStr, SessionWindow &session)
{
   int dash = StringFind(sessionStr, "-");
   if(dash <= 0)
      return false;

   string startStr = StringSubstr(sessionStr, 0, dash);
   string endStr = StringSubstr(sessionStr, dash + 1);

   int startMin = 0;
   int endMin = 0;
   if(!ParseTimeString(startStr, startMin))
      return false;
   if(!ParseTimeString(endStr, endMin))
      return false;

   session.startMin = startMin;
   session.endMin = endMin;
   session.valid = true;
   return true;
}

//+------------------------------------------------------------------+
//| Utility: Session check                                            |
//+------------------------------------------------------------------+
bool IsWithinSession(const SessionWindow &session, const int minuteOfDay)
{
   if(!session.valid)
      return false;

   if(session.startMin <= session.endMin)
      return (minuteOfDay >= session.startMin && minuteOfDay <= session.endMin);

   // Session crosses midnight
   return (minuteOfDay >= session.startMin || minuteOfDay <= session.endMin);
}

//+------------------------------------------------------------------+
//| Utility: Allow trading based on session rules                     |
//+------------------------------------------------------------------+
bool IsSessionAllowed()
{
   if(!UseSessionFilter)
      return true;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week == 0 || dt.day_of_week == 6)
      return false;

   int minuteOfDay = dt.hour * 60 + dt.min;
   bool inLondon = IsWithinSession(g_london, minuteOfDay);
   bool inNY = IsWithinSession(g_newyork, minuteOfDay);

   if(!inLondon && !inNY)
      return false;

   if(UseSessionStartDelay)
   {
      if(inLondon && minuteOfDay < g_london.startMin + SessionStartDelayMinutes)
         return false;
      if(inNY && minuteOfDay < g_newyork.startMin + SessionStartDelayMinutes)
         return false;
   }

   if(AvoidFirstMinutes)
   {
      if(inLondon && minuteOfDay < g_london.startMin + AvoidFirstMinutesCount)
         return false;
      if(inNY && minuteOfDay < g_newyork.startMin + AvoidFirstMinutesCount)
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Utility: Copy swing points                                        |
//+------------------------------------------------------------------+
bool GetLastSwings(const ENUM_TIMEFRAMES tf,
                   const int left,
                   const int right,
                   const int maxBars,
                   const bool wantHigh,
                   SwingPoint &latest,
                   SwingPoint &previous)
{
   latest.valid = false;
   previous.valid = false;

   int bars = Bars(_Symbol, tf);
   if(bars <= left + right + 2)
      return false;

   int count = MathMin(maxBars, bars);
   double highs[];
   double lows[];
   datetime times[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   ArraySetAsSeries(times, true);

   if(CopyHigh(_Symbol, tf, 0, count, highs) <= 0)
      return false;
   if(CopyLow(_Symbol, tf, 0, count, lows) <= 0)
      return false;
   if(CopyTime(_Symbol, tf, 0, count, times) <= 0)
      return false;

   int found = 0;
   for(int i = right + 1; i <= count - left - 1 && found < 2; i++)
   {
      bool isSwing = true;
      double pivot = wantHigh ? highs[i] : lows[i];

      for(int j = 1; j <= left && isSwing; j++)
      {
         if(wantHigh && pivot <= highs[i + j])
            isSwing = false;
         if(!wantHigh && pivot >= lows[i + j])
            isSwing = false;
      }

      for(int j = 1; j <= right && isSwing; j++)
      {
         if(wantHigh && pivot <= highs[i - j])
            isSwing = false;
         if(!wantHigh && pivot >= lows[i - j])
            isSwing = false;
      }

      if(isSwing)
      {
         SwingPoint sp;
         sp.price = pivot;
         sp.time = times[i];
         sp.index = i;
         sp.valid = true;

         if(found == 0)
            latest = sp;
         else
            previous = sp;

         found++;
      }
   }

   return (found >= 2);
}

//+------------------------------------------------------------------+
//| Utility: Single swing point                                       |
//+------------------------------------------------------------------+
bool GetLastSwing(const ENUM_TIMEFRAMES tf,
                  const int left,
                  const int right,
                  const int maxBars,
                  const bool wantHigh,
                  SwingPoint &latest)
{
   latest.valid = false;

   int bars = Bars(_Symbol, tf);
   if(bars <= left + right + 2)
      return false;

   int count = MathMin(maxBars, bars);
   double highs[];
   double lows[];
   datetime times[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   ArraySetAsSeries(times, true);

   if(CopyHigh(_Symbol, tf, 0, count, highs) <= 0)
      return false;
   if(CopyLow(_Symbol, tf, 0, count, lows) <= 0)
      return false;
   if(CopyTime(_Symbol, tf, 0, count, times) <= 0)
      return false;

   for(int i = right + 1; i <= count - left - 1; i++)
   {
      bool isSwing = true;
      double pivot = wantHigh ? highs[i] : lows[i];

      for(int j = 1; j <= left && isSwing; j++)
      {
         if(wantHigh && pivot <= highs[i + j])
            isSwing = false;
         if(!wantHigh && pivot >= lows[i + j])
            isSwing = false;
      }

      for(int j = 1; j <= right && isSwing; j++)
      {
         if(wantHigh && pivot <= highs[i - j])
            isSwing = false;
         if(!wantHigh && pivot >= lows[i - j])
            isSwing = false;
      }

      if(isSwing)
      {
         latest.price = pivot;
         latest.time = times[i];
         latest.index = i;
         latest.valid = true;
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Utility: Determine trend direction                                |
//+------------------------------------------------------------------+
int GetTrendDirection(const ENUM_TIMEFRAMES tf)
{
   SwingPoint lastHigh;
   SwingPoint prevHigh;
   SwingPoint lastLow;
   SwingPoint prevLow;

   if(!GetLastSwings(tf, SwingLeft, SwingRight, MaxSwingBars, true, lastHigh, prevHigh))
      return DIR_NONE;
   if(!GetLastSwings(tf, SwingLeft, SwingRight, MaxSwingBars, false, lastLow, prevLow))
      return DIR_NONE;

   if(lastHigh.price > prevHigh.price && lastLow.price > prevLow.price)
      return DIR_BUY;
   if(lastHigh.price < prevHigh.price && lastLow.price < prevLow.price)
      return DIR_SELL;

   return DIR_NONE;
}

//+------------------------------------------------------------------+
//| Utility: Has open position?                                       |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(symbol == _Symbol && magic == (long)MagicNumber)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Utility: Get managed position ticket                              |
//+------------------------------------------------------------------+
bool GetManagedPosition(ulong &ticket)
{
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      if(!PositionSelectByTicket(t))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(symbol == _Symbol && magic == (long)MagicNumber)
      {
         ticket = t;
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Utility: Manage open position (TP1/BE/Trailing)                   |
//+------------------------------------------------------------------+
void ManageOpenPosition()
{
   ulong ticket;
   if(!GetManagedPosition(ticket))
   {
      g_positionTicket = 0;
      return;
   }

   if(!PositionSelectByTicket(ticket))
      return;

   long type = PositionGetInteger(POSITION_TYPE);
   int dir = (type == POSITION_TYPE_BUY) ? DIR_BUY : DIR_SELL;
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);
   double volume = PositionGetDouble(POSITION_VOLUME);

   if(ticket != g_positionTicket)
   {
      g_positionTicket = ticket;
      g_positionDirection = dir;
      g_entryPrice = entry;
      g_initialStop = sl;
      g_initialRisk = MathAbs(entry - sl);
      g_tp1Hit = false;
   }

   if(g_initialRisk <= 0.0 && sl > 0.0)
      g_initialRisk = MathAbs(entry - sl);

   double price = (dir == DIR_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                   : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(UseMultiTP && !g_tp1Hit && g_initialRisk > 0.0)
   {
      double tp1 = (dir == DIR_BUY) ? entry + g_initialRisk * TP1RiskReward
                                    : entry - g_initialRisk * TP1RiskReward;

      if((dir == DIR_BUY && price >= tp1) || (dir == DIR_SELL && price <= tp1))
      {
         double closeVolume = volume * (TP1ClosePercent / 100.0);
         closeVolume = NormalizeLot(closeVolume);
         double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         if(closeVolume >= volume - (minLot * 0.5))
         {
            g_trade.PositionClose(_Symbol);
         }
         else if(closeVolume >= minLot)
         {
            g_trade.PositionClosePartial(_Symbol, closeVolume);
         }

         if(MoveSLToBEOnTP1)
         {
            double be = entry;
            if(BEBufferPoints > 0)
               be = (dir == DIR_BUY) ? entry + BEBufferPoints * _Point
                                     : entry - BEBufferPoints * _Point;

            if(dir == DIR_BUY)
            {
               if(sl < be)
                  g_trade.PositionModify(_Symbol, be, tp);
            }
            else
            {
               if(sl > be || sl == 0.0)
                  g_trade.PositionModify(_Symbol, be, tp);
            }
         }

         g_tp1Hit = true;
      }
   }

   if(UseTrailingAfterTP1 && g_initialRisk > 0.0)
   {
      if(!UseMultiTP || g_tp1Hit)
      {
         double startLevel = (dir == DIR_BUY) ? entry + g_initialRisk * TrailingStartRR
                                              : entry - g_initialRisk * TrailingStartRR;

         if((dir == DIR_BUY && price >= startLevel) || (dir == DIR_SELL && price <= startLevel))
         {
            double trailDist = TrailingDistancePoints * _Point;
            double trailStep = TrailingStepPoints * _Point;
            if(trailDist <= 0.0)
               return;

            double newSL = (dir == DIR_BUY) ? price - trailDist : price + trailDist;

            if(dir == DIR_BUY)
            {
               if(sl == 0.0 || newSL > sl + trailStep)
                  g_trade.PositionModify(_Symbol, newSL, tp);
            }
            else
            {
               if(sl == 0.0 || newSL < sl - trailStep)
                  g_trade.PositionModify(_Symbol, newSL, tp);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Utility: Normalize lot size                                       |
//+------------------------------------------------------------------+
int GetVolumeDigits()
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   int digits = 0;
   if(step <= 0.0)
      return 2;

   while(step < 1.0 && digits < 8)
   {
      step *= 10.0;
      digits++;
   }

   return digits;
}

double NormalizeLot(const double lot)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   int digits = GetVolumeDigits();

   double normalized = MathMax(minLot, MathMin(maxLot, lot));
   normalized = MathFloor(normalized / step) * step;
   return NormalizeDouble(normalized, digits);
}

//+------------------------------------------------------------------+
//| Utility: Calculate lot size                                       |
//+------------------------------------------------------------------+
double CalculateLotSize(const double entryPrice, const double stopLoss)
{
   if(UseFixedLot)
      return NormalizeLot(FixedLot);

   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100.0);
   double stopDistancePoints = MathAbs(entryPrice - stopLoss) / _Point;
   if(stopDistancePoints <= 0.0)
      return 0.0;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0)
      return 0.0;

   double valuePerPoint = tickValue / tickSize;
   double lot = riskAmount / (stopDistancePoints * valuePerPoint);
   return NormalizeLot(lot);
}

//+------------------------------------------------------------------+
//| Utility: Ensure stop distance                                     |
//+------------------------------------------------------------------+
double EnforceStopDistance(const int dir, const double entry, const double stopLoss)
{
   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDistance = stopsLevel * _Point;
   double sl = stopLoss;

   if(dir == DIR_BUY && (entry - sl) < minDistance)
      sl = entry - minDistance;
   if(dir == DIR_SELL && (sl - entry) < minDistance)
      sl = entry + minDistance;

   return sl;
}

//+------------------------------------------------------------------+
//| Utility: Update touch count                                       |
//+------------------------------------------------------------------+
void UpdateTouchCount(const double level)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double distance = MathAbs(bid - level);
   double tolerance = TouchTolerancePoints * _Point;

   if(distance <= tolerance)
   {
      if(g_touchReady)
      {
         g_touchCount++;
         g_touchReady = false;
      }
   }
   else
   {
      g_touchReady = true;
   }
}

//+------------------------------------------------------------------+
//| Utility: Reset ICC state                                          |
//+------------------------------------------------------------------+
void ResetState()
{
   g_state = STATE_IDLE;
   g_direction = DIR_NONE;
   g_indicationLevel = 0.0;
   g_indicationTime = 0;
   g_invalidationLevel = 0.0;
   g_correctionExtreme = 0.0;
   g_correctionTime = 0;
   g_impulseRangePoints = 0.0;
   g_touchCount = 0;
   g_touchReady = true;
}

//+------------------------------------------------------------------+
//| Utility: Manage daily trade limit                                 |
//+------------------------------------------------------------------+
bool CanTradeToday()
{
   if(MaxTradesPerDay <= 0)
      return true;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int dayOfYear = dt.day_of_year;
   if(dayOfYear != g_lastTradeDay)
   {
      g_lastTradeDay = dayOfYear;
      g_tradesToday = 0;
   }

   return (g_tradesToday < MaxTradesPerDay);
}

//+------------------------------------------------------------------+
//| Utility: Compute take profit                                      |
//+------------------------------------------------------------------+
double ComputeTakeProfit(const int dir, const double entry, const double stopLoss)
{
   double risk = MathAbs(entry - stopLoss);
   if(risk <= 0.0)
      return 0.0;

   double tp = 0.0;

   if(UseMultiTP)
   {
      if(UseIndicationAsTP2)
      {
         if(dir == DIR_BUY && g_indicationLevel > entry)
            tp = g_indicationLevel;
         else if(dir == DIR_SELL && g_indicationLevel < entry)
            tp = g_indicationLevel;
      }

      if(tp == 0.0)
      {
         if(dir == DIR_BUY)
            tp = entry + risk * TP2RiskReward;
         else
            tp = entry - risk * TP2RiskReward;
      }

      return tp;
   }

   if(UseRiskReward)
   {
      if(dir == DIR_BUY)
         tp = entry + risk * RiskReward;
      else
         tp = entry - risk * RiskReward;
      return tp;
   }

   // Target indication level by default
   if(dir == DIR_BUY && g_indicationLevel > entry)
      tp = g_indicationLevel;
   else if(dir == DIR_SELL && g_indicationLevel < entry)
      tp = g_indicationLevel;
   else
   {
      // Fallback to risk reward if indication level is on wrong side
      if(dir == DIR_BUY)
         tp = entry + risk * RiskReward;
      else
         tp = entry - risk * RiskReward;
   }

   return tp;
}

//+------------------------------------------------------------------+
//| Attempt trade execution                                           |
//+------------------------------------------------------------------+
bool ExecuteTrade(const int dir, const double stopLossRaw)
{
   if(HasOpenPosition())
      return false;

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return false;
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
      return false;

   double entry = (dir == DIR_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                   : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double stopLoss = EnforceStopDistance(dir, entry, stopLossRaw);
   double takeProfit = ComputeTakeProfit(dir, entry, stopLoss);
   double lot = CalculateLotSize(entry, stopLoss);
   if(lot <= 0.0)
      return false;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   stopLoss = NormalizeDouble(stopLoss, digits);
   takeProfit = NormalizeDouble(takeProfit, digits);

   g_trade.SetDeviationInPoints(SlippagePoints);
   g_trade.SetExpertMagicNumber(MagicNumber);

   bool result = false;
   if(dir == DIR_BUY)
      result = g_trade.Buy(lot, _Symbol, 0.0, stopLoss, takeProfit, TradeComment);
   else
      result = g_trade.Sell(lot, _Symbol, 0.0, stopLoss, takeProfit, TradeComment);

   if(result)
   {
      g_tradesToday++;
      g_entryPrice = entry;
      g_initialStop = stopLoss;
      g_initialRisk = MathAbs(entry - stopLoss);
      g_tp1Hit = false;
      g_positionTicket = 0;
   }

   return result;
}

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(MagicNumber);
   g_trade.SetDeviationInPoints(SlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   g_london.valid = false;
   g_newyork.valid = false;
   ParseSession(LondonSession, g_london);
   ParseSession(NewYorkSession, g_newyork);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ResetState();
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   ManageOpenPosition();
   if(HasOpenPosition())
   {
      // Only one position at a time per symbol/magic
      g_state = STATE_IDLE;
      return;
   }

   if(!IsSessionAllowed())
      return;

   if(!CanTradeToday())
      return;

   // Determine bias on higher timeframe
   SwingPoint lastHigh;
   SwingPoint prevHigh;
   SwingPoint lastLow;
   SwingPoint prevLow;
   int trendDir = DIR_NONE;

   if(!GetLastSwings(BiasTimeframe, SwingLeft, SwingRight, MaxSwingBars, true, lastHigh, prevHigh))
      return;
   if(!GetLastSwings(BiasTimeframe, SwingLeft, SwingRight, MaxSwingBars, false, lastLow, prevLow))
      return;

   if(lastHigh.price > prevHigh.price && lastLow.price > prevLow.price)
      trendDir = DIR_BUY;
   else if(lastHigh.price < prevHigh.price && lastLow.price < prevLow.price)
      trendDir = DIR_SELL;
   else
      trendDir = DIR_NONE;

   if(UseHigherTimeframeFilter)
   {
      int higherTrend = GetTrendDirection(HigherTimeframe);
      if(higherTrend != trendDir)
         trendDir = DIR_NONE;
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double buffer = IndicationBufferPoints * _Point;
   if(g_state == STATE_IDLE)
   {
      double impulsePoints = MathAbs(lastHigh.price - lastLow.price) / _Point;
      if(UseImpulseFilter && impulsePoints < MinImpulsePoints)
         return;

      if(trendDir == DIR_BUY && lastHigh.time != g_indicationSwingTime)
      {
         if(bid > lastHigh.price + buffer)
         {
            g_state = STATE_INDICATED;
            g_direction = DIR_BUY;
            g_indicationLevel = lastHigh.price;
            g_indicationTime = TimeCurrent();
            g_indicationSwingTime = lastHigh.time;
            g_invalidationLevel = lastLow.price - buffer;
            g_impulseRangePoints = impulsePoints;
            g_touchCount = 0;
            g_touchReady = true;
         }
      }
      else if(trendDir == DIR_SELL && lastLow.time != g_indicationSwingTime)
      {
         if(bid < lastLow.price - buffer)
         {
            g_state = STATE_INDICATED;
            g_direction = DIR_SELL;
            g_indicationLevel = lastLow.price;
            g_indicationTime = TimeCurrent();
            g_indicationSwingTime = lastLow.time;
            g_invalidationLevel = lastHigh.price + buffer;
            g_impulseRangePoints = impulsePoints;
            g_touchCount = 0;
            g_touchReady = true;
         }
      }

      return;
   }

   // Invalidate if trend no longer aligned
   if(g_state != STATE_IDLE && ((g_direction == DIR_BUY && trendDir != DIR_BUY) ||
       (g_direction == DIR_SELL && trendDir != DIR_SELL)))
   {
      ResetState();
      return;
   }

   if(g_state == STATE_INDICATED)
   {
      UpdateTouchCount(g_indicationLevel);

      if(g_direction == DIR_BUY)
      {
         if(bid <= g_invalidationLevel)
         {
            ResetState();
            return;
         }

         if(bid <= g_indicationLevel - (MinCorrectionPoints * _Point))
         {
            g_state = STATE_CORRECTING;
            g_correctionExtreme = bid;
            g_correctionTime = TimeCurrent();
         }
      }
      else if(g_direction == DIR_SELL)
      {
         if(ask >= g_invalidationLevel)
         {
            ResetState();
            return;
         }

         if(ask >= g_indicationLevel + (MinCorrectionPoints * _Point))
         {
            g_state = STATE_CORRECTING;
            g_correctionExtreme = ask;
            g_correctionTime = TimeCurrent();
         }
      }

      return;
   }

   if(g_state == STATE_CORRECTING)
   {
      UpdateTouchCount(g_indicationLevel);

      if(g_direction == DIR_BUY)
      {
         if(bid < g_correctionExtreme)
         {
            g_correctionExtreme = bid;
            g_correctionTime = TimeCurrent();
         }

         if(bid <= g_invalidationLevel)
         {
            ResetState();
            return;
         }

         bool correctionOK = true;
         if(UseCorrectionRetraceFilter && g_impulseRangePoints > 0.0)
         {
            double correctionDepthPoints = (g_indicationLevel - g_correctionExtreme) / _Point;
            double correctionPercent = (correctionDepthPoints / g_impulseRangePoints) * 100.0;
            if(correctionPercent < MinCorrectionRetracePercent)
               correctionOK = false;
         }

         SwingPoint entrySwingHigh;
         if(correctionOK &&
            GetLastSwing(EntryTimeframe, SwingLeft, SwingRight, MaxSwingBars, true, entrySwingHigh) &&
            entrySwingHigh.time > g_correctionTime)
         {
            if(bid > entrySwingHigh.price + (EntryBufferPoints * _Point))
            {
               if(!UseSecondTouchFilter || g_touchCount >= 2)
               {
                  double stopLoss = g_correctionExtreme - (StopBufferPoints * _Point);
                  if(ExecuteTrade(DIR_BUY, stopLoss))
                     ResetState();
               }
            }
         }
      }
      else if(g_direction == DIR_SELL)
      {
         if(ask > g_correctionExtreme)
         {
            g_correctionExtreme = ask;
            g_correctionTime = TimeCurrent();
         }

         if(ask >= g_invalidationLevel)
         {
            ResetState();
            return;
         }

         bool correctionOK = true;
         if(UseCorrectionRetraceFilter && g_impulseRangePoints > 0.0)
         {
            double correctionDepthPoints = (g_correctionExtreme - g_indicationLevel) / _Point;
            double correctionPercent = (correctionDepthPoints / g_impulseRangePoints) * 100.0;
            if(correctionPercent < MinCorrectionRetracePercent)
               correctionOK = false;
         }

         SwingPoint entrySwingLow;
         if(correctionOK &&
            GetLastSwing(EntryTimeframe, SwingLeft, SwingRight, MaxSwingBars, false, entrySwingLow) &&
            entrySwingLow.time > g_correctionTime)
         {
            if(bid < entrySwingLow.price - (EntryBufferPoints * _Point))
            {
               if(!UseSecondTouchFilter || g_touchCount >= 2)
               {
                  double stopLoss = g_correctionExtreme + (StopBufferPoints * _Point);
                  if(ExecuteTrade(DIR_SELL, stopLoss))
                     ResetState();
               }
            }
         }
      }
   }
}
