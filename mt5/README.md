# UltraFast XAUUSD Scalper EA (MT5)

This folder contains a production-oriented **MT5 Expert Advisor template** for XAUUSD:

- `UltraFastXAUUSDScalper.mq5`

It is designed for low-latency scalp execution while keeping strict live-account safeguards:

- spread and slippage filters
- tick-rate/liquidity gating
- session filter
- ATR-based dynamic SL/TP
- breakeven + trailing management
- daily loss cap and max consecutive losses

## Important reality check

Retail MT5 EAs cannot truly match institutional HFT infrastructure (co-location, direct market access, custom hardware).  
This EA is built to be **as fast and robust as possible in retail conditions**, not to promise guaranteed institutional-level performance.

## Install

1. Open MT5 -> `File` -> `Open Data Folder`
2. Copy `UltraFastXAUUSDScalper.mq5` into:
   - `MQL5/Experts/`
3. Restart MT5 or refresh the Navigator.
4. Compile in MetaEditor.
5. Attach to an **XAUUSD** chart (M1 recommended).

## Default strategy logic

Entry requires all of the following:

1. Trend alignment from EMA fast/slow.
2. Breakout of recent micro-range (`InpBreakoutLookbackBars`).
3. RSI confirmation (avoid extreme exhaustion).
4. Tick-volume impulse filter.
5. Spread, session, risk, and tick-rate filters all pass.

Position handling:

- hard SL/TP at entry (ATR-derived)
- optional close on opposite signal
- breakeven trigger
- ATR trailing stop
- max holding time safety close

## Suggested baseline for XAUUSD live testing

Start conservative and tune based on broker conditions:

- `InpSignalTF = PERIOD_M1`
- `InpFastEMAPeriod = 8`
- `InpSlowEMAPeriod = 21`
- `InpMaxSpreadPoints = 30..60` (broker dependent)
- `InpMaxSlippagePoints = 10..25`
- `InpRiskPercent = 0.10..0.40`
- `InpDailyLossLimitPercent = 1.0..3.0`
- `InpMaxHoldingSeconds = 90..240`

## Optimization workflow

1. Backtest with **real tick data** and realistic spread/slippage.
2. Forward test on demo with same VPS/broker environment as live.
3. Keep optimization windows small to reduce curve-fit.
4. Validate out-of-sample periods.
5. Move to tiny live size first.

## VPS and execution requirements

To keep execution latency low:

- run EA on a VPS near broker server
- use stable low-jitter network
- avoid overloaded terminals with many heavy indicators
- monitor `Experts` and `Journal` logs for blocked-entry reasons

## Risk notes

- This EA can still lose money quickly in high-impact news and spread spikes.
- Keep AutoTrading risk controls enabled.
- Prefer disabling around major macro events if your broker widens aggressively.
