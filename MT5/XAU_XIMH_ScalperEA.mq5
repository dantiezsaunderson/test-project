//+------------------------------------------------------------------+
//|                                              XAU_XIMH_ScalperEA  |
//|  Intraday hybrid: mean-reversion + breakout for XAUUSD (MT5)     |
//+------------------------------------------------------------------+
#property strict
#property version   "2.01"
#property description "XAU intraday hybrid scalper: ADX/Hurst regime, VWAP/OFI signals, ATR risk."

#include <Trade/Trade.mqh>

// -------------------- Inputs: execution ----------------------------
input group "Execution"
input string          InpTradeSymbol               = "";       // Blank = chart/tester symbol
input ENUM_TIMEFRAMES InpSignalTF                  = PERIOD_M1;
input ulong           InpMagic                     = 26022026;
input int             InpMaxDeviationPoints        = 40;

// -------------------- Inputs: sessions (UTC) -----------------------
input group "Trading Sessions (UTC)"
input int             InpSession1StartHour         = 6;
input int             InpSession1StartMinute       = 30;
input int             InpSession1EndHour           = 10;
input int             InpSession1EndMinute         = 30;
input int             InpSession2StartHour         = 12;
input int             InpSession2StartMinute       = 30;
input int             InpSession2EndHour           = 16;
input int             InpSession2EndMinute         = 30;
input int             InpServerToUTCOffsetHours    = 0;        // UTC = server - offset

// -------------------- Inputs: feature windows ----------------------
input group "Feature Windows"
input int             InpVWAPLookbackBars          = 20;
input int             InpBreakoutLookbackBars      = 15;
input int             InpATRPeriod                 = 10;
input int             InpADXPeriod                 = 12;
input int             InpHurstLookbackBars         = 48;
input int             InpOfiZLookbackBars          = 16;
input int             InpConfirmBars               = 1;
input int             InpTickFlowWindowSec         = 45;
input int             InpTickFlowKeepSec           = 1200;

// -------------------- Inputs: thresholds ---------------------------
input group "Signal Thresholds"
input double          InpAdxTrendThreshold         = 20.0;
input double          InpHurstTrendThreshold       = 0.50;
input double          InpMRScoreThreshold          = 0.95;
input double          InpMRVwapZThreshold          = 0.85;
input double          InpMRImbalanceThreshold      = 0.08;
input double          InpBOScoreThreshold          = 1.00;
input double          InpBOBreakoutZThreshold      = 0.10;
input double          InpBOOfiZThreshold           = 0.20;
input double          InpBreakoutVolumeMultiplier  = 1.05;

// -------------------- Inputs: exits --------------------------------
input group "Exits (ATR Multipliers)"
input double          InpMRTP_ATR                  = 0.55;
input double          InpMRSL_ATR                  = 0.40;
input int             InpMRTimeStopMin             = 6;
input double          InpBOTP1_ATR                 = 0.70;
input double          InpBOSL_ATR                  = 0.45;
input double          InpBOTrail_ATR               = 0.40;
input int             InpBOTimeStopMin             = 14;
input double          InpBreakoutPartialCloseFrac  = 0.60;

// -------------------- Inputs: sizing/risk --------------------------
input group "Sizing & Risk"
input double          InpBaseRiskPct               = 0.08;     // % equity per trade (base)
input double          InpMaxLossPerTradePct        = 0.12;     // hard cap
input double          InpMaxDailyLossPct           = 1.00;
input double          InpMaxWeeklyLossPct          = 2.00;
input double          InpDrawdownSoftPct           = 6.5;
input double          InpDrawdownHardPct           = 9.0;
input double          InpTargetAtrPct              = 0.10;     // target ATR as % of price
input double          InpMaxLots                   = 1.00;     // absolute cap per trade
input int             InpMinStopDistancePoints     = 80;       // stop floor in points
input bool            InpFlattenOnRiskLock         = true;

// -------------------- Inputs: spread controls ----------------------
input group "Spread / Microstructure Filters"
input int             InpSpreadMedianLookbackBars  = 20;
input double          InpSpreadMultiplierMax       = 1.45;

// -------------------------------------------------------------------
CTrade   g_trade;
string   g_symbol;
int      g_atrHandle = INVALID_HANDLE;
int      g_adxHandle = INVALID_HANDLE;
datetime g_lastSignalBar = 0;
double   g_prevMid = 0.0;

// Signal state
double   g_lastMRScore = 0.0;
double   g_lastBOScoreSigned = 0.0;
bool     g_lastRegimeTrend = false;
int      g_longSignalCount = 0;
int      g_shortSignalCount = 0;

// Position state (single-position design)
ulong    g_activeTicket = 0;
bool     g_activeIsBreakout = false;
double   g_activeEntryATR = 0.0;
double   g_activeInitialVolume = 0.0;
bool     g_activePartialDone = false;

// Risk state
double   g_equityPeak = 0.0;
double   g_dailyStartEquity = 0.0;
double   g_weeklyStartEquity = 0.0;
int      g_lastDayId = -1;
int      g_lastWeekId = -1;
bool     g_dailyLocked = false;
bool     g_weeklyLocked = false;
bool     g_hardLocked = false;

// Histories
double   g_spreadHistory[];
double   g_ofiHistory[];
datetime g_tickTimes[];
double   g_tickSignedVol[];
double   g_tickUpVol[];
double   g_tickDownVol[];

//+------------------------------------------------------------------+
//| Utility: array push with max size                               |
//+------------------------------------------------------------------+
void PushValue(double &arr[], const double value, const int max_size)
{
   int sz = ArraySize(arr);
   ArrayResize(arr, sz + 1);
   arr[sz] = value;
   if(max_size > 0 && ArraySize(arr) > max_size)
   {
      int keep = max_size;
      int from = ArraySize(arr) - keep;
      for(int i = 0; i < keep; ++i)
         arr[i] = arr[from + i];
      ArrayResize(arr, keep);
   }
}

void PushTick(const datetime ts, const double signed_vol, const double up_vol, const double down_vol)
{
   int sz = ArraySize(g_tickTimes);
   ArrayResize(g_tickTimes, sz + 1);
   ArrayResize(g_tickSignedVol, sz + 1);
   ArrayResize(g_tickUpVol, sz + 1);
   ArrayResize(g_tickDownVol, sz + 1);

   g_tickTimes[sz]     = ts;
   g_tickSignedVol[sz] = signed_vol;
   g_tickUpVol[sz]     = up_vol;
   g_tickDownVol[sz]   = down_vol;
}

void PruneTickHistory(const datetime now_ts)
{
   datetime cutoff = now_ts - InpTickFlowKeepSec;
   int sz = ArraySize(g_tickTimes);
   int first_keep = 0;
   while(first_keep < sz && g_tickTimes[first_keep] < cutoff)
      ++first_keep;

   if(first_keep <= 0)
      return;
   if(first_keep >= sz)
   {
      ArrayResize(g_tickTimes, 0);
      ArrayResize(g_tickSignedVol, 0);
      ArrayResize(g_tickUpVol, 0);
      ArrayResize(g_tickDownVol, 0);
      return;
   }

   int keep = sz - first_keep;
   for(int i = 0; i < keep; ++i)
   {
      g_tickTimes[i]     = g_tickTimes[first_keep + i];
      g_tickSignedVol[i] = g_tickSignedVol[first_keep + i];
      g_tickUpVol[i]     = g_tickUpVol[first_keep + i];
      g_tickDownVol[i]   = g_tickDownVol[first_keep + i];
   }
   ArrayResize(g_tickTimes, keep);
   ArrayResize(g_tickSignedVol, keep);
   ArrayResize(g_tickUpVol, keep);
   ArrayResize(g_tickDownVol, keep);
}

double Clamp(const double x, const double lo, const double hi)
{
   if(x < lo) return lo;
   if(x > hi) return hi;
   return x;
}

int VolumeDigits()
{
   double step = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);
   int digits = 0;
   while(digits < 8)
   {
      double scaled = step * MathPow(10.0, digits);
      if(MathAbs(scaled - MathRound(scaled)) < 1e-8)
         break;
      ++digits;
   }
   return digits;
}

double NormalizeLots(double lots)
{
   double min_vol = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   double max_vol = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
   double step    = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);
   int digits     = VolumeDigits();
   if(step <= 0.0)
      return NormalizeDouble(MathMax(min_vol, MathMin(max_vol, lots)), digits);

   lots = MathMax(min_vol, MathMin(max_vol, lots));
   lots = MathFloor(lots / step) * step;
   lots = NormalizeDouble(lots, digits);
   return lots;
}

double MeanTail(const double &arr[], const int tail_count)
{
   int sz = ArraySize(arr);
   if(sz <= 0) return 0.0;
   int n = MathMin(sz, tail_count);
   int start = sz - n;
   double sum = 0.0;
   for(int i = start; i < sz; ++i) sum += arr[i];
   return sum / (double)n;
}

double StdDevTail(const double &arr[], const int tail_count, const double mean)
{
   int sz = ArraySize(arr);
   if(sz <= 1) return 0.0;
   int n = MathMin(sz, tail_count);
   if(n <= 1) return 0.0;
   int start = sz - n;
   double s2 = 0.0;
   for(int i = start; i < sz; ++i)
   {
      double d = arr[i] - mean;
      s2 += d * d;
   }
   return MathSqrt(s2 / (double)(n - 1));
}

double MedianTail(const double &arr[], const int tail_count)
{
   int sz = ArraySize(arr);
   if(sz <= 0) return 0.0;
   int n = MathMin(sz, tail_count);
   if(n <= 0) return 0.0;
   int start = sz - n;

   double tmp[];
   ArrayResize(tmp, n);
   for(int i = 0; i < n; ++i)
      tmp[i] = arr[start + i];
   ArraySort(tmp);

   if((n % 2) == 1)
      return tmp[n / 2];
   return 0.5 * (tmp[n / 2 - 1] + tmp[n / 2]);
}

double ZScoreFromHistory(const double value, const double &history[], const int lookback)
{
   if(ArraySize(history) < MathMax(5, lookback / 2))
      return 0.0;
   double m = MeanTail(history, lookback);
   double s = StdDevTail(history, lookback, m);
   if(s <= 1e-10)
      return 0.0;
   return (value - m) / s;
}

double CurrentSpreadPoints()
{
   double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   double pt  = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   if(pt <= 0.0) return 0.0;
   return (ask - bid) / pt;
}

bool SpreadFilterPass(const double spread_points)
{
   int min_hist = MathMax(5, InpSpreadMedianLookbackBars / 2);
   if(ArraySize(g_spreadHistory) < min_hist)
      return true;
   double med = MedianTail(g_spreadHistory, InpSpreadMedianLookbackBars);
   if(med <= 0.0)
      return true;
   return (spread_points <= InpSpreadMultiplierMax * med);
}

//+------------------------------------------------------------------+
//| Time/session helpers                                              |
//+------------------------------------------------------------------+
int DayIdUTC(const datetime ts_gmt)
{
   MqlDateTime t;
   TimeToStruct(ts_gmt, t);
   return t.year * 1000 + t.day_of_year;
}

int WeekIdUTC(const datetime ts_gmt)
{
   MqlDateTime t;
   TimeToStruct(ts_gmt, t);
   return t.year * 100 + (t.day_of_year / 7);
}

int MinuteOfDayUTC(const datetime ts_gmt)
{
   MqlDateTime t;
   TimeToStruct(ts_gmt, t);
   return t.hour * 60 + t.min;
}

bool InWindowMinute(const int now_minute, const int start_minute, const int end_minute)
{
   if(start_minute <= end_minute)
      return (now_minute >= start_minute && now_minute <= end_minute);
   return (now_minute >= start_minute || now_minute <= end_minute); // Wrap midnight
}

datetime ServerToUTC(const datetime ts_server)
{
   return ts_server - (InpServerToUTCOffsetHours * 3600);
}

bool InTradingSessionUTC(const datetime now_gmt)
{
   int m = MinuteOfDayUTC(now_gmt);
   int s1 = InpSession1StartHour * 60 + InpSession1StartMinute;
   int e1 = InpSession1EndHour * 60 + InpSession1EndMinute;
   int s2 = InpSession2StartHour * 60 + InpSession2StartMinute;
   int e2 = InpSession2EndHour * 60 + InpSession2EndMinute;
   return InWindowMinute(m, s1, e1) || InWindowMinute(m, s2, e2);
}

//+------------------------------------------------------------------+
//| Position helpers                                                  |
//+------------------------------------------------------------------+
bool GetOurPosition(ulong &ticket,
                    long &type,
                    double &volume,
                    double &price_open,
                    datetime &time_open,
                    double &sl,
                    double &tp,
                    string &comment)
{
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; --i)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk))
         continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      long mgc   = PositionGetInteger(POSITION_MAGIC);
      if(sym == g_symbol && (ulong)mgc == InpMagic)
      {
         ticket     = tk;
         type       = PositionGetInteger(POSITION_TYPE);
         volume     = PositionGetDouble(POSITION_VOLUME);
         price_open = PositionGetDouble(POSITION_PRICE_OPEN);
         time_open  = (datetime)PositionGetInteger(POSITION_TIME);
         sl         = PositionGetDouble(POSITION_SL);
         tp         = PositionGetDouble(POSITION_TP);
         comment    = PositionGetString(POSITION_COMMENT);
         return true;
      }
   }
   return false;
}

void ResetActiveState()
{
   g_activeTicket = 0;
   g_activeIsBreakout = false;
   g_activeEntryATR = 0.0;
   g_activeInitialVolume = 0.0;
   g_activePartialDone = false;
}

void SyncActiveStateWithPosition()
{
   ulong tk; long type; double vol, openp, sl, tp; datetime opent; string cmt;
   if(!GetOurPosition(tk, type, vol, openp, opent, sl, tp, cmt))
   {
      ResetActiveState();
      return;
   }

   if(g_activeTicket != tk)
   {
      g_activeTicket = tk;
      g_activeIsBreakout = (StringFind(cmt, "_BO_") >= 0);
      g_activeEntryATR = 0.0;
      g_activeInitialVolume = vol;
      g_activePartialDone = false;
   }
}

bool CloseOurPosition(const string reason)
{
   bool ok = g_trade.PositionClose(g_symbol, InpMaxDeviationPoints);
   if(ok)
      PrintFormat("Position closed: %s", reason);
   else
      PrintFormat("Failed close (%s): %s", reason, g_trade.ResultRetcodeDescription());
   return ok;
}

bool ReducePositionByVolume(const bool is_buy_position, const double close_volume)
{
   if(close_volume <= 0.0)
      return false;

   bool ok = g_trade.PositionClosePartial(g_symbol, close_volume, InpMaxDeviationPoints);
   if(ok)
      return true;

   // Fallback for accounts/brokers where PositionClosePartial is not accepted.
   if(is_buy_position)
      ok = g_trade.Sell(close_volume, g_symbol, 0.0, 0.0, 0.0, "XIMH_PARTIAL");
   else
      ok = g_trade.Buy(close_volume, g_symbol, 0.0, 0.0, 0.0, "XIMH_PARTIAL");

   return ok;
}

//+------------------------------------------------------------------+
//| Indicators/features                                               |
//+------------------------------------------------------------------+
double GetIndicatorValue(const int handle, const int buffer, const int shift)
{
   double vals[];
   if(CopyBuffer(handle, buffer, shift, 1, vals) != 1)
      return 0.0;
   return vals[0];
}

double ComputeVWAP(const MqlRates &rates[], const int start_idx, const int bars)
{
   double sum_pv = 0.0;
   double sum_v  = 0.0;
   for(int i = start_idx; i < start_idx + bars; ++i)
   {
      double px = rates[i].close;
      double v  = (double)rates[i].tick_volume;
      sum_pv += px * v;
      sum_v  += v;
   }
   if(sum_v <= 0.0)
      return rates[start_idx].close;
   return sum_pv / sum_v;
}

double HighestHigh(const MqlRates &rates[], const int start_idx, const int bars)
{
   double hh = rates[start_idx].high;
   for(int i = start_idx + 1; i < start_idx + bars; ++i)
      if(rates[i].high > hh) hh = rates[i].high;
   return hh;
}

double LowestLow(const MqlRates &rates[], const int start_idx, const int bars)
{
   double ll = rates[start_idx].low;
   for(int i = start_idx + 1; i < start_idx + bars; ++i)
      if(rates[i].low < ll) ll = rates[i].low;
   return ll;
}

double MedianTickVolume(const MqlRates &rates[], const int start_idx, const int bars)
{
   int n = bars;
   if(n <= 0) return 0.0;
   double tmp[];
   ArrayResize(tmp, n);
   for(int i = 0; i < n; ++i)
      tmp[i] = (double)rates[start_idx + i].tick_volume;
   ArraySort(tmp);
   if((n % 2) == 1)
      return tmp[n / 2];
   return 0.5 * (tmp[n / 2 - 1] + tmp[n / 2]);
}

double ComputeZMomentum(const MqlRates &rates[], const int start_idx, const int ret_count)
{
   if(ret_count <= 0)
      return 0.0;
   double sum_r = 0.0;
   double sum_r2 = 0.0;
   for(int i = 0; i < ret_count; ++i)
   {
      double c0 = rates[start_idx + i].close;
      double c1 = rates[start_idx + i + 1].close;
      if(c0 <= 0.0 || c1 <= 0.0)
         continue;
      double r = MathLog(c0 / c1);
      sum_r  += r;
      sum_r2 += r * r;
   }
   double sigma = MathSqrt(sum_r2);
   if(sigma <= 1e-10)
      return 0.0;
   return sum_r / sigma;
}

double StdDevArray(const double &arr[])
{
   int n = ArraySize(arr);
   if(n <= 1) return 0.0;
   double m = 0.0;
   for(int i = 0; i < n; ++i) m += arr[i];
   m /= (double)n;
   double s2 = 0.0;
   for(int i = 0; i < n; ++i)
   {
      double d = arr[i] - m;
      s2 += d * d;
   }
   return MathSqrt(s2 / (double)(n - 1));
}

double ComputeHurst(const MqlRates &rates[], const int start_idx, const int lookback)
{
   if(lookback < 30)
      return 0.5;

   double data[];
   ArrayResize(data, lookback);
   for(int i = 0; i < lookback; ++i)
      data[i] = rates[start_idx + (lookback - 1 - i)].close; // oldest -> newest

   int max_lag = MathMin(20, lookback / 2);
   if(max_lag < 5)
      return 0.5;

   double sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
   int used = 0;
   for(int lag = 2; lag <= max_lag; ++lag)
   {
      int n = lookback - lag;
      if(n < 10)
         continue;
      double diff[];
      ArrayResize(diff, n);
      for(int i = 0; i < n; ++i)
         diff[i] = data[i + lag] - data[i];
      double sd = StdDevArray(diff);
      if(sd <= 1e-10)
         continue;
      double tau = MathSqrt(sd);
      if(tau <= 1e-10)
         continue;
      double x = MathLog((double)lag);
      double y = MathLog(tau);
      sx += x; sy += y; sxx += x * x; sxy += x * y;
      ++used;
   }

   if(used < 4)
      return 0.5;

   double denom = (used * sxx - sx * sx);
   if(MathAbs(denom) < 1e-10)
      return 0.5;
   double slope = (used * sxy - sx * sy) / denom;
   double hurst = 2.0 * slope;
   return Clamp(hurst, 0.0, 1.0);
}

void ComputeOFIAndImbalance(const datetime now_ts, const int window_sec, double &ofi, double &imb)
{
   ofi = 0.0;
   double up = 0.0, down = 0.0;
   datetime cutoff = now_ts - window_sec;

   int sz = ArraySize(g_tickTimes);
   for(int i = sz - 1; i >= 0; --i)
   {
      if(g_tickTimes[i] < cutoff)
         break;
      ofi += g_tickSignedVol[i];
      up += g_tickUpVol[i];
      down += g_tickDownVol[i];
   }
   double denom = up + down;
   imb = (denom > 1e-10) ? ((up - down) / denom) : 0.0;
}

//+------------------------------------------------------------------+
//| Risk engine                                                       |
//+------------------------------------------------------------------+
void UpdateRiskAnchors()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   datetime now_ts = TimeCurrent();
   int day_id = DayIdUTC(now_ts);
   int week_id = WeekIdUTC(now_ts);

   if(g_lastDayId != day_id)
   {
      g_lastDayId = day_id;
      g_dailyStartEquity = eq;
      g_dailyLocked = false;
   }

   if(g_lastWeekId != week_id)
   {
      g_lastWeekId = week_id;
      g_weeklyStartEquity = eq;
      g_weeklyLocked = false;
   }

   if(eq > g_equityPeak || g_equityPeak <= 0.0)
      g_equityPeak = eq;

   if(g_dailyStartEquity > 0.0)
   {
      double daily_loss_pct = 100.0 * (g_dailyStartEquity - eq) / g_dailyStartEquity;
      if(daily_loss_pct >= InpMaxDailyLossPct)
         g_dailyLocked = true;
   }

   if(g_weeklyStartEquity > 0.0)
   {
      double weekly_loss_pct = 100.0 * (g_weeklyStartEquity - eq) / g_weeklyStartEquity;
      if(weekly_loss_pct >= InpMaxWeeklyLossPct)
         g_weeklyLocked = true;
   }

   if(g_equityPeak > 0.0)
   {
      double dd_pct = 100.0 * (g_equityPeak - eq) / g_equityPeak;
      if(dd_pct >= InpDrawdownHardPct)
         g_hardLocked = true;
   }
}

bool IsRiskLocked()
{
   return (g_dailyLocked || g_weeklyLocked || g_hardLocked);
}

double RiskPerLotByStop(const int direction, const double entry_price, const double stop_price)
{
   if((direction != 1 && direction != -1) || entry_price <= 0.0 || stop_price <= 0.0)
      return 0.0;

   double pnl = 0.0;
   bool calc_ok = false;
   if(direction > 0)
      calc_ok = OrderCalcProfit(ORDER_TYPE_BUY, g_symbol, 1.0, entry_price, stop_price, pnl);
   else
      calc_ok = OrderCalcProfit(ORDER_TYPE_SELL, g_symbol, 1.0, entry_price, stop_price, pnl);

   if(calc_ok && MathAbs(pnl) > 1e-10)
      return MathAbs(pnl);

   // Fallback for brokers where OrderCalcProfit can fail for synthetic symbols.
   double tick_size  = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tick_value <= 0.0)
      tick_value = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE_PROFIT);
   if(tick_value <= 0.0)
      tick_value = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick_size <= 0.0 || tick_value <= 0.0)
      return 0.0;

   return MathAbs(entry_price - stop_price) / tick_size * tick_value;
}

double DrawdownThrottle()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_equityPeak <= 0.0 || eq <= 0.0)
      return 1.0;
   double dd = 100.0 * (g_equityPeak - eq) / g_equityPeak;
   return MathMax(0.25, 1.0 - dd / MathMax(0.1, InpDrawdownSoftPct));
}

double VolatilityThrottle(const double atr, const double mid_price)
{
   if(mid_price <= 0.0 || atr <= 0.0)
      return 1.0;
   double atr_pct = (atr / mid_price) * 100.0;
   if(atr_pct <= 1e-10)
      return 1.0;
   return MathMin(1.0, InpTargetAtrPct / atr_pct);
}

double CalculatePositionSize(const int direction,
                             const double entry_price,
                             const double stop_price,
                             const double conviction,
                             const double atr,
                             const double mid_price)
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq <= 0.0 || entry_price <= 0.0 || stop_price <= 0.0)
      return 0.0;

   double base_risk_amt = eq * (InpBaseRiskPct / 100.0);
   double conviction_mult = Clamp(conviction / 1.2, 0.5, 1.5);
   double dd_mult = DrawdownThrottle();
   double vol_mult = VolatilityThrottle(atr, mid_price);
   double risk_amt = base_risk_amt * conviction_mult * dd_mult * vol_mult;

   double risk_per_lot = RiskPerLotByStop(direction, entry_price, stop_price);
   if(risk_per_lot <= 0.0)
      return 0.0;

   double lots = risk_amt / risk_per_lot;

   // Per-trade hard cap
   double max_trade_risk_amt = eq * (InpMaxLossPerTradePct / 100.0);
   double est_risk = lots * risk_per_lot;
   if(est_risk > max_trade_risk_amt && est_risk > 0.0)
      lots *= (max_trade_risk_amt / est_risk);

   if(InpMaxLots > 0.0)
      lots = MathMin(lots, InpMaxLots);

   return NormalizeLots(lots);
}

//+------------------------------------------------------------------+
//| Entry/execution                                                   |
//+------------------------------------------------------------------+
bool TryOpenTrade(const int direction, const bool trend_regime, const double atr, const double conviction_score)
{
   if(IsRiskLocked())
      return false;

   if(direction != 1 && direction != -1)
      return false;

   double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   double mid = 0.5 * (ask + bid);
   double pt  = SymbolInfoDouble(g_symbol, SYMBOL_POINT);

   if(ask <= 0.0 || bid <= 0.0 || atr <= 0.0 || pt <= 0.0)
      return false;

   double stop_mult = trend_regime ? InpBOSL_ATR : InpMRSL_ATR;
   double stop_dist = stop_mult * atr;
   double min_stop_dist = InpMinStopDistancePoints * pt;
   if(min_stop_dist > 0.0)
      stop_dist = MathMax(stop_dist, min_stop_dist);
   if(stop_dist <= 0.0)
      return false;

   int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);

   double sl = 0.0;
   double tp = 0.0;
   string regime = trend_regime ? "BO" : "MR";
   string side = (direction > 0) ? "L" : "S";
   string comment = StringFormat("XIMH_%s_%s", regime, side);

   if(direction > 0)
   {
      sl = NormalizeDouble(ask - stop_dist, digits);
      sl = NormalizeStopForBroker(true, sl);
      if(!trend_regime)
         tp = NormalizeDouble(ask + InpMRTP_ATR * atr, digits);
   }
   else
   {
      sl = NormalizeDouble(bid + stop_dist, digits);
      sl = NormalizeStopForBroker(false, sl);
      if(!trend_regime)
         tp = NormalizeDouble(bid - InpMRTP_ATR * atr, digits);
   }

   double entry_price = (direction > 0) ? ask : bid;
   double lots = CalculatePositionSize(direction, entry_price, sl, MathAbs(conviction_score), atr, mid);
   double min_vol = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   if(lots < min_vol)
      return false;
   double risk_per_lot = RiskPerLotByStop(direction, entry_price, sl);
   double est_risk_cash = lots * risk_per_lot;

   bool ok = false;
   if(direction > 0)
      ok = g_trade.Buy(lots, g_symbol, 0.0, sl, tp, comment);
   else
      ok = g_trade.Sell(lots, g_symbol, 0.0, sl, tp, comment);

   if(!ok)
   {
      PrintFormat("Entry failed: %s", g_trade.ResultRetcodeDescription());
      return false;
   }

   SyncActiveStateWithPosition();
   g_activeIsBreakout = trend_regime;
   g_activeEntryATR = atr;
   g_activeInitialVolume = lots;
   g_activePartialDone = false;
   g_longSignalCount = 0;
   g_shortSignalCount = 0;

   PrintFormat("Opened %s %s %.2f lots | ATR=%.3f | estRisk=%.2f",
               g_symbol, comment, lots, atr, est_risk_cash);
   return true;
}

double NormalizeStopForBroker(const bool is_buy, const double desired_sl)
{
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   double pt  = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   int stops_level = (int)SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double min_dist = stops_level * pt;

   double sl = desired_sl;
   if(is_buy)
   {
      double max_sl = bid - min_dist;
      if(sl > max_sl)
         sl = max_sl;
   }
   else
   {
      double min_sl = ask + min_dist;
      if(sl < min_sl)
         sl = min_sl;
   }
   return NormalizeDouble(sl, digits);
}

void HandleBreakoutPartialAndTrail(const bool is_buy,
                                   const double price_open,
                                   const double volume,
                                   const double current_sl,
                                   const double current_tp)
{
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   double px = is_buy ? bid : ask;

   double entry_atr = g_activeEntryATR;
   if(entry_atr <= 0.0)
      entry_atr = GetIndicatorValue(g_atrHandle, 0, 1);
   if(entry_atr <= 0.0)
      return;

   double move = is_buy ? (px - price_open) : (price_open - px);

   // TP1 partial close at +0.8 ATR from entry
   double tp1_dist = InpBOTP1_ATR * entry_atr;
   if(!g_activePartialDone && move >= tp1_dist)
   {
      double close_vol = NormalizeLots(volume * InpBreakoutPartialCloseFrac);
      double min_vol = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
      if(close_vol >= min_vol && close_vol < volume)
      {
         bool ok = ReducePositionByVolume(is_buy, close_vol);
         if(ok)
         {
            g_activePartialDone = true;
            PrintFormat("Breakout TP1 partial closed %.2f lots", close_vol);
         }
         else
         {
            PrintFormat("Partial close failed: %s", g_trade.ResultRetcodeDescription());
         }
      }
      else
      {
         g_activePartialDone = true; // Volume too small to split; move directly to trailing
      }
   }

   // Trailing stop after TP1
   if(g_activePartialDone)
   {
      double atr = GetIndicatorValue(g_atrHandle, 0, 1);
      if(atr <= 0.0)
         atr = entry_atr;
      double trail_dist = InpBOTrail_ATR * atr;
      double desired_sl = is_buy ? (bid - trail_dist) : (ask + trail_dist);
      desired_sl = NormalizeStopForBroker(is_buy, desired_sl);

      bool should_modify = false;
      if(is_buy)
      {
         if(current_sl <= 0.0 || desired_sl > current_sl)
            should_modify = true;
      }
      else
      {
         if(current_sl <= 0.0 || desired_sl < current_sl)
            should_modify = true;
      }

      if(should_modify)
      {
         bool ok = g_trade.PositionModify(g_symbol, desired_sl, current_tp);
         if(!ok)
            PrintFormat("Trailing modify failed: %s", g_trade.ResultRetcodeDescription());
      }
   }
}

void ManageOpenPosition()
{
   ulong tk; long type; double vol, openp, sl, tp; datetime opent; string cmt;
   if(!GetOurPosition(tk, type, vol, openp, opent, sl, tp, cmt))
   {
      ResetActiveState();
      return;
   }

   SyncActiveStateWithPosition();

   bool is_buy = (type == POSITION_TYPE_BUY);
   bool is_breakout = (StringFind(cmt, "_BO_") >= 0);
   bool is_mr = !is_breakout;
   int mins_open = (int)((TimeCurrent() - opent) / 60);

   if(IsRiskLocked() && InpFlattenOnRiskLock)
   {
      CloseOurPosition("Risk lock");
      return;
   }

   if(is_mr)
   {
      if(mins_open >= InpMRTimeStopMin)
      {
         CloseOurPosition("MR time stop");
         return;
      }
      if((is_buy && g_lastMRScore < 0.0) || (!is_buy && g_lastMRScore > 0.0))
      {
         CloseOurPosition("MR signal reversal");
         return;
      }
   }
   else
   {
      if(mins_open >= InpBOTimeStopMin)
      {
         CloseOurPosition("BO time stop");
         return;
      }
      if((is_buy && g_lastBOScoreSigned < 0.0) || (!is_buy && g_lastBOScoreSigned > 0.0))
      {
         CloseOurPosition("BO signal reversal");
         return;
      }
      HandleBreakoutPartialAndTrail(is_buy, openp, vol, sl, tp);
   }
}

//+------------------------------------------------------------------+
//| New-bar signal evaluation                                         |
//+------------------------------------------------------------------+
void UpdateSignalStreaks(const bool raw_long, const bool raw_short)
{
   if(raw_long && !raw_short)
   {
      g_longSignalCount++;
      g_shortSignalCount = 0;
   }
   else if(raw_short && !raw_long)
   {
      g_shortSignalCount++;
      g_longSignalCount = 0;
   }
   else
   {
      g_longSignalCount = 0;
      g_shortSignalCount = 0;
   }
}

void EvaluateSignalsOnNewBar()
{
   UpdateRiskAnchors();

   // Keep spread history
   double spread_pts = CurrentSpreadPoints();
   PushValue(g_spreadHistory, spread_pts, MathMax(60, InpSpreadMedianLookbackBars * 3));

   int need_bars = MathMax(MathMax(InpVWAPLookbackBars, InpBreakoutLookbackBars),
                           MathMax(InpHurstLookbackBars, 25)) + 10;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(g_symbol, InpSignalTF, 0, need_bars, rates);
   if(copied < need_bars)
      return;

   double atr = GetIndicatorValue(g_atrHandle, 0, 1);
   double adx = GetIndicatorValue(g_adxHandle, 0, 1);
   if(atr <= 0.0 || adx <= 0.0)
      return;

   double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   double mid = 0.5 * (ask + bid);
   if(mid <= 0.0)
      return;

   double vwap = ComputeVWAP(rates, 1, InpVWAPLookbackBars);
   double z_vwap = (mid - vwap) / atr;

   double ofi = 0.0, imb = 0.0;
   ComputeOFIAndImbalance(TimeCurrent(), InpTickFlowWindowSec, ofi, imb);
   double z_ofi = ZScoreFromHistory(ofi, g_ofiHistory, InpOfiZLookbackBars);
   PushValue(g_ofiHistory, ofi, MathMax(120, InpOfiZLookbackBars * 6));

   double z_mom = ComputeZMomentum(rates, 1, 4);
   double hh = HighestHigh(rates, 1, InpBreakoutLookbackBars);
   double ll = LowestLow(rates, 1, InpBreakoutLookbackBars);
   double z_brk_pos = (mid - hh) / atr;
   double z_brk_neg = (ll - mid) / atr; // positive when breaking below low

   double hurst = ComputeHurst(rates, 1, InpHurstLookbackBars);
   bool trend_regime = (adx > InpAdxTrendThreshold && hurst > InpHurstTrendThreshold);

   double vol_med_20 = MedianTickVolume(rates, 1, 20);
   double bar_vol = (double)rates[1].tick_volume;
   bool volume_ok = (vol_med_20 <= 0.0) ? true : (bar_vol > InpBreakoutVolumeMultiplier * vol_med_20);

   double score_mr = (-0.50 * z_vwap) + (0.30 * z_ofi) + (0.20 * imb);
   double score_bo_long  = (0.50 * z_mom) + (0.30 * z_ofi) + (0.20 * z_brk_pos);
   double score_bo_short = (0.50 * (-z_mom)) + (0.30 * (-z_ofi)) + (0.20 * z_brk_neg);
   double score_bo_signed = score_bo_long - score_bo_short;

   g_lastMRScore = score_mr;
   g_lastBOScoreSigned = score_bo_signed;
   g_lastRegimeTrend = trend_regime;

   bool raw_long = false;
   bool raw_short = false;

   if(trend_regime)
   {
      raw_long  = (score_bo_long > InpBOScoreThreshold &&
                   z_brk_pos > InpBOBreakoutZThreshold &&
                   z_ofi > InpBOOfiZThreshold &&
                   volume_ok);
      raw_short = (score_bo_short > InpBOScoreThreshold &&
                   z_brk_neg > InpBOBreakoutZThreshold &&
                   z_ofi < -InpBOOfiZThreshold &&
                   volume_ok);
   }
   else
   {
      raw_long  = (score_mr > InpMRScoreThreshold &&
                   z_vwap < -InpMRVwapZThreshold &&
                   imb > InpMRImbalanceThreshold);
      raw_short = (score_mr < -InpMRScoreThreshold &&
                   z_vwap > InpMRVwapZThreshold &&
                   imb < -InpMRImbalanceThreshold);
   }

   datetime bar_utc = ServerToUTC(rates[1].time);
   bool preconditions =
      InTradingSessionUTC(bar_utc) &&
      SpreadFilterPass(spread_pts) &&
      !IsRiskLocked();

   if(!preconditions)
   {
      raw_long = false;
      raw_short = false;
   }

   UpdateSignalStreaks(raw_long, raw_short);

   // One position at a time for this EA/symbol
   ulong tk; long type; double vol, openp, sl, tp; datetime opent; string cmt;
   if(GetOurPosition(tk, type, vol, openp, opent, sl, tp, cmt))
      return;

   if(g_longSignalCount >= InpConfirmBars && !raw_short)
   {
      double conviction = trend_regime ? score_bo_long : score_mr;
      TryOpenTrade(+1, trend_regime, atr, conviction);
   }
   else if(g_shortSignalCount >= InpConfirmBars && !raw_long)
   {
      double conviction = trend_regime ? score_bo_short : -score_mr;
      TryOpenTrade(-1, trend_regime, atr, conviction);
   }
}

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   g_symbol = (StringLen(InpTradeSymbol) > 0) ? InpTradeSymbol : _Symbol;

   if(!SymbolSelect(g_symbol, true))
   {
      PrintFormat("Failed to select symbol %s", g_symbol);
      return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpMaxDeviationPoints);

   g_atrHandle = iATR(g_symbol, InpSignalTF, InpATRPeriod);
   g_adxHandle = iADX(g_symbol, InpSignalTF, InpADXPeriod);
   if(g_atrHandle == INVALID_HANDLE || g_adxHandle == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles");
      return INIT_FAILED;
   }

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   datetime now_ts = TimeCurrent();
   g_equityPeak = eq;
   g_dailyStartEquity = eq;
   g_weeklyStartEquity = eq;
   g_lastDayId = DayIdUTC(now_ts);
   g_lastWeekId = WeekIdUTC(now_ts);

   g_lastSignalBar = iTime(g_symbol, InpSignalTF, 0);
   SyncActiveStateWithPosition();

   PrintFormat("Initialized %s on %s TF=%s",
               MQLInfoString(MQL_PROGRAM_NAME),
               g_symbol,
               EnumToString(InpSignalTF));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if(g_adxHandle != INVALID_HANDLE) IndicatorRelease(g_adxHandle);
}

//+------------------------------------------------------------------+
//| Expert tick                                                       |
//+------------------------------------------------------------------+
void OnTick()
{
   MqlTick tk;
   if(!SymbolInfoTick(g_symbol, tk))
      return;

   double mid = 0.5 * (tk.bid + tk.ask);
   if(mid > 0.0 && g_prevMid > 0.0)
   {
      int dir = 0;
      if(mid > g_prevMid) dir = 1;
      else if(mid < g_prevMid) dir = -1;

      double vol = (tk.volume_real > 0.0) ? tk.volume_real : (double)tk.volume;
      if(vol <= 0.0) vol = 1.0;

      double up = 0.0, down = 0.0, signedv = 0.0;
      if(dir > 0)
      {
         up = vol;
         signedv = vol;
      }
      else if(dir < 0)
      {
         down = vol;
         signedv = -vol;
      }
      PushTick(tk.time, signedv, up, down);
      PruneTickHistory(tk.time);
   }
   g_prevMid = mid;

   UpdateRiskAnchors();
   ManageOpenPosition();

   datetime bar_time = iTime(g_symbol, InpSignalTF, 0);
   if(bar_time > 0 && bar_time != g_lastSignalBar)
   {
      g_lastSignalBar = bar_time;
      EvaluateSignalsOnNewBar();
   }
}

//+------------------------------------------------------------------+
//| Custom optimization criterion for MT5 tester                      |
//+------------------------------------------------------------------+
double OnTester()
{
   double profit = TesterStatistics(STAT_PROFIT);
   double dd_abs = TesterStatistics(STAT_BALANCE_DD);
   double pf = TesterStatistics(STAT_PROFIT_FACTOR);
   double trades = TesterStatistics(STAT_TRADES);

   // Reject unstable parameter sets early.
   if(trades < 80.0)
      return -1.0e9 + trades;
   if(profit <= 0.0 || pf <= 0.0)
      return -1.0e8 + profit;

   if(dd_abs <= 0.0)
      dd_abs = 1.0;

   // Reward profit and quality while penalizing deep drawdown.
   double trade_weight = MathMin(1.5, trades / 200.0);
   return (profit / dd_abs) * pf * trade_weight;
}
//+------------------------------------------------------------------+
