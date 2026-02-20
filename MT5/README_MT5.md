# XAU_XIMH_ScalperEA (MT5)

Hybrid intraday EA for gold scalping on MT5:

- **Mean Reversion mode** in non-trend regimes
- **Breakout mode** in trend regimes
- Dynamic sizing, drawdown throttles, and hard risk locks

## Files

- `XAU_XIMH_ScalperEA.mq5` - Expert Advisor source

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
   - Daily and weekly loss locks
   - Hard drawdown kill-switch
   - Spread regime filter

## Install in MT5

1. Open **MetaEditor** from MT5.
2. Copy `XAU_XIMH_ScalperEA.mq5` into:
   - `MQL5/Experts/` (or a subfolder under Experts)
3. Compile the EA (`F7`).
4. Attach EA to your **XAUUSD** chart (recommended start on `M1`).

## Recommended Initial Parameters

- `InpSignalTF = PERIOD_M1`
- `InpTradeSymbol = ""` (use chart symbol)
- `InpBaseRiskPct = 0.20`
- Keep session windows in UTC:
  - 06:30-10:30
  - 12:30-16:30

## Backtest Checklist

1. Use high-quality tick data for XAUUSD.
2. Include realistic spread and commissions.
3. Test multiple years and event-heavy periods.
4. Validate out-of-sample windows before live deployment.

## Notes

- This EA is single-symbol and designed to hold at most one strategy position for the configured symbol/magic number.
- OFI is implemented via a tick-flow proxy (up/down signed tick volume), suitable when full L2 book data is unavailable.
- Always forward-test on demo before production use.
