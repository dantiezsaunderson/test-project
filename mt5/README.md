# UltraFast XAUUSD Scalper EA (MT5)

This folder contains a production-oriented **MT5 Expert Advisor template** for XAUUSD:

- `UltraFastXAUUSDScalper.mq5`

It is designed for low-latency scalp execution while keeping strict live-account safeguards:

- broker-symbol auto-detection (`XAUUSD`, `XAUUSDm`, `XAUUSD.pro`, etc.)
- spread and slippage filters
- tick-rate/liquidity gating
- session filter
- standard and ECN low-spread execution profiles
- ATR-based dynamic SL/TP
- regime filter (ATR band + spread rank + spread/ATR ratio)
- breakeven + adaptive trailing management
- optional pullback entries after breakout
- optional partial take-profit at R-multiple
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

## Symbol auto-detection

The EA can auto-resolve broker naming variants when exact `InpTradeSymbol` is unavailable.

Key inputs:

- `InpAutoDetectSymbolSuffix = true`
- `InpAutoDetectBaseSymbol = "XAUUSD"`
- `InpSearchAllBrokerSymbols = true`

Example behavior:

- requested `XAUUSD` not found
- broker offers `XAUUSDm`
- EA auto-detects `XAUUSDm` and logs it in `Experts`

## Default strategy logic

Entry requires all of the following:

1. Trend alignment from EMA fast/slow.
2. Breakout of recent micro-range (`InpBreakoutLookbackBars`).
3. Closed-bar impulse quality check (body % and range points).
4. RSI confirmation (avoid extreme exhaustion).
5. Tick-volume impulse filter.
6. Optional pullback re-entry around breakout level.
7. Spread, session, regime, risk, and tick-rate filters all pass.

Position handling:

- hard SL/TP at entry (ATR-derived)
- optional close on opposite signal
- breakeven trigger
- ATR trailing stop (can tighten after 1R)
- optional partial close at configurable R-multiple
- adaptive max holding time by volatility regime

## Regime filters (new)

Use these to avoid dead/chaotic conditions before optimization:

- `InpEnableRegimeFilter`
- `InpMinATRPoints`, `InpMaxATRPoints`
- `InpSpreadRankLookbackTicks`, `InpMaxSpreadRankPercentile`
- `InpSpreadToATRMaxRatio`

This reduces entries when spread is unusually expensive relative to recent market state.

## Diagnostics (new)

The EA now tracks reason-code counters and periodic diagnostics:

- blocked by session/spread/regime/risk/cooldown/tick-rate/signal-quality
- daily closed trades, wins, losses, and PnL

Main inputs:

- `InpEnableDiagnostics`
- `InpDiagnosticsPrintIntervalSeconds`

## Execution profiles

`InpExecutionMode` supports:

1. `EXEC_MODE_STANDARD`
   - uses the standard spread/slippage/cooldown inputs
   - sends market order with SL/TP in one request
2. `EXEC_MODE_ECN_LOW_SPREAD`
   - uses ECN overrides:
     - `InpECNMaxSpreadPoints`
     - `InpECNMaxSlippagePoints`
     - `InpECNCooldownSeconds`
     - `InpECNMinTicksInWindow`
   - can send orders first, then attach stops (`InpECNSendStopsAfterFill = true`) for ECN compatibility
   - attempts IOC fill policy when broker supports it

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

For low-spread ECN accounts, try:

- `InpExecutionMode = EXEC_MODE_ECN_LOW_SPREAD`
- `InpECNMaxSpreadPoints = 12..28`
- `InpECNMaxSlippagePoints = 4..12`
- `InpECNCooldownSeconds = 1..5`
- `InpECNMinTicksInWindow = 8..15`

## Optimization workflow

1. Backtest with **real tick data** and realistic spread/slippage.
2. Tune execution+regime filters first (`spread/slippage/cooldown/tick-rate/regime`).
3. Tune exits next (`SL/TP ATR multipliers`, adaptive hold, trailing, partial TP).
4. Tune signal sensitivity last (`EMA/RSI/lookback/impulse settings`).
5. Validate out-of-sample periods and then forward test on demo.
6. Move to tiny live size first.

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
