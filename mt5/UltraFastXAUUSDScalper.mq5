#property strict
#property version   "1.31"
#property description "Ultra-fast XAUUSD scalper template with live-account risk controls."

#include <Trade/Trade.mqh>

enum ExecutionMode
{
   EXEC_MODE_STANDARD = 0,
   EXEC_MODE_ECN_LOW_SPREAD = 1
};

input group "Core"
input string InpTradeSymbol                = "XAUUSD";
input ENUM_TIMEFRAMES InpSignalTF          = PERIOD_M1;
input long InpMagicNumber                  = 2026021601;

input group "Symbol Discovery"
input bool InpAutoDetectSymbolSuffix       = true;
input string InpAutoDetectBaseSymbol       = "XAUUSD";
input bool InpSearchAllBrokerSymbols       = true;

input group "Execution Filters"
input double InpMaxSpreadPoints            = 45.0;
input int InpMaxSlippagePoints             = 18;
input int InpCooldownSeconds               = 5;
input int InpTickRateWindowSeconds         = 2;
input int InpMinTicksInWindow              = 4;
input bool InpEnableSessionFilter          = true;
input int InpSessionStartHour              = 6;
input int InpSessionEndHour                = 23;

input group "Execution Profile"
input ExecutionMode InpExecutionMode       = EXEC_MODE_STANDARD;
input double InpECNMaxSpreadPoints         = 22.0;
input int InpECNMaxSlippagePoints          = 8;
input int InpECNCooldownSeconds            = 3;
input int InpECNMinTicksInWindow           = 8;
input bool InpECNSendStopsAfterFill        = true;

input group "Signal Model"
input int InpFastEMAPeriod                 = 8;
input int InpSlowEMAPeriod                 = 21;
input int InpRSIPeriod                     = 8;
input double InpRSIOverbought              = 72.0;
input double InpRSIOversold                = 28.0;
input double InpMinEMAGapPoints            = 5.0;
input int InpBreakoutLookbackBars          = 8;
input double InpMinVolumeImpulse           = 1.03;
input double InpMinImpulseBodyPercent      = 45.0;
input double InpMinImpulseRangePoints      = 15.0;
input bool InpEnablePullbackEntry          = true;
input double InpPullbackATRDistance        = 0.22;
input int InpATRPeriod                     = 14;
input double InpSL_ATRMultiplier           = 0.85;
input double InpTP_ATRMultiplier           = 1.20;
input double InpMinStopPoints              = 80.0;
input double InpMinTargetPoints            = 80.0;

input group "Regime Filters"
input bool InpEnableRegimeFilter           = true;
input double InpMinATRPoints               = 40.0;
input double InpMaxATRPoints               = 900.0;
input int InpSpreadRankLookbackTicks       = 120;
input double InpMaxSpreadRankPercentile    = 0.80;
input double InpSpreadToATRMaxRatio        = 0.40;

input group "Position Management"
input int InpMaxHoldingSeconds             = 180;
input bool InpUseAdaptiveTimeStop          = true;
input int InpLowVolHoldingSeconds          = 240;
input int InpNormalVolHoldingSeconds       = 180;
input int InpHighVolHoldingSeconds         = 90;
input double InpLowVolATRPoints            = 130.0;
input double InpHighVolATRPoints           = 280.0;
input bool InpCloseOnOppositeSignal        = true;
input bool InpEnablePartialTP              = true;
input double InpPartialCloseAtRR           = 1.00;
input double InpPartialClosePercent        = 0.50;
input double InpBreakevenTriggerATR        = 0.45;
input double InpBreakevenOffsetPoints      = 10.0;
input double InpTrailingATRMultiplier      = 0.55;
input bool InpTightenTrailAfter1R          = true;
input double InpTightTrailATRMultiplier    = 0.35;
input double InpPostPartialTrailATRMultiplier = 0.30;

input group "Risk Controls"
input bool InpUseRiskPercent               = true;
input double InpRiskPercent                = 0.30;
input double InpFixedLot                   = 0.01;
input double InpDailyLossLimitPercent      = 2.50;
input int InpMaxConsecutiveLosses          = 4;

input group "Diagnostics"
input bool InpEnableDiagnostics            = true;
input int InpDiagnosticsPrintIntervalSeconds = 300;

input group "Optimization"
input bool InpUseCustomTesterScore         = true;
input int InpMinTradesForTesterScore       = 120;
input double InpTargetProfitFactor         = 1.20;
input double InpMaxBalanceDDPctForScore    = 15.0;

// Keep this buffer compact for speed while still covering short windows.
#define TICK_BUFFER_SIZE 1024
#define SPREAD_BUFFER_SIZE 512
#define BLOCK_REASON_TOTAL 7

#define BLOCK_SESSION 0
#define BLOCK_SPREAD 1
#define BLOCK_REGIME 2
#define BLOCK_RISK 3
#define BLOCK_COOLDOWN 4
#define BLOCK_TICKRATE 5
#define BLOCK_SIGNAL_QUALITY 6

struct TradeSignal
{
   int direction;         // 1 = buy, -1 = sell, 0 = no-trade
   double stop_points;
   double target_points;
   int quality_flags;     // bitmask for diagnostics when setup is rejected
};

CTrade trade;

string g_symbol = "";
double g_point = 0.0;
int g_digits = 0;
int g_fast_ema_handle = INVALID_HANDLE;
int g_slow_ema_handle = INVALID_HANDLE;
int g_rsi_handle = INVALID_HANDLE;
int g_atr_handle = INVALID_HANDLE;

long g_tick_times[TICK_BUFFER_SIZE];
int g_tick_count = 0;
int g_tick_cursor = 0;
double g_spread_points_history[SPREAD_BUFFER_SIZE];
int g_spread_count = 0;
int g_spread_cursor = 0;

datetime g_last_trade_action_time = 0;
datetime g_last_risk_refresh_time = 0;
double g_daily_pnl = 0.0;
int g_consecutive_losses = 0;
int g_daily_closed_trades = 0;
int g_daily_wins = 0;
int g_daily_losses = 0;
datetime g_last_block_log_time = 0;
string g_last_block_reason = "";
double g_effective_max_spread_points = 0.0;
int g_effective_max_slippage_points = 0;
int g_effective_cooldown_seconds = 0;
int g_effective_min_ticks_window = 0;
bool g_use_ecn_post_fill_stops = false;
long g_block_counts[BLOCK_REASON_TOTAL];
long g_entries_count = 0;
datetime g_last_diag_print_time = 0;
ulong g_managed_ticket = 0;
double g_managed_initial_volume = 0.0;
double g_managed_initial_risk_points = 0.0;
bool g_managed_partial_done = false;

void LogBlockReason(const string reason);

string ToUpperText(const string source)
{
   string text = source;
   StringToUpper(text);
   return text;
}

int SymbolMatchScore(const string base_symbol_upper, const string candidate_symbol)
{
   if(StringLen(base_symbol_upper) == 0 || StringLen(candidate_symbol) == 0)
      return -1;

   const string candidate_upper = ToUpperText(candidate_symbol);
   if(candidate_upper == base_symbol_upper)
      return 1000;

   const int pos = StringFind(candidate_upper, base_symbol_upper);
   if(pos < 0)
      return -1;

   int score = 100;
   if(pos == 0)
      score += 200;
   if((pos + StringLen(base_symbol_upper)) == StringLen(candidate_upper))
      score += 120;

   const int extra = StringLen(candidate_upper) - StringLen(base_symbol_upper);
   if(extra > 0)
      score -= (extra > 40 ? 40 : extra);

   if(pos == 0 && extra > 0)
   {
      const string suffix = StringSubstr(candidate_upper, StringLen(base_symbol_upper));
      if(StringLen(suffix) <= 4)
         score += 20;
      if(StringFind(suffix, ".") == 0 || StringFind(suffix, "_") == 0)
         score += 8;
   }

   return score;
}

string ResolveTradeSymbol(const string requested_symbol)
{
   string requested = requested_symbol;
   if(StringLen(requested) == 0)
      requested = _Symbol;

   // In Strategy Tester, always use the tested symbol to avoid
   // no-trade runs caused by broker suffix mismatches.
   if((bool)MQLInfoInteger(MQL_TESTER))
   {
      if(requested != _Symbol)
      {
         PrintFormat("Tester mode: forcing symbol to '%s' (requested '%s').",
                     _Symbol,
                     requested);
      }
      return _Symbol;
   }

   if(SymbolSelect(requested, true))
      return requested;

   if(!InpAutoDetectSymbolSuffix)
      return requested;

   string base_key = InpAutoDetectBaseSymbol;
   if(StringLen(base_key) == 0)
      base_key = requested;
   base_key = ToUpperText(base_key);

   string best_symbol = "";
   int best_score = -1;

   const int chart_score = SymbolMatchScore(base_key, _Symbol);
   if(chart_score >= 0)
   {
      best_score = chart_score + 5;
      best_symbol = _Symbol;
   }

   const int total = SymbolsTotal(InpSearchAllBrokerSymbols);
   for(int i = 0; i < total; i++)
   {
      const string candidate = SymbolName(i, InpSearchAllBrokerSymbols);
      const int score = SymbolMatchScore(base_key, candidate);
      if(score > best_score)
      {
         best_score = score;
         best_symbol = candidate;
      }
   }

   if(best_score >= 0 && StringLen(best_symbol) > 0 && SymbolSelect(best_symbol, true))
   {
      if(best_symbol != requested)
      {
         PrintFormat("Auto-detected symbol '%s' from requested '%s' using base '%s'.",
                     best_symbol,
                     requested,
                     base_key);
      }
      return best_symbol;
   }

   return requested;
}

void ConfigureExecutionProfile()
{
   g_effective_max_spread_points = InpMaxSpreadPoints;
   g_effective_max_slippage_points = InpMaxSlippagePoints;
   g_effective_cooldown_seconds = InpCooldownSeconds;
   g_effective_min_ticks_window = InpMinTicksInWindow;
   g_use_ecn_post_fill_stops = false;

   if(InpExecutionMode == EXEC_MODE_ECN_LOW_SPREAD)
   {
      if(InpECNMaxSpreadPoints > 0.0)
         g_effective_max_spread_points = InpECNMaxSpreadPoints;
      if(InpECNMaxSlippagePoints > 0)
         g_effective_max_slippage_points = InpECNMaxSlippagePoints;
      if(InpECNCooldownSeconds >= 0)
         g_effective_cooldown_seconds = InpECNCooldownSeconds;
      if(InpECNMinTicksInWindow > 0 && InpECNMinTicksInWindow > g_effective_min_ticks_window)
         g_effective_min_ticks_window = InpECNMinTicksInWindow;
      g_use_ecn_post_fill_stops = InpECNSendStopsAfterFill;
   }

   if(g_effective_max_spread_points <= 0.0)
      g_effective_max_spread_points = InpMaxSpreadPoints;
   if(g_effective_max_slippage_points < 0)
      g_effective_max_slippage_points = InpMaxSlippagePoints;
   if(g_effective_cooldown_seconds < 0)
      g_effective_cooldown_seconds = 0;
   if(g_effective_min_ticks_window < 0)
      g_effective_min_ticks_window = 0;

   trade.SetDeviationInPoints(g_effective_max_slippage_points);

   if(InpExecutionMode == EXEC_MODE_ECN_LOW_SPREAD)
   {
      const long filling_flags = SymbolInfoInteger(g_symbol, SYMBOL_FILLING_MODE);
      if((filling_flags & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
         trade.SetTypeFilling(ORDER_FILLING_IOC);
      else if((filling_flags & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
         trade.SetTypeFilling(ORDER_FILLING_FOK);
      else
         trade.SetTypeFillingBySymbol(g_symbol);
   }
   else
   {
      trade.SetTypeFillingBySymbol(g_symbol);
   }
}

string ExecutionModeLabel()
{
   if(InpExecutionMode == EXEC_MODE_ECN_LOW_SPREAD)
      return "ECN_LOW_SPREAD";
   return "STANDARD";
}

int VolumeDigitsFromStep(const double step)
{
   int digits = 0;
   double scaled = step;
   while(scaled < 1.0 && digits < 8)
   {
      scaled *= 10.0;
      digits++;
   }
   return digits;
}

double NormalizeVolume(const double raw_volume)
{
   const double min_lot = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   const double max_lot = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
   const double lot_step = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);

   if(lot_step <= 0.0)
      return 0.0;

   double clipped = MathMax(min_lot, MathMin(max_lot, raw_volume));
   clipped = MathFloor(clipped / lot_step) * lot_step;

   const int vol_digits = VolumeDigitsFromStep(lot_step);
   return NormalizeDouble(clipped, vol_digits);
}

double ComputeOrderVolume(const double stop_points)
{
   if(!InpUseRiskPercent)
      return NormalizeVolume(InpFixedLot);

   if(InpRiskPercent <= 0.0)
      return NormalizeVolume(InpFixedLot);

   const double risk_money = AccountInfoDouble(ACCOUNT_EQUITY) * (InpRiskPercent * 0.01);
   if(risk_money <= 0.0)
      return NormalizeVolume(InpFixedLot);

   const double tick_size = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE_PROFIT);
   if(tick_value <= 0.0)
      tick_value = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tick_size <= 0.0 || tick_value <= 0.0 || stop_points <= 0.0)
      return NormalizeVolume(InpFixedLot);

   const double stop_distance_price = stop_points * g_point;
   const double risk_per_lot = (stop_distance_price / tick_size) * tick_value;
   if(risk_per_lot <= 0.0)
      return NormalizeVolume(InpFixedLot);

   return NormalizeVolume(risk_money / risk_per_lot);
}

bool IsTradingSessionOpen()
{
   if(!InpEnableSessionFilter)
      return true;

   MqlDateTime now_struct;
   if(!TimeToStruct(TimeCurrent(), now_struct))
      return true;
   const int hour_now = now_struct.hour;
   if(InpSessionStartHour == InpSessionEndHour)
      return true;

   if(InpSessionStartHour < InpSessionEndHour)
      return (hour_now >= InpSessionStartHour && hour_now < InpSessionEndHour);

   return (hour_now >= InpSessionStartHour || hour_now < InpSessionEndHour);
}

void RegisterTick(const MqlTick &tick)
{
   long tick_time_msc = tick.time_msc;
   if(tick_time_msc <= 0)
      tick_time_msc = (long)tick.time * 1000;
   if(tick_time_msc <= 0)
      tick_time_msc = (long)TimeCurrent() * 1000;

   g_tick_times[g_tick_cursor] = tick_time_msc;
   g_tick_cursor = (g_tick_cursor + 1) % TICK_BUFFER_SIZE;
   if(g_tick_count < TICK_BUFFER_SIZE)
      g_tick_count++;

   double spread_points = (tick.ask - tick.bid) / g_point;
   if(spread_points < 0.0)
      spread_points = 0.0;

   g_spread_points_history[g_spread_cursor] = spread_points;
   g_spread_cursor = (g_spread_cursor + 1) % SPREAD_BUFFER_SIZE;
   if(g_spread_count < SPREAD_BUFFER_SIZE)
      g_spread_count++;
}

int TicksInWindow(const int window_seconds)
{
   if(window_seconds <= 0 || g_tick_count <= 0)
      return 0;

   int last_idx = g_tick_cursor - 1;
   if(last_idx < 0)
      last_idx += TICK_BUFFER_SIZE;
   long now_msc = g_tick_times[last_idx];
   if(now_msc <= 0)
      now_msc = (long)TimeCurrent() * 1000;

   const long threshold = (long)window_seconds * 1000;
   int count = 0;

   for(int i = 0; i < g_tick_count; i++)
   {
      const long ts = g_tick_times[i];
      if(ts <= 0)
         continue;
      const long age = now_msc - ts;
      if(age >= 0 && age <= threshold)
         count++;
   }

   return count;
}

double SpreadRankPercentile(const double spread_points, const int requested_lookback)
{
   if(g_spread_count <= 0)
      return 0.0;

   int sample = requested_lookback;
   if(sample <= 0)
      sample = g_spread_count;
   if(sample > g_spread_count)
      sample = g_spread_count;
   if(sample <= 0)
      return 0.0;

   int less_or_equal = 0;
   for(int i = 0; i < sample; i++)
   {
      int idx = g_spread_cursor - 1 - i;
      while(idx < 0)
         idx += SPREAD_BUFFER_SIZE;
      if(g_spread_points_history[idx] <= spread_points + 0.000001)
         less_or_equal++;
   }

   return (double)less_or_equal / (double)sample;
}

void ResetManagedPositionState()
{
   g_managed_ticket = 0;
   g_managed_initial_volume = 0.0;
   g_managed_initial_risk_points = 0.0;
   g_managed_partial_done = false;
}

void UpdateManagedPositionState(const ulong ticket,
                                const ENUM_POSITION_TYPE type,
                                const double open_price,
                                const double sl,
                                const double volume)
{
   if(ticket == 0)
      return;

   if(g_managed_ticket != ticket)
   {
      g_managed_ticket = ticket;
      g_managed_initial_volume = volume;
      g_managed_partial_done = false;

      if(type == POSITION_TYPE_BUY && sl > 0.0 && sl < open_price)
         g_managed_initial_risk_points = (open_price - sl) / g_point;
      else if(type == POSITION_TYPE_SELL && sl > open_price)
         g_managed_initial_risk_points = (sl - open_price) / g_point;
      else
         g_managed_initial_risk_points = InpMinStopPoints;
   }
   else
   {
      const double lot_step = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);
      const double threshold = (lot_step > 0.0 ? lot_step : 0.01) * 0.5;
      if(g_managed_initial_volume > 0.0 && volume < (g_managed_initial_volume - threshold))
         g_managed_partial_done = true;
   }
}

void RegisterBlock(const int block_code, const string reason)
{
   if(block_code >= 0 && block_code < BLOCK_REASON_TOTAL)
      g_block_counts[block_code]++;
   LogBlockReason(reason);
}

bool RegimeAllowsEntry(const double atr_points, const double spread_points, string &reason)
{
   reason = "";
   if(!InpEnableRegimeFilter)
      return true;

   if(InpMinATRPoints > 0.0 && atr_points < InpMinATRPoints)
   {
      reason = StringFormat("regime low volatility atr=%.1f < %.1f", atr_points, InpMinATRPoints);
      return false;
   }

   if(InpMaxATRPoints > 0.0 && atr_points > InpMaxATRPoints)
   {
      reason = StringFormat("regime high volatility atr=%.1f > %.1f", atr_points, InpMaxATRPoints);
      return false;
   }

   if(InpSpreadToATRMaxRatio > 0.0 && atr_points > 0.0)
   {
      const double spread_ratio = spread_points / atr_points;
      if(spread_ratio > InpSpreadToATRMaxRatio)
      {
         reason = StringFormat("spread/atr ratio %.3f > %.3f", spread_ratio, InpSpreadToATRMaxRatio);
         return false;
      }
   }

   if(InpSpreadRankLookbackTicks > 8 &&
      InpMaxSpreadRankPercentile > 0.0 &&
      g_spread_count >= 25)
   {
      const double spread_rank = SpreadRankPercentile(spread_points, InpSpreadRankLookbackTicks);
      if(spread_rank > InpMaxSpreadRankPercentile)
      {
         reason = StringFormat("spread rank %.2f > %.2f", spread_rank, InpMaxSpreadRankPercentile);
         return false;
      }
   }

   return true;
}

int EffectiveMaxHoldingSeconds(const double atr_points)
{
   if(!InpUseAdaptiveTimeStop)
      return InpMaxHoldingSeconds;

   int max_hold = InpMaxHoldingSeconds;
   if(InpNormalVolHoldingSeconds > 0)
      max_hold = InpNormalVolHoldingSeconds;

   if(InpHighVolHoldingSeconds > 0 && atr_points >= InpHighVolATRPoints)
      max_hold = InpHighVolHoldingSeconds;
   else if(InpLowVolHoldingSeconds > 0 && atr_points <= InpLowVolATRPoints)
      max_hold = InpLowVolHoldingSeconds;

   return max_hold;
}

void MaybePrintDiagnostics()
{
   if(!InpEnableDiagnostics)
      return;

   const datetime now = TimeCurrent();
   if(now <= 0)
      return;

   if(InpDiagnosticsPrintIntervalSeconds > 0 &&
      g_last_diag_print_time > 0 &&
      (now - g_last_diag_print_time) < InpDiagnosticsPrintIntervalSeconds)
      return;

   g_last_diag_print_time = now;
   PrintFormat("Diag: entries=%I64d dailyClosed=%d wins=%d losses=%d dailyPnL=%.2f blocks[s=%I64d sp=%I64d rg=%I64d rk=%I64d cd=%I64d tk=%I64d sq=%I64d]",
               g_entries_count,
               g_daily_closed_trades,
               g_daily_wins,
               g_daily_losses,
               g_daily_pnl,
               g_block_counts[BLOCK_SESSION],
               g_block_counts[BLOCK_SPREAD],
               g_block_counts[BLOCK_REGIME],
               g_block_counts[BLOCK_RISK],
               g_block_counts[BLOCK_COOLDOWN],
               g_block_counts[BLOCK_TICKRATE],
               g_block_counts[BLOCK_SIGNAL_QUALITY]);
}

bool SpreadAllowed(const MqlTick &tick, double &spread_points)
{
   spread_points = (tick.ask - tick.bid) / g_point;
   if(spread_points < 0.0)
      spread_points = 0.0;
   return (spread_points <= g_effective_max_spread_points);
}

bool RefreshIndicators(double &ema_fast,
                       double &ema_slow,
                       double &ema_fast_prev,
                       double &ema_slow_prev,
                       double &rsi,
                       double &atr)
{
   double fast_buf[];
   double slow_buf[];
   double rsi_buf[];
   double atr_buf[];
   ArrayResize(fast_buf, 2);
   ArrayResize(slow_buf, 2);
   ArrayResize(rsi_buf, 1);
   ArrayResize(atr_buf, 1);
   ArraySetAsSeries(fast_buf, true);
   ArraySetAsSeries(slow_buf, true);
   ArraySetAsSeries(rsi_buf, true);
   ArraySetAsSeries(atr_buf, true);

   if(CopyBuffer(g_fast_ema_handle, 0, 0, 2, fast_buf) < 2)
      return false;
   if(CopyBuffer(g_slow_ema_handle, 0, 0, 2, slow_buf) < 2)
      return false;
   if(CopyBuffer(g_rsi_handle, 0, 0, 1, rsi_buf) < 1)
      return false;
   if(CopyBuffer(g_atr_handle, 0, 0, 1, atr_buf) < 1)
      return false;

   ema_fast = fast_buf[0];
   ema_fast_prev = fast_buf[1];
   ema_slow = slow_buf[0];
   ema_slow_prev = slow_buf[1];
   rsi = rsi_buf[0];
   atr = atr_buf[0];

   if(!MathIsValidNumber(ema_fast) || !MathIsValidNumber(ema_slow) || !MathIsValidNumber(rsi) || !MathIsValidNumber(atr))
      return false;
   return (atr > 0.0);
}

bool GenerateSignal(const MqlTick &tick,
                    const double ema_fast,
                    const double ema_slow,
                    const double ema_fast_prev,
                    const double ema_slow_prev,
                    const double rsi,
                    const double atr,
                    TradeSignal &signal)
{
   signal.direction = 0;
   signal.stop_points = 0.0;
   signal.target_points = 0.0;
   signal.quality_flags = 0;

   const int bars_needed = InpBreakoutLookbackBars + 3;
   if(bars_needed < 5)
      return false;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(g_symbol, InpSignalTF, 0, bars_needed, rates) < bars_needed)
      return false;

   double highest = -DBL_MAX;
   double lowest = DBL_MAX;
   for(int i = 2; i <= (InpBreakoutLookbackBars + 1); i++)
   {
      highest = MathMax(highest, rates[i].high);
      lowest = MathMin(lowest, rates[i].low);
   }

   const MqlRates impulse_bar = rates[1];
   const MqlRates prev_bar = rates[2];
   const double impulse_range_price = impulse_bar.high - impulse_bar.low;
   const double impulse_range_points = impulse_range_price / g_point;
   double impulse_body_percent = 0.0;
   if(impulse_range_price > 0.0)
      impulse_body_percent = (MathAbs(impulse_bar.close - impulse_bar.open) / impulse_range_price) * 100.0;

   const bool impulse_body_ok = (impulse_body_percent >= InpMinImpulseBodyPercent &&
                                 impulse_range_points >= InpMinImpulseRangePoints);
   const bool impulse_bullish = (impulse_bar.close > impulse_bar.open);
   const bool impulse_bearish = (impulse_bar.close < impulse_bar.open);

   const double ema_gap_points = MathAbs(ema_fast - ema_slow) / g_point;
   const bool trend_up = (ema_fast > ema_slow && ema_fast_prev >= ema_slow_prev && ema_gap_points >= InpMinEMAGapPoints);
   const bool trend_down = (ema_fast < ema_slow && ema_fast_prev <= ema_slow_prev && ema_gap_points >= InpMinEMAGapPoints);
   const bool bullish_breakout_live = (tick.bid > highest);
   const bool bearish_breakout_live = (tick.ask < lowest);
   const bool bullish_breakout_closed = (impulse_bar.close > highest);
   const bool bearish_breakout_closed = (impulse_bar.close < lowest);

   const double pullback_price = MathMax(atr * InpPullbackATRDistance, g_point * 6.0);
   bool bullish_pullback = false;
   bool bearish_pullback = false;
   if(InpEnablePullbackEntry)
   {
      bullish_pullback = (bullish_breakout_closed &&
                          tick.bid >= (highest - pullback_price) &&
                          tick.bid <= (highest + pullback_price * 1.5) &&
                          tick.bid >= (ema_fast - pullback_price));
      bearish_pullback = (bearish_breakout_closed &&
                          tick.ask <= (lowest + pullback_price) &&
                          tick.ask >= (lowest - pullback_price * 1.5) &&
                          tick.ask <= (ema_fast + pullback_price));
   }

   bool volume_ok = true;
   if(InpMinVolumeImpulse > 0.0 && prev_bar.tick_volume > 0)
   {
      const double impulse = (double)impulse_bar.tick_volume / (double)prev_bar.tick_volume;
      volume_ok = (impulse >= InpMinVolumeImpulse);
   }

    const bool long_rsi_ok = (rsi > 50.0 && rsi < InpRSIOverbought);
    const bool short_rsi_ok = (rsi < 50.0 && rsi > InpRSIOversold);
    const bool long_trigger = (bullish_breakout_live || bullish_pullback);
    const bool short_trigger = (bearish_breakout_live || bearish_pullback);

   const double atr_points = atr / g_point;
   const double stop_points = MathMax(InpMinStopPoints, atr_points * InpSL_ATRMultiplier);
   const double target_points = MathMax(InpMinTargetPoints, atr_points * InpTP_ATRMultiplier);
   signal.stop_points = stop_points;
   signal.target_points = target_points;

   if(trend_up && long_trigger)
   {
      int flags = 0;
      if(!volume_ok)
         flags |= 1;
      if(!impulse_body_ok || !impulse_bullish)
         flags |= 2;
      if(!long_rsi_ok)
         flags |= 4;
      if(flags == 0)
      {
         signal.direction = 1;
         return true;
      }
      signal.quality_flags |= flags;
   }

   if(trend_down && short_trigger)
   {
      int flags = 0;
      if(!volume_ok)
         flags |= 1;
      if(!impulse_body_ok || !impulse_bearish)
         flags |= 2;
      if(!short_rsi_ok)
         flags |= 4;
      if(flags == 0)
      {
         signal.direction = -1;
         return true;
      }
      signal.quality_flags |= flags;
   }

   return true;
}

bool GetOpenPosition(ulong &ticket,
                     ENUM_POSITION_TYPE &type,
                     double &open_price,
                     datetime &open_time,
                     double &sl,
                     double &tp,
                     double &volume)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      const ulong pos_ticket = PositionGetTicket(i);
      if(pos_ticket == 0)
         continue;
      if(!PositionSelectByTicket(pos_ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != g_symbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      ticket = pos_ticket;
      type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      open_time = (datetime)PositionGetInteger(POSITION_TIME);
      sl = PositionGetDouble(POSITION_SL);
      tp = PositionGetDouble(POSITION_TP);
      volume = PositionGetDouble(POSITION_VOLUME);
      return true;
   }

   return false;
}

void UpdateRiskStats()
{
   const datetime now = TimeCurrent();
   if(now <= 0)
      return;

   const datetime day_start = StringToTime(TimeToString(now, TIME_DATE));
   if(!HistorySelect(day_start, now))
      return;

   g_daily_pnl = 0.0;
   g_consecutive_losses = 0;
   g_daily_closed_trades = 0;
   g_daily_wins = 0;
   g_daily_losses = 0;
   bool reached_last_win = false;

   const int deals_total = HistoryDealsTotal();
   for(int i = deals_total - 1; i >= 0; i--)
   {
      const ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;
      if((long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber)
         continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != g_symbol)
         continue;

      const ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
         continue;

      const double pnl = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                       + HistoryDealGetDouble(ticket, DEAL_SWAP)
                       + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      g_daily_pnl += pnl;
      g_daily_closed_trades++;
      if(pnl > 0.00001)
         g_daily_wins++;
      else if(pnl < -0.00001)
         g_daily_losses++;

      if(!reached_last_win)
      {
         if(pnl < -0.00001)
            g_consecutive_losses++;
         else if(pnl > 0.00001)
            reached_last_win = true;
      }
   }

   g_last_risk_refresh_time = now;
}

void LogBlockReason(const string reason)
{
   const datetime now = TimeCurrent();
   if(reason != g_last_block_reason || (now - g_last_block_log_time) >= 10)
   {
      Print("Entry blocked: ", reason);
      g_last_block_reason = reason;
      g_last_block_log_time = now;
   }
}

bool RiskGuardsAllowEntry(string &reason)
{
   reason = "";
   if((TimeCurrent() - g_last_risk_refresh_time) >= 1)
      UpdateRiskStats();

   if(InpDailyLossLimitPercent > 0.0)
   {
      const double max_daily_loss = AccountInfoDouble(ACCOUNT_BALANCE) * (InpDailyLossLimitPercent * 0.01);
      if(max_daily_loss > 0.0 && g_daily_pnl <= -max_daily_loss)
      {
         reason = StringFormat("daily loss %.2f reached limit %.2f", g_daily_pnl, -max_daily_loss);
         return false;
      }
   }

   if(InpMaxConsecutiveLosses > 0 && g_consecutive_losses >= InpMaxConsecutiveLosses)
   {
      reason = StringFormat("consecutive losses %d reached limit %d", g_consecutive_losses, InpMaxConsecutiveLosses);
      return false;
   }

   return true;
}

void ManagePosition(const MqlTick &tick, const int signal_direction, const double atr)
{
   ulong ticket = 0;
   ENUM_POSITION_TYPE type = POSITION_TYPE_BUY;
   double open_price = 0.0;
   datetime open_time = 0;
   double sl = 0.0;
   double tp = 0.0;
   double volume = 0.0;
   if(!GetOpenPosition(ticket, type, open_price, open_time, sl, tp, volume))
   {
      ResetManagedPositionState();
      return;
   }

   UpdateManagedPositionState(ticket, type, open_price, sl, volume);

   const double atr_points = atr / g_point;
   if(atr_points <= 0.0)
      return;

   const int max_holding_seconds = EffectiveMaxHoldingSeconds(atr_points);
   if(max_holding_seconds > 0 && (TimeCurrent() - open_time) >= max_holding_seconds)
   {
      if(trade.PositionClose(g_symbol))
      {
         g_last_trade_action_time = TimeCurrent();
         Print("Position closed by max holding time.");
         ResetManagedPositionState();
      }
      return;
   }

   if(InpCloseOnOppositeSignal)
   {
      if((type == POSITION_TYPE_BUY && signal_direction < 0) ||
         (type == POSITION_TYPE_SELL && signal_direction > 0))
      {
         if(trade.PositionClose(g_symbol))
         {
            g_last_trade_action_time = TimeCurrent();
            Print("Position closed by opposite signal.");
            ResetManagedPositionState();
         }
         return;
      }
   }

   const int stops_level = (int)SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const double min_distance = MathMax((double)stops_level, 1.0) * g_point;
   const double be_trigger_points = atr_points * InpBreakevenTriggerATR;
   const double base_trail_multiplier = MathMax(InpTrailingATRMultiplier, 0.01);
   const double be_offset = InpBreakevenOffsetPoints * g_point;
   const double profit_points = (type == POSITION_TYPE_BUY)
                                ? ((tick.bid - open_price) / g_point)
                                : ((open_price - tick.ask) / g_point);
   const double reference_risk_points = MathMax(g_managed_initial_risk_points, MathMax(InpMinStopPoints, 1.0));

   if(InpEnablePartialTP &&
      !g_managed_partial_done &&
      InpPartialClosePercent > 0.0 &&
      InpPartialClosePercent < 1.0 &&
      InpPartialCloseAtRR > 0.0 &&
      profit_points >= (reference_risk_points * InpPartialCloseAtRR))
   {
      const double min_lot = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
      const double lot_step = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);
      double remain_target = volume - min_lot;
      if(remain_target > 0.0)
         remain_target = NormalizeVolume(remain_target);
      double close_volume = NormalizeVolume(volume * InpPartialClosePercent);
      if(remain_target > 0.0 && close_volume > remain_target)
         close_volume = remain_target;

      const double step_threshold = (lot_step > 0.0 ? lot_step : 0.01) * 0.5;
      if(close_volume >= min_lot && close_volume < (volume - step_threshold))
      {
         if(trade.PositionClosePartial(g_symbol, close_volume))
         {
            g_last_trade_action_time = TimeCurrent();
            g_managed_partial_done = true;
            PrintFormat("Partial close executed: %.2f lots at %.2fR",
                        close_volume,
                        profit_points / reference_risk_points);
         }
         else
         {
            PrintFormat("PositionClosePartial failed. retcode=%u (%s)",
                        trade.ResultRetcode(),
                        trade.ResultRetcodeDescription());
         }
      }
   }

   double trail_multiplier = base_trail_multiplier;
   if(InpTightenTrailAfter1R && InpTightTrailATRMultiplier > 0.0 && profit_points >= reference_risk_points)
      trail_multiplier = MathMin(trail_multiplier, InpTightTrailATRMultiplier);
   if(g_managed_partial_done && InpPostPartialTrailATRMultiplier > 0.0)
      trail_multiplier = MathMin(trail_multiplier, InpPostPartialTrailATRMultiplier);

   const double trail_points = atr_points * MathMax(trail_multiplier, 0.01);

   bool modify_needed = false;
   double new_sl = sl;

   if(type == POSITION_TYPE_BUY)
   {
      if(profit_points >= be_trigger_points)
      {
         const double be_level = open_price + be_offset;
         if(new_sl <= 0.0 || be_level > new_sl)
         {
            new_sl = be_level;
            modify_needed = true;
         }
      }

      if(profit_points >= trail_points)
      {
         const double trail_level = tick.bid - (trail_points * g_point);
         if(new_sl <= 0.0 || trail_level > new_sl)
         {
            new_sl = trail_level;
            modify_needed = true;
         }
      }

      if(modify_needed)
      {
         const double max_allowed = tick.bid - min_distance;
         new_sl = MathMin(new_sl, max_allowed);
      }
   }
   else if(type == POSITION_TYPE_SELL)
   {
      if(profit_points >= be_trigger_points)
      {
         const double be_level = open_price - be_offset;
         if(new_sl <= 0.0 || be_level < new_sl)
         {
            new_sl = be_level;
            modify_needed = true;
         }
      }

      if(profit_points >= trail_points)
      {
         const double trail_level = tick.ask + (trail_points * g_point);
         if(new_sl <= 0.0 || trail_level < new_sl)
         {
            new_sl = trail_level;
            modify_needed = true;
         }
      }

      if(modify_needed)
      {
         const double min_allowed = tick.ask + min_distance;
         new_sl = MathMax(new_sl, min_allowed);
      }
   }

   if(!modify_needed)
      return;

   new_sl = NormalizeDouble(new_sl, g_digits);
   if(tp > 0.0)
      tp = NormalizeDouble(tp, g_digits);

   if(type == POSITION_TYPE_BUY && sl > 0.0 && new_sl <= (sl + g_point))
      return;
   if(type == POSITION_TYPE_SELL && sl > 0.0 && new_sl >= (sl - g_point))
      return;

   if(!trade.PositionModify(g_symbol, new_sl, tp))
   {
      PrintFormat("PositionModify failed. retcode=%u (%s)", trade.ResultRetcode(), trade.ResultRetcodeDescription());
   }
}

bool ApplyStopsAfterFill(const double sl, const double tp)
{
   for(int attempt = 0; attempt < 6; attempt++)
   {
      if(PositionSelect(g_symbol))
      {
         if(trade.PositionModify(g_symbol, sl, tp))
            return true;

         PrintFormat("Post-fill stop attach failed. retcode=%u (%s)",
                     trade.ResultRetcode(),
                     trade.ResultRetcodeDescription());
         return false;
      }

      Sleep(20);
   }

   Print("Post-fill stop attach failed: position not found after order fill.");
   return false;
}

bool PlaceEntry(const int direction, double stop_points, double target_points, const MqlTick &tick)
{
   if(direction == 0)
      return false;

   const int stops_level = (int)SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const double min_stop = MathMax((double)stops_level + 1.0, InpMinStopPoints);
   stop_points = MathMax(stop_points, min_stop);
   target_points = MathMax(target_points, MathMax((double)stops_level + 1.0, InpMinTargetPoints));

   const double volume = ComputeOrderVolume(stop_points);
   if(volume <= 0.0)
   {
      Print("Entry blocked: invalid volume calculation.");
      return false;
   }

   double sl = 0.0;
   double tp = 0.0;
   if(direction > 0)
   {
      sl = NormalizeDouble(tick.ask - (stop_points * g_point), g_digits);
      tp = NormalizeDouble(tick.ask + (target_points * g_point), g_digits);
   }
   else
   {
      sl = NormalizeDouble(tick.bid + (stop_points * g_point), g_digits);
      tp = NormalizeDouble(tick.bid - (target_points * g_point), g_digits);
   }

   ResetLastError();
   bool sent = false;
   const bool send_stops_now = !g_use_ecn_post_fill_stops;
   if(direction > 0)
      sent = trade.Buy(volume, g_symbol, 0.0, send_stops_now ? sl : 0.0, send_stops_now ? tp : 0.0, "UF_XAUUSD_SCALPER");
   else
      sent = trade.Sell(volume, g_symbol, 0.0, send_stops_now ? sl : 0.0, send_stops_now ? tp : 0.0, "UF_XAUUSD_SCALPER");

   if(!sent)
   {
      PrintFormat("Order send failed. err=%d retcode=%u (%s)",
                  GetLastError(),
                  trade.ResultRetcode(),
                  trade.ResultRetcodeDescription());
      return false;
   }

   if(g_use_ecn_post_fill_stops)
   {
      if(!ApplyStopsAfterFill(sl, tp))
      {
         Print("Safety close triggered: unable to attach protective stops in ECN mode.");
         if(trade.PositionClose(g_symbol))
            g_last_trade_action_time = TimeCurrent();
         return false;
      }
   }

   g_last_trade_action_time = TimeCurrent();
   g_entries_count++;
   PrintFormat("Entry placed: dir=%d lots=%.2f sl=%.2f tp=%.2f mode=%s",
               direction,
               volume,
               sl,
               tp,
               ExecutionModeLabel());
   return true;
}

int OnInit()
{
   g_symbol = ResolveTradeSymbol(InpTradeSymbol);

   if(!SymbolSelect(g_symbol, true))
   {
      Print("Failed to select symbol: ", g_symbol);
      return INIT_FAILED;
   }

   g_point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   g_digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   if(g_point <= 0.0 || g_digits < 0)
   {
      Print("Invalid symbol pricing properties.");
      return INIT_FAILED;
   }

   g_fast_ema_handle = iMA(g_symbol, InpSignalTF, InpFastEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_slow_ema_handle = iMA(g_symbol, InpSignalTF, InpSlowEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_rsi_handle = iRSI(g_symbol, InpSignalTF, InpRSIPeriod, PRICE_CLOSE);
   g_atr_handle = iATR(g_symbol, InpSignalTF, InpATRPeriod);
   if(g_fast_ema_handle == INVALID_HANDLE ||
      g_slow_ema_handle == INVALID_HANDLE ||
      g_rsi_handle == INVALID_HANDLE ||
      g_atr_handle == INVALID_HANDLE)
   {
      Print("Indicator initialization failed.");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   ConfigureExecutionProfile();

   ArrayInitialize(g_tick_times, 0);
   ArrayInitialize(g_spread_points_history, 0.0);
   ArrayInitialize(g_block_counts, 0);
   g_tick_count = 0;
   g_tick_cursor = 0;
   g_spread_count = 0;
   g_spread_cursor = 0;
   g_entries_count = 0;
   g_last_diag_print_time = 0;
   ResetManagedPositionState();
   UpdateRiskStats();
   EventSetTimer(1);

   PrintFormat("UF XAUUSD scalper initialized on %s (%s), mode=%s spread<=%.1f slip<=%d cooldown=%ds minTicks=%d regime[%s atr %.1f..%.1f].",
               g_symbol,
               EnumToString(InpSignalTF),
               ExecutionModeLabel(),
               g_effective_max_spread_points,
               g_effective_max_slippage_points,
               g_effective_cooldown_seconds,
               g_effective_min_ticks_window,
               (InpEnableRegimeFilter ? "on" : "off"),
               InpMinATRPoints,
               InpMaxATRPoints);
   if(g_symbol != _Symbol)
      Print("Attach EA to chart symbol matching InpTradeSymbol for best tick frequency.");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_fast_ema_handle != INVALID_HANDLE)
      IndicatorRelease(g_fast_ema_handle);
   if(g_slow_ema_handle != INVALID_HANDLE)
      IndicatorRelease(g_slow_ema_handle);
   if(g_rsi_handle != INVALID_HANDLE)
      IndicatorRelease(g_rsi_handle);
   if(g_atr_handle != INVALID_HANDLE)
      IndicatorRelease(g_atr_handle);
}

void OnTimer()
{
   UpdateRiskStats();
   MaybePrintDiagnostics();
}

void OnTick()
{
   MqlTick tick;
   if(!SymbolInfoTick(g_symbol, tick))
      return;

   RegisterTick(tick);

   double ema_fast = 0.0;
   double ema_slow = 0.0;
   double ema_fast_prev = 0.0;
   double ema_slow_prev = 0.0;
   double rsi = 0.0;
   double atr = 0.0;
   if(!RefreshIndicators(ema_fast, ema_slow, ema_fast_prev, ema_slow_prev, rsi, atr))
      return;

   TradeSignal signal;
   if(!GenerateSignal(tick, ema_fast, ema_slow, ema_fast_prev, ema_slow_prev, rsi, atr, signal))
      return;

   ManagePosition(tick, signal.direction, atr);

   ulong ticket = 0;
   ENUM_POSITION_TYPE type = POSITION_TYPE_BUY;
   double open_price = 0.0;
   datetime open_time = 0;
   double sl = 0.0;
   double tp = 0.0;
   double volume = 0.0;
   if(GetOpenPosition(ticket, type, open_price, open_time, sl, tp, volume))
      return;

   if(signal.direction == 0)
   {
      if(signal.quality_flags != 0)
         RegisterBlock(BLOCK_SIGNAL_QUALITY, StringFormat("signal rejected flags=%d", signal.quality_flags));
      return;
   }

   if(!IsTradingSessionOpen())
   {
      RegisterBlock(BLOCK_SESSION, "outside configured session");
      return;
   }

   double spread_points = 0.0;
   if(!SpreadAllowed(tick, spread_points))
   {
      RegisterBlock(BLOCK_SPREAD, StringFormat("spread %.1f > %.1f", spread_points, g_effective_max_spread_points));
      return;
   }

   const double atr_points = atr / g_point;
   string regime_reason = "";
   if(!RegimeAllowsEntry(atr_points, spread_points, regime_reason))
   {
      RegisterBlock(BLOCK_REGIME, regime_reason);
      return;
   }

   string risk_reason = "";
   if(!RiskGuardsAllowEntry(risk_reason))
   {
      RegisterBlock(BLOCK_RISK, risk_reason);
      return;
   }

   if(g_effective_cooldown_seconds > 0 && (TimeCurrent() - g_last_trade_action_time) < g_effective_cooldown_seconds)
   {
      RegisterBlock(BLOCK_COOLDOWN, "cooldown active");
      return;
   }

   if(InpTickRateWindowSeconds > 0 && g_effective_min_ticks_window > 0)
   {
      const int ticks_now = TicksInWindow(InpTickRateWindowSeconds);
      if(ticks_now < g_effective_min_ticks_window)
      {
         RegisterBlock(BLOCK_TICKRATE, StringFormat("tick-rate %d below %d", ticks_now, g_effective_min_ticks_window));
         return;
      }
   }

   PlaceEntry(signal.direction, signal.stop_points, signal.target_points, tick);
}

double OnTester()
{
   const double profit = TesterStatistics(STAT_PROFIT);
   if(!InpUseCustomTesterScore)
      return profit;

   const double trades = TesterStatistics(STAT_TRADES);
   const double pf_raw = TesterStatistics(STAT_PROFIT_FACTOR);
   const double dd_rel = TesterStatistics(STAT_BALANCE_DDREL_PERCENT);
   const double expected_payoff = TesterStatistics(STAT_EXPECTED_PAYOFF);

   if(trades < 1.0)
      return -1000000000.0;

   if(trades < (double)InpMinTradesForTesterScore)
      return -500000.0 + trades * 20.0 + profit * 0.01;

   double pf = pf_raw;
   if(!MathIsValidNumber(pf) || pf <= 0.0)
      pf = 0.05;
   if(pf > 5.0)
      pf = 5.0;

   double dd_factor = 1.0 - (MathMin(MathMax(dd_rel, 0.0), 95.0) / 100.0);
   if(dd_factor < 0.05)
      dd_factor = 0.05;

   double pf_factor = pf;
   if(InpTargetProfitFactor > 0.0)
      pf_factor *= MathMin(pf / InpTargetProfitFactor, 1.50);

   double score = profit * pf_factor * dd_factor;
   score += expected_payoff * trades * 0.20;

   if(InpMaxBalanceDDPctForScore > 0.0 && dd_rel > InpMaxBalanceDDPctForScore)
   {
      const double penalty_scale = MathAbs(profit) + 1000.0;
      score -= (dd_rel - InpMaxBalanceDDPctForScore) * penalty_scale;
   }

   if(profit <= 0.0)
      score -= 250000.0;

   return score;
}
