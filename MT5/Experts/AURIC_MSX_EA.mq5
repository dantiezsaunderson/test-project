#property copyright "Systematic Architecture by Cursor Agent"
#property version   "1.00"
#property strict
#property description "AURIC-MSX multi-strategy EA (XAU/USD optimized, cross-market portable)"

#include <Trade/Trade.mqh>

enum RegimeType
{
   REGIME_TREND = 0,
   REGIME_RANGE = 1,
   REGIME_TRANSITION = 2
};

enum StrategyId
{
   STRAT_NONE = 0,
   STRAT_S1_MICRO = 1,
   STRAT_S2_BREAKOUT = 2,
   STRAT_S3_MEANREV = 3,
   STRAT_S4_SQUEEZE = 4,
   STRAT_S5_GRID = 5,
   STRAT_S6_SWING = 6
};

struct MarketContext
{
   double bid;
   double ask;
   double mid;
   double spreadPoints;

   double atrM1;
   double atrM5;
   double atrM15;
   double atrH4;
   double atrD1;

   double adxM5;
   double adxD1;

   double ema20M5;
   double ema50M5;
   double ema100M5;
   double ema50M5Shift10;

   double ema50D1;
   double ema200D1;
   double ema20H4;

   double vwapM1;
   double vwapM5;

   double ofiProxy;
   double velocity;
   double trendScore;
   double zScore;

   double donHighM5;
   double donLowM5;
   double donHighD1_55;
   double donLowD1_55;

   double bbWidthPercentileM15;
   double m15VolumeRatio;

   double atrPercentile;
   bool highVol;
   RegimeType regime;
};

struct StrategySignal
{
   bool valid;
   double value;
   bool longEntry;
   bool shortEntry;
   double slDistance;
   double tpDistance;
};

input group "General"
input bool   EnableS1 = true;
input bool   EnableS2 = true;
input bool   EnableS3 = true;
input bool   EnableS4 = true;
input bool   EnableS5 = true;
input bool   EnableS6 = true;
input bool   AllowNewEntries = true;
input long   MagicBase = 620000;
input int    SlippagePoints = 30;
input double DailyRiskPct = 0.80;                 // percent equity
input double MaxOpenRiskPct = 3.50;               // percent equity
input int    MaxOpenPositions = 12;

input group "Risk Guardrails"
input double SoftDrawdownPct = 8.0;
input double HardDrawdownPct = 12.0;
input double DailyLossLimitPct = 2.0;
input double WeeklyLossLimitPct = 4.0;
input double WeeklyRiskReductionFactor = 0.65;
input bool   FlattenOnHardDrawdown = true;

input group "Regime Engine"
input int    AtrPeriod = 14;
input int    AdxPeriod = 14;
input double AdxTrendThreshold = 22.0;
input double AdxRangeThreshold = 18.0;
input double TrendScoreTrendThreshold = 0.20;
input double TrendScoreRangeThreshold = 0.15;
input int    AtrPercentileLookback = 252;
input double HighVolPercentile = 0.75;

input group "S1 Micro Scalper"
input double S1EntryThreshold = 0.65;
input double S1TP_ATR = 0.35;
input double S1SL_ATR = 0.25;
input int    S1TimeStopSeconds = 180;
input int    S1SessionStartUTC = 7;               // London open hour
input int    S1SessionEndUTC = 21;                // NY close hour
input int    S1OFILookbackBars = 10;
input int    S1VelocityLookbackBars = 5;
input double S1SpreadMedianMultiplier = 1.10;

input group "S2 Momentum Breakout"
input int    S2DonchianPeriod = 20;
input double S2BreakoutBufferATR = 0.10;
input double S2TrendMinAbs = 0.25;
input double S2SL_ATR = 1.20;
input double S2TP_R = 1.50;
input double S2TrailATR = 3.0;
input int    S2TrailLookbackBars = 22;
input int    S2TimeStopBarsM5 = 24;

input group "S3 Mean Reversion"
input double S3ZEntry = 2.0;
input double S3SL_ATR = 1.0;
input double S3TP_ATR = 1.3;
input int    S3TimeStopBarsM5 = 18;
input double S3VWAPExitAbsZ = 0.2;
input double S3BbwPercentileMax = 0.60;

input group "S4 Squeeze Breakout"
input int    S4RangePeriod = 20;
input double S4SqueezePercentile = 0.20;
input double S4BreakoutBufferATR = 0.05;
input double S4VolumeMultiplier = 1.20;
input double S4SL_ATR = 1.40;
input double S4TP_ATR = 2.80;
input double S4TrailATR = 2.00;
input int    S4TimeStopBarsM15 = 16;

input group "S5 Adaptive Grid"
input int    S5GridLevels = 4;
input double S5GridSpacingATR = 0.35;
input double S5GridSL_Multiplier = 1.20;          // SL in spacing units
input double S5EmergencyDistanceATR = 1.80;
input double S5KillAdxThreshold = 20.0;
input bool   S5AllowHighVol = false;
input int    S5CooldownMinutes = 60;

input group "S6 Swing Trend"
input int    S6DonchianPeriodD1 = 55;
input double S6SL_ATR_H4 = 2.50;
input double S6TP_ATR_H4 = 4.00;
input double S6TrailATR_H4 = 3.00;
input double S6TrailActivationR = 2.0;
input int    S6TimeStopDays = 15;

input group "News / Session Filters"
input bool   UseManualNewsBlackout = true;
input string ManualNewsBlackoutUTC = "13:25-13:40;15:55-16:10";
input int    NewsBlackoutExtraMinutes = 0;
input int    ServerToUTCOffsetHours = 0;          // UTC = server time + this offset
input bool   BacktestRelaxFilters = true;         // Disable session/news/spread gates in tester

input group "Diagnostics"
input bool   PrintDiagnosticsInTester = true;
input int    DiagnosticsEveryNBarsM5 = 24;

input group "Edge Decay Controls"
input bool   EnableEdgeDecayMonitor = true;
input int    EdgeDecayLookbackTrades = 30;
input int    EdgeDecayMinTrades = 12;
input double EdgeDecayYellowWinRate = 0.40;
input double EdgeDecayRedWinRate = 0.30;
input int    EdgeDecayRedLossStreak = 8;
input bool   AutoReenableAfterRecovery = true;

const int STRATEGY_MIN = 1;
const int STRATEGY_MAX = 6;
const int STRATEGY_COUNT = 7;
const int SPREAD_BUFFER_SIZE = 300;
const int MAX_NEWS_WINDOWS = 32;
const int EDGE_BUFFER_SIZE = 120;

CTrade g_trade;

int g_hAtrM1 = INVALID_HANDLE;
int g_hAtrM5 = INVALID_HANDLE;
int g_hAtrM15 = INVALID_HANDLE;
int g_hAtrH4 = INVALID_HANDLE;
int g_hAtrD1 = INVALID_HANDLE;
int g_hAdxM5 = INVALID_HANDLE;
int g_hAdxD1 = INVALID_HANDLE;
int g_hEma20M5 = INVALID_HANDLE;
int g_hEma50M5 = INVALID_HANDLE;
int g_hEma100M5 = INVALID_HANDLE;
int g_hEma50D1 = INVALID_HANDLE;
int g_hEma200D1 = INVALID_HANDLE;
int g_hEma20H4 = INVALID_HANDLE;
int g_hBandsM15 = INVALID_HANDLE;

double g_tickValue = 0.0;
double g_tickSize = 0.0;
double g_minVolume = 0.0;
double g_maxVolume = 0.0;
double g_volumeStep = 0.0;
int    g_symbolDigits = 0;

double g_spreadBuffer[300];
int g_spreadCount = 0;
int g_spreadIndex = 0;

int g_newsStartMin[32];
int g_newsEndMin[32];
int g_newsWindowCount = 0;

double g_highWaterEquity = 0.0;
double g_dayStartEquity = 0.0;
double g_weekStartEquity = 0.0;
int g_dayId = -1;
int g_weekId = -1;
bool g_hardHalt = false;
bool g_dailyHalt = false;
bool g_weeklyPenalty = false;
datetime g_gridCooldownUntil = 0;

double g_strategyRiskScaler[7];
bool g_strategyDisabled[7];
int g_strategyLossStreak[7];
double g_strategyPnlRing[7][120];
int g_strategyPnlCount[7];
int g_strategyPnlWriteIndex[7];

ulong g_lastProcessedDeal = 0;

datetime g_lastBarM5 = 0;
datetime g_lastBarM15 = 0;
datetime g_lastBarH4 = 0;
datetime g_lastBarD1 = 0;

double Clamp(const double v, const double lo, const double hi)
{
   if(v < lo)
      return lo;
   if(v > hi)
      return hi;
   return v;
}

int Sign(const double v)
{
   if(v > 0.0)
      return 1;
   if(v < 0.0)
      return -1;
   return 0;
}

bool IsFiniteNumber(const double v)
{
   if(v == EMPTY_VALUE)
      return false;
   if(v != v)
      return false;
   return true;
}

double FastTanh(const double x)
{
   if(x >= 20.0)
      return 1.0;
   if(x <= -20.0)
      return -1.0;
   double e2x = MathExp(2.0 * x);
   return (e2x - 1.0) / (e2x + 1.0);
}

int StrategyFromMagic(const long magic)
{
   int sid = (int)(magic - MagicBase);
   if(sid < STRATEGY_MIN || sid > STRATEGY_MAX)
      return STRAT_NONE;
   return sid;
}

long StrategyMagic(const int sid)
{
   return MagicBase + sid;
}

string StrategyTag(const int sid)
{
   return StringFormat("AURIC_S%d", sid);
}

int CurrentDayId()
{
   MqlDateTime tm;
   TimeToStruct(TimeTradeServer(), tm);
   return tm.year * 1000 + tm.day_of_year;
}

int CurrentWeekId()
{
   datetime now = TimeTradeServer();
   return (int)(now / 604800);
}

bool IsNewBar(const ENUM_TIMEFRAMES tf, datetime &lastBarTime)
{
   datetime t = iTime(_Symbol, tf, 0);
   if(t <= 0)
      return false;
   if(lastBarTime == 0)
   {
      lastBarTime = t;
      return false;
   }
   if(t != lastBarTime)
   {
      lastBarTime = t;
      return true;
   }
   return false;
}

bool GetBufferValue(const int handle, const int bufferIndex, const int shift, double &value)
{
   if(handle == INVALID_HANDLE)
      return false;

   double arr[];
   ArraySetAsSeries(arr, true);
   int copied = CopyBuffer(handle, bufferIndex, shift, 1, arr);
   if(copied < 1)
      return false;
   value = arr[0];
   return IsFiniteNumber(value);
}

bool GetDonchian(const ENUM_TIMEFRAMES tf, const int period, const int shift, double &highValue, double &lowValue)
{
   int hIndex = iHighest(_Symbol, tf, MODE_HIGH, period, shift);
   int lIndex = iLowest(_Symbol, tf, MODE_LOW, period, shift);
   if(hIndex < 0 || lIndex < 0)
      return false;
   highValue = iHigh(_Symbol, tf, hIndex);
   lowValue = iLow(_Symbol, tf, lIndex);
   return (highValue > 0.0 && lowValue > 0.0 && highValue >= lowValue);
}

bool ComputeSessionVWAP(const ENUM_TIMEFRAMES tf, const int maxBars, double &vwap)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, tf, 0, maxBars, rates);
   if(copied <= 0)
      return false;

   datetime dayStart = StringToTime(TimeToString(TimeTradeServer(), TIME_DATE));
   double pv = 0.0;
   double vv = 0.0;

   for(int i = copied - 1; i >= 0; --i)
   {
      if(rates[i].time < dayStart)
         continue;
      double tp = (rates[i].high + rates[i].low + rates[i].close) / 3.0;
      double vol = (double)rates[i].tick_volume;
      pv += tp * vol;
      vv += vol;
   }

   if(vv <= 0.0)
      return false;

   vwap = pv / vv;
   return IsFiniteNumber(vwap) && vwap > 0.0;
}

double ComputeOFIProxy(const int lookbackBars)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int need = lookbackBars + 2;
   int copied = CopyRates(_Symbol, PERIOD_M1, 0, need, rates);
   if(copied < need)
      return 0.0;

   double sumSignedVol = 0.0;
   double sumVol = 0.0;

   for(int i = 0; i < lookbackBars; ++i)
   {
      double d = rates[i].close - rates[i + 1].close;
      double s = (double)Sign(d);
      double v = (double)rates[i].tick_volume;
      sumSignedVol += s * v;
      sumVol += v;
   }

   if(sumVol <= 0.0)
      return 0.0;

   return Clamp(sumSignedVol / sumVol, -1.0, 1.0);
}

double ComputeVelocityProxy(const int lookbackBars, const double atrM1)
{
   if(atrM1 <= 0.0)
      return 0.0;

   double c0 = iClose(_Symbol, PERIOD_M1, 0);
   double cn = iClose(_Symbol, PERIOD_M1, lookbackBars);
   if(c0 <= 0.0 || cn <= 0.0)
      return 0.0;

   return Clamp((c0 - cn) / atrM1, -3.0, 3.0);
}

double ComputeAtrPercentile()
{
   if(g_hAtrM5 == INVALID_HANDLE)
      return 0.5;

   int lookback = MathMax(AtrPercentileLookback, 30);
   double atr[];
   ArraySetAsSeries(atr, true);
   int copied = CopyBuffer(g_hAtrM5, 0, 0, lookback, atr);
   if(copied < 20)
      return 0.5;

   double cur = atr[0];
   int lessOrEqual = 0;
   for(int i = 0; i < copied; ++i)
   {
      if(atr[i] <= cur)
         ++lessOrEqual;
   }

   return Clamp((double)lessOrEqual / (double)copied, 0.0, 1.0);
}

double ComputeBbWidthPercentileM15()
{
   if(g_hBandsM15 == INVALID_HANDLE)
      return 0.5;

   int lookback = MathMax(AtrPercentileLookback, 50);
   double upper[];
   double lower[];
   double closeArr[];
   ArraySetAsSeries(upper, true);
   ArraySetAsSeries(lower, true);
   ArraySetAsSeries(closeArr, true);

   int u = CopyBuffer(g_hBandsM15, 1, 0, lookback, upper);
   int l = CopyBuffer(g_hBandsM15, 2, 0, lookback, lower);
   int c = CopyClose(_Symbol, PERIOD_M15, 0, lookback, closeArr);
   int n = MathMin(u, MathMin(l, c));
   if(n < 20)
      return 0.5;

   double currentWidth = 0.0;
   int validCount = 0;
   int lessOrEqual = 0;
   for(int i = 0; i < n; ++i)
   {
      if(closeArr[i] <= 0.0)
         continue;
      double w = (upper[i] - lower[i]) / closeArr[i];
      if(w <= 0.0 || !IsFiniteNumber(w))
         continue;
      if(i == 0)
         currentWidth = w;
      ++validCount;
      if(w <= currentWidth)
         ++lessOrEqual;
   }

   if(validCount < 20)
      return 0.5;

   return Clamp((double)lessOrEqual / (double)validCount, 0.0, 1.0);
}

double ComputeM15VolumeRatio()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int need = 30;
   int copied = CopyRates(_Symbol, PERIOD_M15, 0, need, rates);
   if(copied < 22)
      return 1.0;

   double cur = (double)rates[1].tick_volume; // last closed bar
   double sum = 0.0;
   int count = 0;
   for(int i = 2; i < 22; ++i)
   {
      sum += (double)rates[i].tick_volume;
      ++count;
   }

   if(sum <= 0.0 || count == 0)
      return 1.0;

   return cur / (sum / count);
}

void UpdateSpreadStats(const double spreadPoints)
{
   g_spreadBuffer[g_spreadIndex] = spreadPoints;
   g_spreadIndex = (g_spreadIndex + 1) % SPREAD_BUFFER_SIZE;
   if(g_spreadCount < SPREAD_BUFFER_SIZE)
      ++g_spreadCount;
}

double MedianSpread()
{
   if(g_spreadCount <= 0)
      return 0.0;

   double tmp[];
   ArrayResize(tmp, g_spreadCount);
   for(int i = 0; i < g_spreadCount; ++i)
      tmp[i] = g_spreadBuffer[i];
   ArraySort(tmp);

   if((g_spreadCount % 2) == 1)
      return tmp[g_spreadCount / 2];

   int hi = g_spreadCount / 2;
   int lo = hi - 1;
   return 0.5 * (tmp[lo] + tmp[hi]);
}

int ParseHHMM(const string text)
{
   string parts[];
   int p = StringSplit(text, ':', parts);
   if(p != 2)
      return -1;

   int hh = (int)StringToInteger(parts[0]);
   int mm = (int)StringToInteger(parts[1]);
   if(hh < 0 || hh > 23 || mm < 0 || mm > 59)
      return -1;
   return hh * 60 + mm;
}

bool ParseManualNewsWindows()
{
   g_newsWindowCount = 0;
   if(!UseManualNewsBlackout)
      return true;

   string blocks[];
   int cnt = StringSplit(ManualNewsBlackoutUTC, ';', blocks);
   if(cnt <= 0)
      return true;

   for(int i = 0; i < cnt && g_newsWindowCount < MAX_NEWS_WINDOWS; ++i)
   {
      string clean = blocks[i];
      StringTrimLeft(clean);
      StringTrimRight(clean);
      if(StringLen(clean) < 9)
         continue;

      string bounds[];
      int b = StringSplit(clean, '-', bounds);
      if(b != 2)
         continue;

      StringTrimLeft(bounds[0]);
      StringTrimRight(bounds[0]);
      StringTrimLeft(bounds[1]);
      StringTrimRight(bounds[1]);
      int s = ParseHHMM(bounds[0]);
      int e = ParseHHMM(bounds[1]);
      if(s < 0 || e < 0)
         continue;
      g_newsStartMin[g_newsWindowCount] = s;
      g_newsEndMin[g_newsWindowCount] = e;
      ++g_newsWindowCount;
   }

   return true;
}

int NormalizeMinute(int m)
{
   while(m < 0)
      m += 1440;
   while(m >= 1440)
      m -= 1440;
   return m;
}

bool MinuteInWindow(const int minuteOfDay, const int startMin, const int endMin)
{
   if(startMin <= endMin)
      return (minuteOfDay >= startMin && minuteOfDay <= endMin);
   return (minuteOfDay >= startMin || minuteOfDay <= endMin);
}

bool IsTesterRelaxMode()
{
   return (BacktestRelaxFilters && (bool)MQLInfoInteger(MQL_TESTER));
}

int FilterMinuteOfDay()
{
   datetime ref = TimeTradeServer() + (datetime)(ServerToUTCOffsetHours * 3600);
   MqlDateTime tm;
   TimeToStruct(ref, tm);
   return tm.hour * 60 + tm.min;
}

bool IsInNewsBlackout()
{
   if(IsTesterRelaxMode())
      return false;

   if(!UseManualNewsBlackout || g_newsWindowCount <= 0)
      return false;

   int nowMin = FilterMinuteOfDay();

   for(int i = 0; i < g_newsWindowCount; ++i)
   {
      int s = NormalizeMinute(g_newsStartMin[i] - NewsBlackoutExtraMinutes);
      int e = NormalizeMinute(g_newsEndMin[i] + NewsBlackoutExtraMinutes);
      if(MinuteInWindow(nowMin, s, e))
         return true;
   }
   return false;
}

bool IsInS1Session()
{
   if(IsTesterRelaxMode())
      return true;

   int h = FilterMinuteOfDay() / 60;
   if(S1SessionStartUTC == S1SessionEndUTC)
      return true;
   if(S1SessionStartUTC < S1SessionEndUTC)
      return (h >= S1SessionStartUTC && h < S1SessionEndUTC);
   return (h >= S1SessionStartUTC || h < S1SessionEndUTC);
}

double MinStopDistancePrice()
{
   int stops = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   return (double)stops * _Point + _Point;
}

int VolumeDigits()
{
   if(g_volumeStep <= 0.0)
      return 2;
   double step = g_volumeStep;
   int digits = 0;
   while(step < 1.0 && digits < 8)
   {
      step *= 10.0;
      ++digits;
   }
   return digits;
}

double NormalizeVolume(const double lots)
{
   if(lots <= 0.0)
      return 0.0;

   double v = MathMax(g_minVolume, MathMin(g_maxVolume, lots));
   if(g_volumeStep > 0.0)
      v = MathFloor(v / g_volumeStep) * g_volumeStep;
   return NormalizeDouble(v, VolumeDigits());
}

double NormalizePrice(const double price)
{
   return NormalizeDouble(price, g_symbolDigits);
}

double CalcLotsByRiskUSD(const double riskUsd, const double stopDistancePrice)
{
   if(riskUsd <= 0.0 || stopDistancePrice <= 0.0)
      return 0.0;
   if(g_tickValue <= 0.0 || g_tickSize <= 0.0)
      return 0.0;

   double lossPerLot = (stopDistancePrice / g_tickSize) * g_tickValue;
   if(lossPerLot <= 0.0)
      return 0.0;

   double lots = riskUsd / lossPerLot;
   return NormalizeVolume(lots);
}

double PositionRiskUSD(const ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return 0.0;
   double sl = PositionGetDouble(POSITION_SL);
   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double vol = PositionGetDouble(POSITION_VOLUME);
   if(sl <= 0.0 || open <= 0.0 || vol <= 0.0)
      return 0.0;
   double dist = MathAbs(open - sl);
   return (dist / g_tickSize) * g_tickValue * vol;
}

int CountOurOpenPositions()
{
   int count = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; ++i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      int sid = StrategyFromMagic((long)PositionGetInteger(POSITION_MAGIC));
      if(sid != STRAT_NONE)
         ++count;
   }
   return count;
}

double EstimateOpenRiskUSD()
{
   double sumRisk = 0.0;
   int total = PositionsTotal();
   for(int i = 0; i < total; ++i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      int sid = StrategyFromMagic((long)PositionGetInteger(POSITION_MAGIC));
      if(sid == STRAT_NONE)
         continue;

      double r = PositionRiskUSD(ticket);
      if(r <= 0.0)
      {
         double equity = AccountInfoDouble(ACCOUNT_EQUITY);
         r = equity * 0.0025; // fallback for positions without SL
      }
      sumRisk += r;
   }
   return sumRisk;
}

bool PortfolioCanAddRiskUSD(const double newRiskUSD)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0)
      return false;

   if(CountOurOpenPositions() >= MaxOpenPositions)
      return false;

   double openRiskPct = 100.0 * (EstimateOpenRiskUSD() + newRiskUSD) / equity;
   if(openRiskPct > MaxOpenRiskPct)
      return false;

   return true;
}

void DeletePendingByMagic(const long magic)
{
   for(int i = OrdersTotal() - 1; i >= 0; --i)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((long)OrderGetInteger(ORDER_MAGIC) != magic)
         continue;

      ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_SELL_LIMIT ||
         ot == ORDER_TYPE_BUY_STOP || ot == ORDER_TYPE_SELL_STOP ||
         ot == ORDER_TYPE_BUY_STOP_LIMIT || ot == ORDER_TYPE_SELL_STOP_LIMIT)
      {
         g_trade.OrderDelete(ticket);
      }
   }
}

void DeleteAllOurPending()
{
   for(int sid = STRATEGY_MIN; sid <= STRATEGY_MAX; ++sid)
      DeletePendingByMagic(StrategyMagic(sid));
}

bool ClosePositionTicket(const ulong ticket, const string reason)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   g_trade.SetDeviationInPoints(SlippagePoints);
   bool ok = g_trade.PositionClose(ticket);
   if(!ok)
      PrintFormat("Close failed ticket=%I64u reason=%s err=%d", ticket, reason, _LastError);
   return ok;
}

void CloseAllPositionsForStrategy(const int sid)
{
   long magic = StrategyMagic(sid);
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != magic)
         continue;
      ClosePositionTicket(ticket, "strategy_close_all");
   }
}

void CloseAllOurPositions()
{
   for(int sid = STRATEGY_MIN; sid <= STRATEGY_MAX; ++sid)
      CloseAllPositionsForStrategy(sid);
}

bool StrategyHasOpenPosition(const int sid, ulong &ticketOut, long &typeOut)
{
   ticketOut = 0;
   typeOut = -1;
   long magic = StrategyMagic(sid);

   for(int i = 0; i < PositionsTotal(); ++i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != magic)
         continue;

      ticketOut = ticket;
      typeOut = PositionGetInteger(POSITION_TYPE);
      return true;
   }
   return false;
}

bool ModifyPositionStops(const ulong ticket, const double newSL, const double newTP)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action = TRADE_ACTION_SLTP;
   req.position = ticket;
   req.symbol = _Symbol;
   req.sl = (newSL > 0.0 ? NormalizePrice(newSL) : 0.0);
   req.tp = (newTP > 0.0 ? NormalizePrice(newTP) : 0.0);

   bool ok = OrderSend(req, res);
   if(!ok || (res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_DONE_PARTIAL))
   {
      PrintFormat("SLTP modify failed ticket=%I64u ret=%d", ticket, res.retcode);
      return false;
   }
   return true;
}

bool PendingExistsNear(const long magic, const ENUM_ORDER_TYPE orderType, const double price, const double tolerance)
{
   for(int i = 0; i < OrdersTotal(); ++i)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((long)OrderGetInteger(ORDER_MAGIC) != magic)
         continue;
      ENUM_ORDER_TYPE t = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(t != orderType)
         continue;
      double p = OrderGetDouble(ORDER_PRICE_OPEN);
      if(MathAbs(p - price) <= tolerance)
         return true;
   }
   return false;
}

double StrategyBudget(const int sid, const RegimeType regime, const bool highVol)
{
   // Budget fractions from memo table.
   if(regime == REGIME_TREND && !highVol)
   {
      if(sid == STRAT_S1_MICRO) return 0.15;
      if(sid == STRAT_S2_BREAKOUT) return 0.30;
      if(sid == STRAT_S3_MEANREV) return 0.05;
      if(sid == STRAT_S4_SQUEEZE) return 0.15;
      if(sid == STRAT_S5_GRID) return 0.00;
      if(sid == STRAT_S6_SWING) return 0.35;
   }
   if(regime == REGIME_TREND && highVol)
   {
      if(sid == STRAT_S1_MICRO) return 0.10;
      if(sid == STRAT_S2_BREAKOUT) return 0.35;
      if(sid == STRAT_S3_MEANREV) return 0.00;
      if(sid == STRAT_S4_SQUEEZE) return 0.25;
      if(sid == STRAT_S5_GRID) return 0.00;
      if(sid == STRAT_S6_SWING) return 0.30;
   }
   if(regime == REGIME_RANGE && !highVol)
   {
      if(sid == STRAT_S1_MICRO) return 0.10;
      if(sid == STRAT_S2_BREAKOUT) return 0.10;
      if(sid == STRAT_S3_MEANREV) return 0.30;
      if(sid == STRAT_S4_SQUEEZE) return 0.10;
      if(sid == STRAT_S5_GRID) return 0.30;
      if(sid == STRAT_S6_SWING) return 0.10;
   }
   // Transition OR Range+HighVol fallback.
   if(sid == STRAT_S1_MICRO) return 0.05;
   if(sid == STRAT_S2_BREAKOUT) return 0.15;
   if(sid == STRAT_S3_MEANREV) return 0.20;
   if(sid == STRAT_S4_SQUEEZE) return 0.20;
   if(sid == STRAT_S5_GRID) return 0.05;
   if(sid == STRAT_S6_SWING) return 0.35;
   return 0.0;
}

double EntryThresholdForStrategy(const int sid)
{
   if(sid == STRAT_S1_MICRO) return S1EntryThreshold;
   if(sid == STRAT_S2_BREAKOUT) return 0.30;
   if(sid == STRAT_S3_MEANREV) return 0.40;
   if(sid == STRAT_S4_SQUEEZE) return 0.25;
   if(sid == STRAT_S5_GRID) return 0.00;
   if(sid == STRAT_S6_SWING) return 0.25;
   return 0.50;
}

double ReversalThresholdForStrategy(const int sid)
{
   if(sid == STRAT_S1_MICRO) return 0.20;
   if(sid == STRAT_S2_BREAKOUT) return 0.25;
   if(sid == STRAT_S3_MEANREV) return 0.20;
   if(sid == STRAT_S4_SQUEEZE) return 0.20;
   if(sid == STRAT_S6_SWING) return 0.20;
   return 0.30;
}

int TimeStopSecondsForStrategy(const int sid)
{
   if(sid == STRAT_S1_MICRO) return S1TimeStopSeconds;
   if(sid == STRAT_S2_BREAKOUT) return S2TimeStopBarsM5 * 300;
   if(sid == STRAT_S3_MEANREV) return S3TimeStopBarsM5 * 300;
   if(sid == STRAT_S4_SQUEEZE) return S4TimeStopBarsM15 * 900;
   if(sid == STRAT_S6_SWING) return S6TimeStopDays * 86400;
   return 0;
}

double GlobalRiskMultiplier()
{
   double mult = 1.0;

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_highWaterEquity > 0.0)
   {
      double dd = 100.0 * (g_highWaterEquity - eq) / g_highWaterEquity;
      if(dd >= SoftDrawdownPct)
         mult *= 0.5;
   }

   if(g_weeklyPenalty)
      mult *= WeeklyRiskReductionFactor;

   return Clamp(mult, 0.0, 1.0);
}

bool TradingHalted()
{
   if(g_hardHalt || g_dailyHalt)
      return true;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return true;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return true;
   return false;
}

void RefreshRiskState()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq <= 0.0)
      return;

   int d = CurrentDayId();
   int w = CurrentWeekId();
   if(g_dayId != d)
   {
      g_dayId = d;
      g_dayStartEquity = eq;
      g_dailyHalt = false;
   }
   if(g_weekId != w)
   {
      g_weekId = w;
      g_weekStartEquity = eq;
      g_weeklyPenalty = false;
   }

   if(eq > g_highWaterEquity)
      g_highWaterEquity = eq;

   if(g_dayStartEquity > 0.0)
   {
      double dayPnlPct = 100.0 * (eq - g_dayStartEquity) / g_dayStartEquity;
      if(dayPnlPct <= -DailyLossLimitPct)
      {
         g_dailyHalt = true;
         PrintFormat("Daily loss limit breached: %.2f%%", dayPnlPct);
      }
   }

   if(g_weekStartEquity > 0.0)
   {
      double weekPnlPct = 100.0 * (eq - g_weekStartEquity) / g_weekStartEquity;
      if(weekPnlPct <= -WeeklyLossLimitPct)
      {
         g_weeklyPenalty = true;
         PrintFormat("Weekly loss threshold breached: %.2f%%", weekPnlPct);
      }
   }

   if(g_highWaterEquity > 0.0)
   {
      double dd = 100.0 * (g_highWaterEquity - eq) / g_highWaterEquity;
      if(dd >= HardDrawdownPct)
      {
         if(!g_hardHalt)
            PrintFormat("Hard drawdown reached: %.2f%%. Trading halted.", dd);
         g_hardHalt = true;
         if(FlattenOnHardDrawdown)
         {
            CloseAllOurPositions();
            DeleteAllOurPending();
         }
      }
   }
}

bool BuildContext(MarketContext &ctx)
{
   ZeroMemory(ctx);

   ctx.bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   ctx.ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(ctx.bid <= 0.0 || ctx.ask <= 0.0 || ctx.ask <= ctx.bid)
      return false;
   ctx.mid = 0.5 * (ctx.bid + ctx.ask);
   ctx.spreadPoints = (ctx.ask - ctx.bid) / _Point;

   if(!GetBufferValue(g_hAtrM1, 0, 0, ctx.atrM1)) return false;
   if(!GetBufferValue(g_hAtrM5, 0, 0, ctx.atrM5)) return false;
   if(!GetBufferValue(g_hAtrM15, 0, 0, ctx.atrM15)) return false;
   if(!GetBufferValue(g_hAtrH4, 0, 0, ctx.atrH4)) return false;
   if(!GetBufferValue(g_hAtrD1, 0, 0, ctx.atrD1)) return false;

   if(!GetBufferValue(g_hAdxM5, 0, 1, ctx.adxM5)) return false;
   if(!GetBufferValue(g_hAdxD1, 0, 1, ctx.adxD1)) return false;

   if(!GetBufferValue(g_hEma20M5, 0, 1, ctx.ema20M5)) return false;
   if(!GetBufferValue(g_hEma50M5, 0, 1, ctx.ema50M5)) return false;
   if(!GetBufferValue(g_hEma100M5, 0, 1, ctx.ema100M5)) return false;
   if(!GetBufferValue(g_hEma50M5, 0, 11, ctx.ema50M5Shift10)) return false;
   if(!GetBufferValue(g_hEma50D1, 0, 1, ctx.ema50D1)) return false;
   if(!GetBufferValue(g_hEma200D1, 0, 1, ctx.ema200D1)) return false;
   if(!GetBufferValue(g_hEma20H4, 0, 1, ctx.ema20H4)) return false;

   if(!ComputeSessionVWAP(PERIOD_M1, 3000, ctx.vwapM1))
      ctx.vwapM1 = ctx.mid;
   if(!ComputeSessionVWAP(PERIOD_M5, 1000, ctx.vwapM5))
      ctx.vwapM5 = ctx.mid;

   ctx.ofiProxy = ComputeOFIProxy(S1OFILookbackBars);
   ctx.velocity = ComputeVelocityProxy(S1VelocityLookbackBars, ctx.atrM1);

   double eps = 1e-9;
   ctx.trendScore =
      FastTanh((ctx.ema20M5 - ctx.ema100M5) / MathMax(1.5 * ctx.atrM5, eps)) +
      0.5 * FastTanh((ctx.ema50M5 - ctx.ema50M5Shift10) / MathMax(ctx.atrM5, eps));
   ctx.trendScore = Clamp(ctx.trendScore, -2.0, 2.0);

   ctx.zScore = (ctx.mid - ctx.vwapM5) / MathMax(0.8 * ctx.atrM5, eps);
   ctx.zScore = Clamp(ctx.zScore, -8.0, 8.0);

   GetDonchian(PERIOD_M5, S2DonchianPeriod, 1, ctx.donHighM5, ctx.donLowM5);
   GetDonchian(PERIOD_D1, S6DonchianPeriodD1, 1, ctx.donHighD1_55, ctx.donLowD1_55);

   ctx.bbWidthPercentileM15 = ComputeBbWidthPercentileM15();
   ctx.m15VolumeRatio = ComputeM15VolumeRatio();

   ctx.atrPercentile = ComputeAtrPercentile();
   ctx.highVol = (ctx.atrPercentile > HighVolPercentile);

   if(ctx.adxM5 >= AdxTrendThreshold && MathAbs(ctx.trendScore) >= TrendScoreTrendThreshold)
      ctx.regime = REGIME_TREND;
   else if(ctx.adxM5 < AdxRangeThreshold && MathAbs(ctx.trendScore) < TrendScoreRangeThreshold)
      ctx.regime = REGIME_RANGE;
   else
      ctx.regime = REGIME_TRANSITION;

   return true;
}

StrategySignal EvaluateS1(const MarketContext &ctx)
{
   StrategySignal sig;
   ZeroMemory(sig);
   sig.valid = false;

   if(!EnableS1 || ctx.atrM1 <= 0.0)
      return sig;

   double denom = MathMax(0.25 * ctx.atrM1, 1e-9);
   double raw = 0.45 * ctx.ofiProxy +
                0.35 * ((ctx.mid - ctx.vwapM1) / denom) +
                0.20 * ctx.velocity;
   sig.value = Clamp(raw, -1.0, 1.0);
   sig.slDistance = MathMax(S1SL_ATR * ctx.atrM1, MinStopDistancePrice());
   sig.tpDistance = MathMax(S1TP_ATR * ctx.atrM1, MinStopDistancePrice());
   sig.valid = true;

   double medianSpread = MedianSpread();
   bool spreadOk = true;
   if(!IsTesterRelaxMode() && medianSpread > 0.0)
      spreadOk = (ctx.spreadPoints <= S1SpreadMedianMultiplier * medianSpread);

   bool baseOk = spreadOk && IsInS1Session() && !IsInNewsBlackout();
   sig.longEntry = (baseOk && sig.value > S1EntryThreshold);
   sig.shortEntry = (baseOk && sig.value < -S1EntryThreshold);
   return sig;
}

StrategySignal EvaluateS2(const MarketContext &ctx)
{
   StrategySignal sig;
   ZeroMemory(sig);
   sig.valid = false;

   if(!EnableS2 || ctx.atrM5 <= 0.0 || ctx.donHighM5 <= 0.0 || ctx.donLowM5 <= 0.0)
      return sig;

   double close1 = iClose(_Symbol, PERIOD_M5, 1);
   if(close1 <= 0.0)
      return sig;

   double bo = 0.0;
   if(close1 > ctx.donHighM5)
      bo = (close1 - ctx.donHighM5) / MathMax(ctx.atrM5, 1e-9);
   else if(close1 < ctx.donLowM5)
      bo = -(ctx.donLowM5 - close1) / MathMax(ctx.atrM5, 1e-9);

   double adxScaled = Clamp((ctx.adxM5 - 20.0) / 20.0, -1.0, 1.0);
   double raw = 0.50 * bo + 0.30 * ctx.trendScore + 0.20 * adxScaled;
   sig.value = Clamp(raw, -1.0, 1.0);
   sig.slDistance = MathMax(S2SL_ATR * ctx.atrM5, MinStopDistancePrice());
   sig.tpDistance = MathMax(sig.slDistance * S2TP_R, MinStopDistancePrice());
   sig.valid = true;

   bool longBreak = (close1 > (ctx.donHighM5 + S2BreakoutBufferATR * ctx.atrM5));
   bool shortBreak = (close1 < (ctx.donLowM5 - S2BreakoutBufferATR * ctx.atrM5));
   bool trendOk = (ctx.adxM5 > AdxTrendThreshold && MathAbs(ctx.trendScore) > S2TrendMinAbs);
   bool baseOk = (!IsInNewsBlackout() && trendOk);
   sig.longEntry = (baseOk && longBreak);
   sig.shortEntry = (baseOk && shortBreak);
   return sig;
}

StrategySignal EvaluateS3(const MarketContext &ctx)
{
   StrategySignal sig;
   ZeroMemory(sig);
   sig.valid = false;

   if(!EnableS3 || ctx.atrM5 <= 0.0)
      return sig;

   double damp = 1.0 - MathMin(1.0, ctx.adxM5 / 30.0);
   double raw = -ctx.zScore * damp;
   sig.value = Clamp(raw, -1.0, 1.0);
   sig.slDistance = MathMax(S3SL_ATR * ctx.atrM5, MinStopDistancePrice());
   sig.tpDistance = MathMax(S3TP_ATR * ctx.atrM5, MinStopDistancePrice());
   sig.valid = true;

   bool regimeOk = (ctx.adxM5 < AdxRangeThreshold);
   bool bbwOk = (ctx.bbWidthPercentileM15 <= S3BbwPercentileMax);
   bool baseOk = (!IsInNewsBlackout() && regimeOk && bbwOk);
   sig.longEntry = (baseOk && ctx.zScore <= -S3ZEntry);
   sig.shortEntry = (baseOk && ctx.zScore >= S3ZEntry);
   return sig;
}

StrategySignal EvaluateS4(const MarketContext &ctx)
{
   StrategySignal sig;
   ZeroMemory(sig);
   sig.valid = false;

   if(!EnableS4 || ctx.atrM15 <= 0.0)
      return sig;

   double rangeHigh = 0.0;
   double rangeLow = 0.0;
   if(!GetDonchian(PERIOD_M15, S4RangePeriod, 1, rangeHigh, rangeLow))
      return sig;
   if(rangeHigh <= rangeLow)
      return sig;

   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   if(close1 <= 0.0)
      return sig;

   double rangeMid = 0.5 * (rangeHigh + rangeLow);
   double halfWidth = MathMax((rangeHigh - rangeLow) * 0.5, 1e-9);
   double raw = (close1 - rangeMid) / halfWidth;
   sig.value = Clamp(raw, -1.0, 1.0);
   sig.slDistance = MathMax(S4SL_ATR * ctx.atrM15, MinStopDistancePrice());
   sig.tpDistance = MathMax(S4TP_ATR * ctx.atrM15, MinStopDistancePrice());
   sig.valid = true;

   bool squeeze = (ctx.bbWidthPercentileM15 <= S4SqueezePercentile);
   double atrM15Prev = 0.0;
   if(!GetBufferValue(g_hAtrM15, 0, 1, atrM15Prev))
      atrM15Prev = ctx.atrM15;
   bool volRising = (ctx.atrM15 > atrM15Prev);
   bool volOk = (ctx.m15VolumeRatio >= S4VolumeMultiplier);
   bool longBreak = close1 > (rangeHigh + S4BreakoutBufferATR * ctx.atrM15);
   bool shortBreak = close1 < (rangeLow - S4BreakoutBufferATR * ctx.atrM15);
   bool baseOk = (!IsInNewsBlackout() && squeeze && volRising && volOk);
   sig.longEntry = (baseOk && longBreak);
   sig.shortEntry = (baseOk && shortBreak);
   return sig;
}

StrategySignal EvaluateS6(const MarketContext &ctx)
{
   StrategySignal sig;
   ZeroMemory(sig);
   sig.valid = false;

   if(!EnableS6 || ctx.atrD1 <= 0.0 || ctx.atrH4 <= 0.0)
      return sig;

   double trendD1 = (ctx.ema50D1 - ctx.ema200D1) / MathMax(1.5 * ctx.atrD1, 1e-9);
   double closeD1 = iClose(_Symbol, PERIOD_D1, 1);
   if(closeD1 <= 0.0)
      return sig;

   double breakTerm = 0.0;
   if(ctx.donHighD1_55 > 0.0 && ctx.donLowD1_55 > 0.0 && ctx.donHighD1_55 >= ctx.donLowD1_55)
   {
      if(closeD1 > ctx.donHighD1_55)
         breakTerm = (closeD1 - ctx.donHighD1_55) / MathMax(ctx.atrD1, 1e-9);
      else if(closeD1 < ctx.donLowD1_55)
         breakTerm = -(ctx.donLowD1_55 - closeD1) / MathMax(ctx.atrD1, 1e-9);
   }

   double h4Close1 = iClose(_Symbol, PERIOD_H4, 1);
   double h4Close2 = iClose(_Symbol, PERIOD_H4, 2);
   if(h4Close1 <= 0.0 || h4Close2 <= 0.0)
      return sig;

   double pullbackScore = Clamp((h4Close1 - ctx.ema20H4) / MathMax(ctx.atrH4, 1e-9), -1.0, 1.0);
   double raw = 0.4 * trendD1 + 0.3 * breakTerm + 0.3 * pullbackScore;
   sig.value = Clamp(raw, -1.0, 1.0);
   sig.slDistance = MathMax(S6SL_ATR_H4 * ctx.atrH4, MinStopDistancePrice());
   sig.tpDistance = MathMax(S6TP_ATR_H4 * ctx.atrH4, MinStopDistancePrice());
   sig.valid = true;

   bool longTrend = (ctx.ema50D1 > ctx.ema200D1 && ctx.adxD1 > 20.0);
   bool shortTrend = (ctx.ema50D1 < ctx.ema200D1 && ctx.adxD1 > 20.0);
   bool longReentry = (h4Close2 < ctx.ema20H4 && h4Close1 > ctx.ema20H4);
   bool shortReentry = (h4Close2 > ctx.ema20H4 && h4Close1 < ctx.ema20H4);

   sig.longEntry = (!IsInNewsBlackout() && longTrend && longReentry);
   sig.shortEntry = (!IsInNewsBlackout() && shortTrend && shortReentry);
   return sig;
}

bool OpenMarketPosition(const int sid, const int direction, const StrategySignal &sig, const MarketContext &ctx)
{
   if(direction == 0 || !sig.valid)
      return false;

   if(g_strategyDisabled[sid])
      return false;

   double budget = StrategyBudget(sid, ctx.regime, ctx.highVol);
   if(budget <= 0.0)
      return false;

   double entryThreshold = MathMax(EntryThresholdForStrategy(sid), 0.01);
   double conviction = Clamp(MathAbs(sig.value) / entryThreshold, 0.5, 1.5);
   double riskScale = GlobalRiskMultiplier() * g_strategyRiskScaler[sid];
   if(riskScale <= 0.0)
      return false;

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq <= 0.0)
      return false;

   double riskUsd = eq * (DailyRiskPct / 100.0) * budget * conviction * riskScale;
   if(riskUsd <= 0.0)
      return false;

   double slDist = MathMax(sig.slDistance, MinStopDistancePrice());
   double tpDist = sig.tpDistance;
   double lots = CalcLotsByRiskUSD(riskUsd, slDist);
   if(lots <= 0.0)
      return false;

   if(!PortfolioCanAddRiskUSD(riskUsd))
      return false;

   double price = (direction > 0 ? ctx.ask : ctx.bid);
   double sl = 0.0;
   double tp = 0.0;
   if(direction > 0)
   {
      sl = NormalizePrice(price - slDist);
      if(tpDist > 0.0)
         tp = NormalizePrice(price + tpDist);
   }
   else
   {
      sl = NormalizePrice(price + slDist);
      if(tpDist > 0.0)
         tp = NormalizePrice(price - tpDist);
   }

   g_trade.SetExpertMagicNumber(StrategyMagic(sid));
   g_trade.SetDeviationInPoints(SlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   bool ok = false;
   string comment = StrategyTag(sid);
   if(direction > 0)
      ok = g_trade.Buy(lots, _Symbol, 0.0, sl, tp, comment);
   else
      ok = g_trade.Sell(lots, _Symbol, 0.0, sl, tp, comment);

   if(!ok)
      PrintFormat("Order failed %s dir=%d err=%d ret=%u (%s) lots=%.2f sl=%.5f tp=%.5f",
                  comment, direction, _LastError, g_trade.ResultRetcode(),
                  g_trade.ResultRetcodeDescription(), lots, sl, tp);
   return ok;
}

void ManageOpenPositions(const MarketContext &ctx, const StrategySignal &s1, const StrategySignal &s2,
                         const StrategySignal &s3, const StrategySignal &s4, const StrategySignal &s6)
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      int sid = StrategyFromMagic((long)PositionGetInteger(POSITION_MAGIC));
      if(sid == STRAT_NONE)
         continue;

      long pType = PositionGetInteger(POSITION_TYPE);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);

      int tStop = TimeStopSecondsForStrategy(sid);
      if(tStop > 0 && (TimeTradeServer() - openTime) >= tStop)
      {
         ClosePositionTicket(ticket, "time_stop");
         continue;
      }

      double signalValue = 0.0;
      if(sid == STRAT_S1_MICRO) signalValue = s1.value;
      if(sid == STRAT_S2_BREAKOUT) signalValue = s2.value;
      if(sid == STRAT_S3_MEANREV) signalValue = s3.value;
      if(sid == STRAT_S4_SQUEEZE) signalValue = s4.value;
      if(sid == STRAT_S6_SWING) signalValue = s6.value;

      double rev = ReversalThresholdForStrategy(sid);
      if(pType == POSITION_TYPE_BUY && signalValue <= -rev && sid != STRAT_S5_GRID)
      {
         ClosePositionTicket(ticket, "signal_reversal");
         continue;
      }
      if(pType == POSITION_TYPE_SELL && signalValue >= rev && sid != STRAT_S5_GRID)
      {
         ClosePositionTicket(ticket, "signal_reversal");
         continue;
      }

      if(sid == STRAT_S3_MEANREV)
      {
         if(pType == POSITION_TYPE_BUY && ctx.zScore >= -S3VWAPExitAbsZ)
         {
            ClosePositionTicket(ticket, "vwap_reversion");
            continue;
         }
         if(pType == POSITION_TYPE_SELL && ctx.zScore <= S3VWAPExitAbsZ)
         {
            ClosePositionTicket(ticket, "vwap_reversion");
            continue;
         }
      }

      double newSL = curSL;
      double newTP = curTP;
      bool change = false;

      if(sid == STRAT_S2_BREAKOUT)
      {
         double hh = 0.0, ll = 0.0;
         if(GetDonchian(PERIOD_M5, S2TrailLookbackBars, 1, hh, ll))
         {
            if(pType == POSITION_TYPE_BUY)
            {
               double trail = hh - S2TrailATR * ctx.atrM5;
               if((curSL <= 0.0 || trail > curSL) && trail < ctx.bid - MinStopDistancePrice())
               {
                  newSL = trail;
                  change = true;
               }
            }
            else if(pType == POSITION_TYPE_SELL)
            {
               double trail = ll + S2TrailATR * ctx.atrM5;
               if((curSL <= 0.0 || trail < curSL) && trail > ctx.ask + MinStopDistancePrice())
               {
                  newSL = trail;
                  change = true;
               }
            }
         }
      }
      else if(sid == STRAT_S4_SQUEEZE)
      {
         if(pType == POSITION_TYPE_BUY)
         {
            double trail = ctx.bid - S4TrailATR * ctx.atrM15;
            if((curSL <= 0.0 || trail > curSL) && trail < ctx.bid - MinStopDistancePrice())
            {
               newSL = trail;
               change = true;
            }
         }
         else if(pType == POSITION_TYPE_SELL)
         {
            double trail = ctx.ask + S4TrailATR * ctx.atrM15;
            if((curSL <= 0.0 || trail < curSL) && trail > ctx.ask + MinStopDistancePrice())
            {
               newSL = trail;
               change = true;
            }
         }
      }
      else if(sid == STRAT_S6_SWING)
      {
         double initRisk = MathAbs(openPrice - curSL);
         if(initRisk <= 0.0)
            initRisk = S6SL_ATR_H4 * ctx.atrH4;

         if(pType == POSITION_TYPE_BUY)
         {
            double move = ctx.bid - openPrice;
            if(move >= S6TrailActivationR * initRisk)
            {
               double trail = ctx.bid - S6TrailATR_H4 * ctx.atrH4;
               if((curSL <= 0.0 || trail > curSL) && trail < ctx.bid - MinStopDistancePrice())
               {
                  newSL = trail;
                  change = true;
               }
            }
         }
         else if(pType == POSITION_TYPE_SELL)
         {
            double move = openPrice - ctx.ask;
            if(move >= S6TrailActivationR * initRisk)
            {
               double trail = ctx.ask + S6TrailATR_H4 * ctx.atrH4;
               if((curSL <= 0.0 || trail < curSL) && trail > ctx.ask + MinStopDistancePrice())
               {
                  newSL = trail;
                  change = true;
               }
            }
         }
      }

      if(change)
         ModifyPositionStops(ticket, newSL, newTP);
   }
}

void ManageGrid(const MarketContext &ctx)
{
   if(!EnableS5)
   {
      DeletePendingByMagic(StrategyMagic(STRAT_S5_GRID));
      return;
   }

   bool news = IsInNewsBlackout();
   bool regimeOk = (ctx.regime == REGIME_RANGE);
   bool volOk = (!ctx.highVol || S5AllowHighVol);
   bool trendKill = (ctx.adxM5 > S5KillAdxThreshold || MathAbs(ctx.trendScore) > 0.20);
   bool inCooldown = (TimeTradeServer() < g_gridCooldownUntil);

   if(trendKill)
   {
      CloseAllPositionsForStrategy(STRAT_S5_GRID);
      DeletePendingByMagic(StrategyMagic(STRAT_S5_GRID));
      g_gridCooldownUntil = TimeTradeServer() + S5CooldownMinutes * 60;
      return;
   }

   if(news || !regimeOk || !volOk || inCooldown || TradingHalted() || !AllowNewEntries)
   {
      DeletePendingByMagic(StrategyMagic(STRAT_S5_GRID));
      return;
   }

   double anchor = ctx.vwapM5;
   double spacing = MathMax(S5GridSpacingATR * ctx.atrM5, MinStopDistancePrice());
   double emergency = S5EmergencyDistanceATR * ctx.atrM5;
   if(MathAbs(ctx.mid - anchor) > emergency)
   {
      CloseAllPositionsForStrategy(STRAT_S5_GRID);
      DeletePendingByMagic(StrategyMagic(STRAT_S5_GRID));
      g_gridCooldownUntil = TimeTradeServer() + S5CooldownMinutes * 60;
      return;
   }

   double budget = StrategyBudget(STRAT_S5_GRID, ctx.regime, ctx.highVol);
   double riskScale = GlobalRiskMultiplier() * g_strategyRiskScaler[STRAT_S5_GRID];
   if(g_strategyDisabled[STRAT_S5_GRID] || budget <= 0.0 || riskScale <= 0.0)
      return;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double totalGridRiskUsd = equity * (DailyRiskPct / 100.0) * budget * riskScale;
   int legs = MathMax(S5GridLevels * 2, 1);
   double riskPerLeg = totalGridRiskUsd / legs;
   double slDist = MathMax(S5GridSL_Multiplier * spacing, MinStopDistancePrice());
   double lots = CalcLotsByRiskUSD(riskPerLeg, slDist);
   if(lots <= 0.0)
      return;

   long magic = StrategyMagic(STRAT_S5_GRID);
   double tol = spacing * 0.10;

   for(int k = 1; k <= S5GridLevels; ++k)
   {
      double buyPrice = NormalizePrice(anchor - k * spacing);
      double sellPrice = NormalizePrice(anchor + k * spacing);

      if(buyPrice < ctx.bid - MinStopDistancePrice() &&
         !PendingExistsNear(magic, ORDER_TYPE_BUY_LIMIT, buyPrice, tol))
      {
         double sl = NormalizePrice(buyPrice - slDist);
         double tp = NormalizePrice(buyPrice + spacing);
         if(PortfolioCanAddRiskUSD(riskPerLeg))
         {
            g_trade.SetExpertMagicNumber(magic);
            bool ok = g_trade.BuyLimit(lots, buyPrice, _Symbol, sl, tp, ORDER_TIME_GTC, 0, StrategyTag(STRAT_S5_GRID));
            if(!ok)
               PrintFormat("Grid BuyLimit failed err=%d ret=%u (%s) lots=%.2f price=%.5f sl=%.5f tp=%.5f",
                           _LastError, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription(),
                           lots, buyPrice, sl, tp);
         }
      }

      if(sellPrice > ctx.ask + MinStopDistancePrice() &&
         !PendingExistsNear(magic, ORDER_TYPE_SELL_LIMIT, sellPrice, tol))
      {
         double sl = NormalizePrice(sellPrice + slDist);
         double tp = NormalizePrice(sellPrice - spacing);
         if(PortfolioCanAddRiskUSD(riskPerLeg))
         {
            g_trade.SetExpertMagicNumber(magic);
            bool ok = g_trade.SellLimit(lots, sellPrice, _Symbol, sl, tp, ORDER_TIME_GTC, 0, StrategyTag(STRAT_S5_GRID));
            if(!ok)
               PrintFormat("Grid SellLimit failed err=%d ret=%u (%s) lots=%.2f price=%.5f sl=%.5f tp=%.5f",
                           _LastError, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription(),
                           lots, sellPrice, sl, tp);
         }
      }
   }
}

void PushStrategyPnl(const int sid, const double pnl)
{
   if(sid < STRATEGY_MIN || sid > STRATEGY_MAX)
      return;

   int idx = g_strategyPnlWriteIndex[sid] % EDGE_BUFFER_SIZE;
   g_strategyPnlRing[sid][idx] = pnl;
   g_strategyPnlWriteIndex[sid]++;
   if(g_strategyPnlCount[sid] < EDGE_BUFFER_SIZE)
      g_strategyPnlCount[sid]++;

   if(pnl < 0.0)
      g_strategyLossStreak[sid]++;
   else
      g_strategyLossStreak[sid] = 0;
}

void ProcessNewDealsForEdgeDecay()
{
   if(!EnableEdgeDecayMonitor)
      return;

   datetime now = TimeTradeServer();
   if(!HistorySelect(now - 86400 * 45, now))
      return;

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; ++i)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0 || dealTicket <= g_lastProcessedDeal)
         continue;

      long entryType = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_OUT_BY)
         continue;

      string sym = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
      if(sym != _Symbol)
         continue;

      long magic = (long)HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
      int sid = StrategyFromMagic(magic);
      if(sid == STRAT_NONE)
         continue;

      double pnl = HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                 + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                 + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      PushStrategyPnl(sid, pnl);
   }

   if(total > 0)
      g_lastProcessedDeal = HistoryDealGetTicket(total - 1);
}

void EvaluateEdgeDecay()
{
   if(!EnableEdgeDecayMonitor)
      return;

   for(int sid = STRATEGY_MIN; sid <= STRATEGY_MAX; ++sid)
   {
      int nTotal = g_strategyPnlCount[sid];
      int n = MathMin(nTotal, EdgeDecayLookbackTrades);
      if(n < EdgeDecayMinTrades)
      {
         g_strategyRiskScaler[sid] = 1.0;
         continue;
      }

      double sum = 0.0;
      int wins = 0;
      for(int j = 0; j < n; ++j)
      {
         int idx = (g_strategyPnlWriteIndex[sid] - 1 - j);
         while(idx < 0)
            idx += EDGE_BUFFER_SIZE;
         idx %= EDGE_BUFFER_SIZE;

         double p = g_strategyPnlRing[sid][idx];
         sum += p;
         if(p > 0.0)
            ++wins;
      }

      double avg = sum / n;
      double winRate = (double)wins / n;

      if(g_strategyLossStreak[sid] >= EdgeDecayRedLossStreak || (avg < 0.0 && winRate < EdgeDecayRedWinRate))
      {
         g_strategyDisabled[sid] = true;
         g_strategyRiskScaler[sid] = 0.0;
      }
      else if(avg < 0.0 && winRate < EdgeDecayYellowWinRate)
      {
         g_strategyRiskScaler[sid] = 0.5;
      }
      else
      {
         g_strategyRiskScaler[sid] = 1.0;
         if(AutoReenableAfterRecovery && winRate > 0.5 && avg > 0.0)
            g_strategyDisabled[sid] = false;
      }
   }
}

void UpdateEdgeDecay()
{
   ProcessNewDealsForEdgeDecay();
   EvaluateEdgeDecay();
}

void TryOpenStrategies(const MarketContext &ctx, const StrategySignal &s1, const StrategySignal &s2,
                       const StrategySignal &s3, const StrategySignal &s4, const StrategySignal &s6,
                       const bool newM5, const bool newM15, const bool newH4)
{
   if(!AllowNewEntries || TradingHalted())
      return;

   // S1 can trigger on tick.
   if(EnableS1 && !g_strategyDisabled[STRAT_S1_MICRO] && s1.valid)
   {
      ulong ticket = 0;
      long type = -1;
      if(!StrategyHasOpenPosition(STRAT_S1_MICRO, ticket, type))
      {
         if(s1.longEntry) OpenMarketPosition(STRAT_S1_MICRO, +1, s1, ctx);
         else if(s1.shortEntry) OpenMarketPosition(STRAT_S1_MICRO, -1, s1, ctx);
      }
   }

   // S2 / S3 evaluate and enter on M5 close.
   if(newM5)
   {
      if(EnableS2 && !g_strategyDisabled[STRAT_S2_BREAKOUT] && s2.valid)
      {
         ulong t = 0;
         long ty = -1;
         if(!StrategyHasOpenPosition(STRAT_S2_BREAKOUT, t, ty))
         {
            if(s2.longEntry) OpenMarketPosition(STRAT_S2_BREAKOUT, +1, s2, ctx);
            else if(s2.shortEntry) OpenMarketPosition(STRAT_S2_BREAKOUT, -1, s2, ctx);
         }
      }

      if(EnableS3 && !g_strategyDisabled[STRAT_S3_MEANREV] && s3.valid)
      {
         ulong t = 0;
         long ty = -1;
         if(!StrategyHasOpenPosition(STRAT_S3_MEANREV, t, ty))
         {
            if(s3.longEntry) OpenMarketPosition(STRAT_S3_MEANREV, +1, s3, ctx);
            else if(s3.shortEntry) OpenMarketPosition(STRAT_S3_MEANREV, -1, s3, ctx);
         }
      }
   }

   // S4 enters on M15 close.
   if(newM15 && EnableS4 && !g_strategyDisabled[STRAT_S4_SQUEEZE] && s4.valid)
   {
      ulong t = 0;
      long ty = -1;
      if(!StrategyHasOpenPosition(STRAT_S4_SQUEEZE, t, ty))
      {
         if(s4.longEntry) OpenMarketPosition(STRAT_S4_SQUEEZE, +1, s4, ctx);
         else if(s4.shortEntry) OpenMarketPosition(STRAT_S4_SQUEEZE, -1, s4, ctx);
      }
   }

   // S6 enters on H4 close.
   if(newH4 && EnableS6 && !g_strategyDisabled[STRAT_S6_SWING] && s6.valid)
   {
      ulong t = 0;
      long ty = -1;
      if(!StrategyHasOpenPosition(STRAT_S6_SWING, t, ty))
      {
         if(s6.longEntry) OpenMarketPosition(STRAT_S6_SWING, +1, s6, ctx);
         else if(s6.shortEntry) OpenMarketPosition(STRAT_S6_SWING, -1, s6, ctx);
      }
   }
}

bool BuildIndicatorHandles()
{
   g_hAtrM1 = iATR(_Symbol, PERIOD_M1, AtrPeriod);
   g_hAtrM5 = iATR(_Symbol, PERIOD_M5, AtrPeriod);
   g_hAtrM15 = iATR(_Symbol, PERIOD_M15, AtrPeriod);
   g_hAtrH4 = iATR(_Symbol, PERIOD_H4, AtrPeriod);
   g_hAtrD1 = iATR(_Symbol, PERIOD_D1, AtrPeriod);
   g_hAdxM5 = iADX(_Symbol, PERIOD_M5, AdxPeriod);
   g_hAdxD1 = iADX(_Symbol, PERIOD_D1, AdxPeriod);
   g_hEma20M5 = iMA(_Symbol, PERIOD_M5, 20, 0, MODE_EMA, PRICE_CLOSE);
   g_hEma50M5 = iMA(_Symbol, PERIOD_M5, 50, 0, MODE_EMA, PRICE_CLOSE);
   g_hEma100M5 = iMA(_Symbol, PERIOD_M5, 100, 0, MODE_EMA, PRICE_CLOSE);
   g_hEma50D1 = iMA(_Symbol, PERIOD_D1, 50, 0, MODE_EMA, PRICE_CLOSE);
   g_hEma200D1 = iMA(_Symbol, PERIOD_D1, 200, 0, MODE_EMA, PRICE_CLOSE);
   g_hEma20H4 = iMA(_Symbol, PERIOD_H4, 20, 0, MODE_EMA, PRICE_CLOSE);
   g_hBandsM15 = iBands(_Symbol, PERIOD_M15, 20, 0, 2.0, PRICE_CLOSE);

   int handles[14] = {g_hAtrM1, g_hAtrM5, g_hAtrM15, g_hAtrH4, g_hAtrD1,
                      g_hAdxM5, g_hAdxD1, g_hEma20M5, g_hEma50M5, g_hEma100M5,
                      g_hEma50D1, g_hEma200D1, g_hEma20H4, g_hBandsM15};
   for(int i = 0; i < 14; ++i)
   {
      if(handles[i] == INVALID_HANDLE)
         return false;
   }
   return true;
}

void ReleaseHandle(const int handle)
{
   if(handle != INVALID_HANDLE)
      IndicatorRelease(handle);
}

int OnInit()
{
   g_trade.SetDeviationInPoints(SlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   g_tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   g_tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   g_minVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   g_maxVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   g_volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   g_symbolDigits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(g_tickValue <= 0.0 || g_tickSize <= 0.0)
   {
      Print("Invalid symbol tick settings.");
      return(INIT_FAILED);
   }

   if(!BuildIndicatorHandles())
   {
      Print("Indicator handle creation failed.");
      return(INIT_FAILED);
   }

   if(!ParseManualNewsWindows())
   {
      Print("Manual news window parsing failed.");
      return(INIT_FAILED);
   }

   for(int sid = STRATEGY_MIN; sid <= STRATEGY_MAX; ++sid)
   {
      g_strategyRiskScaler[sid] = 1.0;
      g_strategyDisabled[sid] = false;
      g_strategyLossStreak[sid] = 0;
      g_strategyPnlCount[sid] = 0;
      g_strategyPnlWriteIndex[sid] = 0;
      for(int j = 0; j < EDGE_BUFFER_SIZE; ++j)
         g_strategyPnlRing[sid][j] = 0.0;
   }

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   g_highWaterEquity = eq;
   g_dayStartEquity = eq;
   g_weekStartEquity = eq;
   g_dayId = CurrentDayId();
   g_weekId = CurrentWeekId();
   g_hardHalt = false;
   g_dailyHalt = false;
   g_weeklyPenalty = false;
   g_gridCooldownUntil = 0;

   if(HistorySelect(TimeTradeServer() - 86400 * 30, TimeTradeServer()))
   {
      int deals = HistoryDealsTotal();
      if(deals > 0)
         g_lastProcessedDeal = HistoryDealGetTicket(deals - 1);
   }

   EventSetTimer(30); // edge-decay + housekeeping interval

   Print("AURIC_MSX_EA initialized for ", _Symbol);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ReleaseHandle(g_hAtrM1);
   ReleaseHandle(g_hAtrM5);
   ReleaseHandle(g_hAtrM15);
   ReleaseHandle(g_hAtrH4);
   ReleaseHandle(g_hAtrD1);
   ReleaseHandle(g_hAdxM5);
   ReleaseHandle(g_hAdxD1);
   ReleaseHandle(g_hEma20M5);
   ReleaseHandle(g_hEma50M5);
   ReleaseHandle(g_hEma100M5);
   ReleaseHandle(g_hEma50D1);
   ReleaseHandle(g_hEma200D1);
   ReleaseHandle(g_hEma20H4);
   ReleaseHandle(g_hBandsM15);
}

void OnTimer()
{
   RefreshRiskState();
   UpdateEdgeDecay();
}

string RegimeLabel(const RegimeType r)
{
   if(r == REGIME_TREND) return "TREND";
   if(r == REGIME_RANGE) return "RANGE";
   return "TRANSITION";
}

void OnTick()
{
   // Spread telemetry for S1 execution quality gating.
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(ask > bid && bid > 0.0)
      UpdateSpreadStats((ask - bid) / _Point);

   RefreshRiskState();
   if(g_hardHalt)
      return;

   MarketContext ctx;
   if(!BuildContext(ctx))
      return;

   bool newM5 = IsNewBar(PERIOD_M5, g_lastBarM5);
   bool newM15 = IsNewBar(PERIOD_M15, g_lastBarM15);
   bool newH4 = IsNewBar(PERIOD_H4, g_lastBarH4);
   IsNewBar(PERIOD_D1, g_lastBarD1);

   StrategySignal s1 = EvaluateS1(ctx);
   StrategySignal s2 = EvaluateS2(ctx);
   StrategySignal s3 = EvaluateS3(ctx);
   StrategySignal s4 = EvaluateS4(ctx);
   StrategySignal s6 = EvaluateS6(ctx);

   if(PrintDiagnosticsInTester && (bool)MQLInfoInteger(MQL_TESTER) && newM5)
   {
      static int diagBarCounter = 0;
      diagBarCounter++;
      int printEvery = MathMax(1, DiagnosticsEveryNBarsM5);
      if((diagBarCounter % printEvery) == 0)
      {
         PrintFormat("AURIC_DIAG regime=%s adx=%.2f ts=%.3f z=%.3f hv=%d spread=%.1f "
                     "S1(v=%.3f L=%d S=%d) S2(v=%.3f L=%d S=%d) S3(v=%.3f L=%d S=%d) "
                     "S4(v=%.3f L=%d S=%d) S6(v=%.3f L=%d S=%d) halted=%d",
                     RegimeLabel(ctx.regime), ctx.adxM5, ctx.trendScore, ctx.zScore, (int)ctx.highVol, ctx.spreadPoints,
                     s1.value, (int)s1.longEntry, (int)s1.shortEntry,
                     s2.value, (int)s2.longEntry, (int)s2.shortEntry,
                     s3.value, (int)s3.longEntry, (int)s3.shortEntry,
                     s4.value, (int)s4.longEntry, (int)s4.shortEntry,
                     s6.value, (int)s6.longEntry, (int)s6.shortEntry,
                     (int)TradingHalted());
      }
   }

   ManageOpenPositions(ctx, s1, s2, s3, s4, s6);
   ManageGrid(ctx);

   TryOpenStrategies(ctx, s1, s2, s3, s4, s6, newM5, newM15, newH4);
}
