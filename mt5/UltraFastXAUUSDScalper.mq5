#property strict
#property version   "1.00"
#property description "Ultra-fast XAUUSD scalper template with live-account risk controls."

#include <Trade/Trade.mqh>

input group "Core"
input string InpTradeSymbol                = "XAUUSD";
input ENUM_TIMEFRAMES InpSignalTF          = PERIOD_M1;
input long InpMagicNumber                  = 2026021601;

input group "Execution Filters"
input double InpMaxSpreadPoints            = 45.0;
input int InpMaxSlippagePoints             = 18;
input int InpCooldownSeconds               = 8;
input int InpTickRateWindowSeconds         = 2;
input int InpMinTicksInWindow              = 6;
input bool InpEnableSessionFilter          = true;
input int InpSessionStartHour              = 6;
input int InpSessionEndHour                = 23;

input group "Signal Model"
input int InpFastEMAPeriod                 = 8;
input int InpSlowEMAPeriod                 = 21;
input int InpRSIPeriod                     = 8;
input double InpRSIOverbought              = 72.0;
input double InpRSIOversold                = 28.0;
input double InpMinEMAGapPoints            = 8.0;
input int InpBreakoutLookbackBars          = 8;
input double InpMinVolumeImpulse           = 1.10;
input int InpATRPeriod                     = 14;
input double InpSL_ATRMultiplier           = 0.85;
input double InpTP_ATRMultiplier           = 1.20;
input double InpMinStopPoints              = 80.0;
input double InpMinTargetPoints            = 80.0;

input group "Position Management"
input int InpMaxHoldingSeconds             = 180;
input bool InpCloseOnOppositeSignal        = true;
input double InpBreakevenTriggerATR        = 0.45;
input double InpBreakevenOffsetPoints      = 10.0;
input double InpTrailingATRMultiplier      = 0.55;

input group "Risk Controls"
input bool InpUseRiskPercent               = true;
input double InpRiskPercent                = 0.30;
input double InpFixedLot                   = 0.01;
input double InpDailyLossLimitPercent      = 2.50;
input int InpMaxConsecutiveLosses          = 4;

// Keep this buffer compact for speed while still covering short windows.
#define TICK_BUFFER_SIZE 1024

struct TradeSignal
{
   int direction;         // 1 = buy, -1 = sell, 0 = no-trade
   double stop_points;
   double target_points;
};

CTrade trade;

string g_symbol = "";
double g_point = 0.0;
int g_digits = 0;
int g_fast_ema_handle = INVALID_HANDLE;
int g_slow_ema_handle = INVALID_HANDLE;
int g_rsi_handle = INVALID_HANDLE;
int g_atr_handle = INVALID_HANDLE;

uint g_tick_times[TICK_BUFFER_SIZE];
int g_tick_count = 0;
int g_tick_cursor = 0;

datetime g_last_trade_action_time = 0;
datetime g_last_risk_refresh_time = 0;
double g_daily_pnl = 0.0;
int g_consecutive_losses = 0;
datetime g_last_block_log_time = 0;
string g_last_block_reason = "";

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

   const int hour_now = TimeHour(TimeCurrent());
   if(InpSessionStartHour == InpSessionEndHour)
      return true;

   if(InpSessionStartHour < InpSessionEndHour)
      return (hour_now >= InpSessionStartHour && hour_now < InpSessionEndHour);

   return (hour_now >= InpSessionStartHour || hour_now < InpSessionEndHour);
}

void RegisterTick()
{
   g_tick_times[g_tick_cursor] = GetTickCount();
   g_tick_cursor = (g_tick_cursor + 1) % TICK_BUFFER_SIZE;
   if(g_tick_count < TICK_BUFFER_SIZE)
      g_tick_count++;
}

int TicksInWindow(const int window_seconds)
{
   if(window_seconds <= 0 || g_tick_count <= 0)
      return 0;

   const uint now = GetTickCount();
   const uint threshold = (uint)(window_seconds * 1000);
   int count = 0;

   for(int i = 0; i < g_tick_count; i++)
   {
      const uint ts = g_tick_times[i];
      const uint age = now - ts;
      if(age <= threshold)
         count++;
   }

   return count;
}

bool SpreadAllowed(const MqlTick &tick, double &spread_points)
{
   spread_points = (tick.ask - tick.bid) / g_point;
   if(spread_points < 0.0)
      spread_points = 0.0;
   return (spread_points <= InpMaxSpreadPoints);
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

   const int bars_needed = InpBreakoutLookbackBars + 2;
   if(bars_needed < 4)
      return false;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(g_symbol, InpSignalTF, 0, bars_needed, rates) < bars_needed)
      return false;

   double highest = -DBL_MAX;
   double lowest = DBL_MAX;
   for(int i = 1; i <= InpBreakoutLookbackBars; i++)
   {
      highest = MathMax(highest, rates[i].high);
      lowest = MathMin(lowest, rates[i].low);
   }

   const double ema_gap_points = MathAbs(ema_fast - ema_slow) / g_point;
   const bool trend_up = (ema_fast > ema_slow && ema_fast_prev >= ema_slow_prev && ema_gap_points >= InpMinEMAGapPoints);
   const bool trend_down = (ema_fast < ema_slow && ema_fast_prev <= ema_slow_prev && ema_gap_points >= InpMinEMAGapPoints);
   const bool bullish_breakout = (tick.bid > highest);
   const bool bearish_breakout = (tick.ask < lowest);

   bool volume_ok = true;
   if(InpMinVolumeImpulse > 0.0 && rates[1].tick_volume > 0)
   {
      const double impulse = (double)rates[0].tick_volume / (double)rates[1].tick_volume;
      volume_ok = (impulse >= InpMinVolumeImpulse);
   }

   const double atr_points = atr / g_point;
   const double stop_points = MathMax(InpMinStopPoints, atr_points * InpSL_ATRMultiplier);
   const double target_points = MathMax(InpMinTargetPoints, atr_points * InpTP_ATRMultiplier);

   if(trend_up && bullish_breakout && volume_ok && rsi > 50.0 && rsi < InpRSIOverbought)
   {
      signal.direction = 1;
      signal.stop_points = stop_points;
      signal.target_points = target_points;
      return true;
   }

   if(trend_down && bearish_breakout && volume_ok && rsi < 50.0 && rsi > InpRSIOversold)
   {
      signal.direction = -1;
      signal.stop_points = stop_points;
      signal.target_points = target_points;
      return true;
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
      return;

   if(InpMaxHoldingSeconds > 0 && (TimeCurrent() - open_time) >= InpMaxHoldingSeconds)
   {
      if(trade.PositionClose(g_symbol))
      {
         g_last_trade_action_time = TimeCurrent();
         Print("Position closed by max holding time.");
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
         }
         return;
      }
   }

   const double atr_points = atr / g_point;
   if(atr_points <= 0.0)
      return;

   const int stops_level = (int)SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const double min_distance = MathMax((double)stops_level, 1.0) * g_point;
   const double be_trigger_points = atr_points * InpBreakevenTriggerATR;
   const double trail_points = atr_points * InpTrailingATRMultiplier;
   const double be_offset = InpBreakevenOffsetPoints * g_point;

   bool modify_needed = false;
   double new_sl = sl;

   if(type == POSITION_TYPE_BUY)
   {
      const double profit_points = (tick.bid - open_price) / g_point;
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
      const double profit_points = (open_price - tick.ask) / g_point;
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
   if(direction > 0)
      sent = trade.Buy(volume, g_symbol, 0.0, sl, tp, "UF_XAUUSD_SCALPER");
   else
      sent = trade.Sell(volume, g_symbol, 0.0, sl, tp, "UF_XAUUSD_SCALPER");

   if(!sent)
   {
      PrintFormat("Order send failed. err=%d retcode=%u (%s)",
                  GetLastError(),
                  trade.ResultRetcode(),
                  trade.ResultRetcodeDescription());
      return false;
   }

   g_last_trade_action_time = TimeCurrent();
   PrintFormat("Entry placed: dir=%d lots=%.2f sl=%.2f tp=%.2f", direction, volume, sl, tp);
   return true;
}

int OnInit()
{
   g_symbol = InpTradeSymbol;
   if(StringLen(g_symbol) == 0)
      g_symbol = _Symbol;

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
   trade.SetDeviationInPoints(InpMaxSlippagePoints);
   trade.SetTypeFillingBySymbol(g_symbol);

   ArrayInitialize(g_tick_times, 0);
   g_tick_count = 0;
   g_tick_cursor = 0;
   UpdateRiskStats();
   EventSetTimer(1);

   PrintFormat("UF XAUUSD scalper initialized on %s (%s).", g_symbol, EnumToString(InpSignalTF));
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
}

void OnTick()
{
   MqlTick tick;
   if(!SymbolInfoTick(g_symbol, tick))
      return;

   RegisterTick();

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
      return;

   if(!IsTradingSessionOpen())
   {
      LogBlockReason("outside configured session");
      return;
   }

   double spread_points = 0.0;
   if(!SpreadAllowed(tick, spread_points))
   {
      LogBlockReason(StringFormat("spread %.1f > %.1f", spread_points, InpMaxSpreadPoints));
      return;
   }

   string risk_reason = "";
   if(!RiskGuardsAllowEntry(risk_reason))
   {
      LogBlockReason(risk_reason);
      return;
   }

   if(InpCooldownSeconds > 0 && (TimeCurrent() - g_last_trade_action_time) < InpCooldownSeconds)
   {
      LogBlockReason("cooldown active");
      return;
   }

   if(InpTickRateWindowSeconds > 0 && InpMinTicksInWindow > 0)
   {
      const int ticks_now = TicksInWindow(InpTickRateWindowSeconds);
      if(ticks_now < InpMinTicksInWindow)
      {
         LogBlockReason(StringFormat("tick-rate %d below %d", ticks_now, InpMinTicksInWindow));
         return;
      }
   }

   PlaceEntry(signal.direction, signal.stop_points, signal.target_points, tick);
}
