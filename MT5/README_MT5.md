# XAU_XIMH_ScalperEA (MT5)

Current release: **v2.00**

Hybrid intraday EA for gold scalping on MT5:

- **Mean Reversion mode** in non-trend regimes
- **Breakout mode** in trend regimes
- Dynamic sizing, drawdown throttles, and hard risk locks

## Files

- `XAU_XIMH_ScalperEA.mq5` - Expert Advisor source
- `sets/XAU_XIMH_Ultima_Aggressive.set` - Aggressive profile (**matches EA defaults**)
- `sets/XAU_XIMH_Ultima_Balanced.set` - Balanced profile
- `sets/XAU_XIMH_Ultima_Conservative.set` - Conservative profile

## Strategy Components Implemented

1. **Regime classifier**: `ADX + Hurst`
2. **MR signal**: VWAP z-score + OFI z-score + tick imbalance
3. **Breakout signal**: momentum z-score + OFI z-score + range breakout z-score
4. **Entry confirmation**: consecutive-bar confirmation
5. **Exit stack**:
   - ATR-based stop-losses
   - MR take-profit
   - Breakout TP1 partial + trailing stop
   - Time stop
   - Signal reversal exit
6. **Risk engine**:
   - Base risk per trade with conviction/drawdown/volatility multipliers
   - Per-trade risk cap
   - Broker-accurate stop risk sizing via `OrderCalcProfit`
   - Absolute lot cap and minimum stop-distance floor
   - Daily and weekly loss locks
   - Hard drawdown kill-switch
   - Spread regime filter

## Install in MT5

1. Open **MetaEditor** from MT5.
2. Copy `XAU_XIMH_ScalperEA.mq5` into:
   - `MQL5/Experts/` (or a subfolder under Experts)
3. Compile the EA (`F7`).
4. Attach EA to your **XAUUSD** chart (recommended start on `M1`).

## Default Profile (Baked into EA)

- The EA now ships with the **Ultima aggressive profile** as default input values.
- Equivalent preset file: `sets/XAU_XIMH_Ultima_Aggressive.set`
- Core defaults include:
  - `InpConfirmBars = 1`
  - `InpBaseRiskPct = 0.08`
  - `InpMaxLossPerTradePct = 0.12`
  - `InpMaxLots = 1.00`
  - `InpMinStopDistancePoints = 80`
  - `InpSpreadMultiplierMax = 1.45`

## How to Load Presets in Strategy Tester (MT5)

1. Open **View -> Strategy Tester**.
2. Select `XAU_XIMH_ScalperEA`.
3. Symbol: **XAUUSD** (or your broker suffix variant, e.g., `XAUUSD.` / `XAUUSDm`).
4. Timeframe: **M1**.
5. In **Inputs**, click **Load** and choose one of the files in `MT5/sets/`.
6. If your broker server is not UTC, set `InpServerToUTCOffsetHours`:
   - Example: server = UTC+2 -> set `2`
   - Example: server = UTC+3 -> set `3`
7. Start with:
   - Aggressive: highest activity (still risk-capped)
   - Balanced: moderate turnover/risk
   - Conservative: lowest activity/risk

## Backtest Checklist

1. Use high-quality tick data for XAUUSD.
2. Include realistic spread and commissions.
3. Test multiple years and event-heavy periods.
4. Validate out-of-sample windows before live deployment.

## If Results Look Wrong (Very Few Trades / Oversized Lot)

1. Confirm `InpServerToUTCOffsetHours` matches your broker server (common: `2` or `3`).
2. Start with `XAU_XIMH_Ultima_Balanced.set` for calibration, then move to aggressive.
3. Check the Journal entry logs for `estRisk=...` and ensure per-trade cash risk is in your expected range.

## Notes

- This EA is single-symbol and designed to hold at most one strategy position for the configured symbol/magic number.
- OFI is implemented via a tick-flow proxy (up/down signed tick volume), suitable when full L2 book data is unavailable.
- Always forward-test on demo before production use.
