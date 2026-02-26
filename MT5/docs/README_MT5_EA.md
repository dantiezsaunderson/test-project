# AURIC_MSX_EA (MT5) - Setup and Usage

This EA implements the multi-strategy architecture from the strategy memo:
- S1: micro scalper
- S2: momentum breakout
- S3: mean reversion
- S4: squeeze breakout
- S5: adaptive grid
- S6: swing trend

Primary file:
- `MT5/Experts/AURIC_MSX_EA.mq5`

## 1) Install in MetaTrader 5

1. Open MT5.
2. Go to **File -> Open Data Folder**.
3. Copy `AURIC_MSX_EA.mq5` into:
   - `MQL5/Experts/`
4. Open MetaEditor and compile the EA.
5. Attach EA to chart (recommended starting chart: **XAUUSD, M1**).

## 2) Recommended initial chart + tester setup

- Symbol: `XAUUSD`
- Model: **Every tick based on real ticks**
- Spread: current or realistic broker spread
- Date range: at least 3-5 years for first validation pass
- Deposit/leverage: match your intended production environment

## 3) Starter parameter profile (from memo defaults)

- `DailyRiskPct = 0.80`
- `MaxOpenRiskPct = 3.50`
- `SoftDrawdownPct = 8.0`
- `HardDrawdownPct = 12.0`
- `S1EntryThreshold = 0.65`
- `S2DonchianPeriod = 20`
- `S3ZEntry = 2.0`
- `S4SqueezePercentile = 0.20`
- `S5GridSpacingATR = 0.35`
- `S6SL_ATR_H4 = 2.50`

## 4) Important operational notes

- The EA uses **manual blackout windows** for news filters by default:
  - `ManualNewsBlackoutUTC = "13:25-13:40;15:55-16:10"`
  - Adjust this to your release schedule (NFP/CPI/FOMC, etc).
- The EA enforces portfolio controls:
  - daily loss stop
  - hard drawdown kill switch
  - max open positions
  - max open risk
- S5 grid is automatically disabled in trend-kill conditions and after emergency exits for cooldown minutes.

## 5) Suggested optimization order

1. Optimize execution-safe blocks first:
   - spread filters, SL/TP ATR multipliers, session window
2. Then optimize regime thresholds:
   - ADX trend/range, trend score threshold
3. Finally tune strategy-specific entries:
   - S1 threshold
   - S2 breakout buffer
   - S3 z-score threshold
   - S5 spacing and levels

Use walk-forward and OOS validation after each optimization stage.

## 6) Production checklist

- Confirm broker symbol contract settings (tick value/size, volume step).
- Validate max slippage under live conditions.
- Start with reduced risk and scale up in phases.
- Review logs for risk halts and edge-decay state changes weekly.

## 7) If tester shows "no trades"

Use this quick checklist:

1. Use **Every tick based on real ticks** model.
2. Confirm all strategy toggles are enabled (`EnableS1..EnableS6=true`).
3. Keep `BacktestRelaxFilters=true` for first validation pass.
4. Set `PrintDiagnosticsInTester=true` and check `AURIC_DIAG` lines in Journal.
5. If needed, adjust `ServerToUTCOffsetHours` so session/news windows align to broker server time.
