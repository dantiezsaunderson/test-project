# GS Quant Architect v4.02 - Variable Tuning Guide

This guide explains every input variable in `GS-QuantArchitectv6.mq5` so you can tune the EA with intention.

## How to tune safely

- Optimize in stages (entry -> exits -> market filters).
- Keep fixed lot (`InpFixedLot=0.01`) while optimizing logic.
- Use real ticks and forward testing before increasing risk.
- Change only a few related variables per pass.

---

## 1) GLOBAL

- `InpMagicNumber` (default `20260306`)
  - Unique ID for this EA's trades.
  - Use a different value per strategy/account instance.

- `InpTradeComment` (default `"GSQ4"`)
  - Comment tag for orders and diagnostics.
  - Useful for filtering trades in history.

- `InpDebugMode` (default `true`)
  - Enables detailed log output.
  - Keep `true` while tuning, set `false` for clean production logs.

- `InpLogTrades` (default `true`)
  - Logs open/close actions.
  - Can be disabled during large optimization sweeps.

- `InpSignalTF` (default `PERIOD_M15`)
  - Main decision timeframe.
  - Lower TF = more trades/noise; higher TF = fewer trades/smoother behavior.

- `InpWarmupBars` (default `20`)
  - Bars required before trading starts.
  - Increase if indicators are unstable at start of test.

---

## 2) EXECUTION SAFETY

- `InpMaxSlippage` (default `30` points)
  - Max acceptable price deviation on market orders.
  - Tight values can miss entries; loose values can worsen fill quality.

- `InpSpreadFilterPoints` (default `0` = off)
  - Blocks entries when spread exceeds threshold.
  - Very important for forward robustness and news periods.

- `InpMinSecondsBetweenEntries` (default `30`)
  - Cooldown between entries.
  - Helps avoid rapid flip-flopping in chop.

- `InpAllowBuy` / `InpAllowSell` (default `true` / `true`)
  - Direction gate switches.
  - Useful for directional bias tests.

- `InpOnePositionPerDirection` (default `true`)
  - If `true`, only one BUY and one SELL max at a time.
  - Reduces over-stacking and duplicate exposure.

- `InpMaxOpenPositions` (default `2`)
  - Absolute cap of simultaneous positions.
  - Lower = safer; higher = more opportunity but more clustered risk.

---

## 3) RISK

- `InpRiskLevel` (default `RISK_MODERATE`)
  - Base risk profile for dynamic lot sizing.
  - Conservative/Moderate/Aggressive map to lower/higher risk percent.

- `InpFixedLot` (default `0.00`)
  - `0` means risk-based position size.
  - `>0` forces fixed lots (best for optimizer comparability).

- `InpMaxDailyDrawdown` (default `6.0%`)
  - Daily circuit breaker for new entries.
  - Tighten for capital preservation.

- `InpMaxTotalDrawdown` (default `20.0%`)
  - Hard kill switch threshold.
  - If reached, EA stops opening and can close all positions.

---

## 4) STRATEGY TOGGLES

- `InpEnableTrend` (default `true`)
  - Includes trend-following score in entry decision.

- `InpEnableMeanReversion` (default `true`)
  - Includes band/RSI reversion score.

- `InpEnableBreakout` (default `true`)
  - Includes breakout structure score.

- `InpEnableMomentum` (default `true`)
  - Includes RSI/MACD momentum score.

- `InpEnableVolatility` (default `true`)
  - Includes ATR-regime score.

Tip: Turn off one module at a time to identify which signal family hurts PF.

---

## 5) INDICATORS

- `InpATRPeriod` (default `14`)
  - Core ATR used for stop sizing and management.

- `InpEMAFast` / `InpEMASlow` / `InpEMATrend` (default `21/55/200`)
  - Trend structure backbone.
  - Larger gaps usually reduce noise but can delay entries.

- `InpRSIPeriod` (default `14`)
  - RSI calculation period.
  - Lower = faster, noisier.

- `InpRSIOverbought` / `InpRSIOversold` (default `68/32`)
  - Reversion trigger sensitivity.
  - More extreme values reduce trade count but can improve selectivity.

- `InpBBPeriod` / `InpBBDev` (default `20 / 2.0`)
  - Bollinger context for mean reversion and volatility behavior.

- `InpADXPeriod` (default `14`)
  - ADX smoothing period.

- `InpADXTrendMin` (default `18.0`)
  - Minimum trend strength to trust trend continuation logic.
  - Increasing often helps PF but lowers frequency.

- `InpBreakoutLookback` (default `24`)
  - Window for breakout high/low detection.
  - Larger values prefer stronger structural breaks.

- `InpATRFastPeriod` / `InpATRSlowPeriod` (default `7 / 50`)
  - Volatility regime ratio.
  - Bigger separation increases regime contrast.

---

## 6) ADAPTIVE ENTRY

- `InpEntryScoreBase` (default `35.0`)
  - Main threshold to open a trade from composite score.
  - Higher = stricter entries (usually higher PF, fewer trades).

- `InpEntryScoreMin` (default `18.0`)
  - Minimum threshold floor after decay.
  - Prevents threshold from becoming too loose.

- `InpThresholdDecayBars` (default `24`)
  - Bars required before threshold decays.
  - Smaller = threshold loosens faster after no-trade periods.

- `InpThresholdDecayStep` (default `5.0`)
  - Amount threshold relaxes at each decay step.
  - Too high can overtrade low-quality setups.

- `InpGuaranteeActivity` (default `true`)
  - Allows forced entries when no trades for long periods.
  - Improves activity but can hurt forward PF if too aggressive.

- `InpForceTradeBars` (default `24`)
  - Bars without trades before forced entry logic can trigger.

- `InpForceRiskScale` (default `0.50`)
  - Risk multiplier applied to forced trades.
  - Lower is safer (`0.20` to `0.50` common for stability).

- `InpForceTradeNeedsTrend` (default `true`)
  - Requires trend confirmation before forced entries.
  - Strongly recommended for forward robustness.

---

## 7) OPTIMIZER TARGETS (used by OnTester Custom Max)

- `InpOptMinProfitFactor` (default `1.50`)
  - Hard PF floor; runs below this are scored as zero in custom objective.

- `InpOptMinTrades` (default `80`)
  - Minimum trade count floor for statistical relevance.

Note: These only affect `OnTester()` optimization score, not live entry logic.

---

## 8) EXIT / MANAGEMENT

- `InpSL_ATR_Mult` (default `1.8`)
  - Stop-loss distance in ATR units.
  - Higher = safer/wider stops, lower hit rate pressure, larger average loss.

- `InpTP_RR` (default `2.2`)
  - Take-profit distance as multiple of SL distance.
  - Higher values increase payoff asymmetry but reduce win rate.

- `InpTrailATR_Mult` (default `1.2`)
  - ATR trailing distance.
  - Tight trails lock profits quickly but can cut trends early.

- `InpBreakEvenATR` (default `1.0`)
  - Profit threshold (in ATR) before moving SL toward BE.

- `InpMaxHoldBars` (default `280`, `0` disables)
  - Time stop; closes stale positions.
  - Useful to limit overnight regime drift exposure.

- `InpStrictProtectionMode` (default `true`)
  - Requires proper SL/TP protection behavior.
  - Recommended `true` for forward safety.

- `InpMaxUnprotectedSeconds` (default `15`)
  - Emergency timeout for any position lacking SL/TP in strict mode.

---

## 9) SESSION FILTER

- `InpSessionFilter` (default `SESSION_ALL`)
  - Session gate:
  - `SESSION_ALL`, `SESSION_LONDON`, `SESSION_NEWYORK`, `SESSION_OVERLAP`, `SESSION_ASIAN`, `SESSION_NO_ASIAN`.

- `InpLondonStart` / `InpLondonEnd` (default `8/16`)
  - London session boundaries.

- `InpNYStart` / `InpNYEnd` (default `13/21`)
  - New York session boundaries.

- `InpAsianStart` / `InpAsianEnd` (default `0/8`)
  - Asian session boundaries.

- `InpNoTradeFriday` (default `false`)
  - Blocks late-Friday entries to reduce weekend-gap vulnerability.

---

## Practical tuning playbook

1. **Base edge pass**
   - Optimize: `InpEntryScoreBase`, `InpEntryScoreMin`, `InpThresholdDecayBars`, `InpTP_RR`.

2. **Exit quality pass**
   - Optimize: `InpSL_ATR_Mult`, `InpTrailATR_Mult`, `InpBreakEvenATR`, `InpMaxHoldBars`.

3. **Market robustness pass**
   - Optimize: `InpSessionFilter`, `InpSpreadFilterPoints`, `InpADXTrendMin`.

4. **Forward hardening**
   - Keep `InpStrictProtectionMode=true`, prefer `InpGuaranteeActivity=false` if forward cliff appears.

5. **Scaling**
   - Increase lot size only after stable forward PF/DD.
   - Lot size changes returns and DD, not the core PF ratio.

---

## Suggested safe profiles

- **PF-focused**: higher `InpEntryScoreBase`, `InpGuaranteeActivity=false`, tighter session/spread filters.
- **Frequency-focused**: lower entry thresholds, but keep strict protection and moderate spread filter.
- **Forward-stability**: `MaxOpenPositions=1`, `SESSION_NO_ASIAN`, `InpNoTradeFriday=true`, stricter DD caps.

