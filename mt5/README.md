# ICT Gold Breaker EA (MT5)

This EA implements the strategy framework from your transcript in a **rule-based, testable form** for MT5, with defaults tuned for **gold first** and ready for broker symbol variations (including Ultima Markets suffix formats).

## What this EA automates

1. **Higher-timeframe context (HTF)**
   - Detects 3-candle swing highs/lows.
   - Looks for a market-structure break (MSB).
   - Builds a working range (swing anchor -> post-break extension).
   - Finds an order block (last opposite candle before the break).
   - Uses midpoint as premium/discount filter.

2. **Lower-timeframe execution (LTF)**
   - Waits for breaker-style confirmation:
     - liquidity sweep of a recent swing,
     - close back through structure in trend direction.
   - Requires a fresh break trigger on the latest closed LTF bar.
   - Optionally requires sweep candle to overlap the HTF order block.

3. **Risk management and execution controls**
   - Risk-based lot sizing (`InpRiskPercent`).
   - Fixed R:R target (`InpRewardRisk`, default 2.0).
   - Spread and session filters.
   - Daily trade cap and daily loss cap.
   - Optional single-position mode.
   - Break-even automation after configured R multiple.

---

## Files

- `ICT_Gold_Breaker_EA.mq5` - MT5 Expert Advisor source code.

---

## Suggested gold-first defaults

These are already set in inputs:

- Symbol: `""` (auto-uses chart symbol; recommended for brokers with suffixes)
- HTF: `H4`
- LTF: `M15`
- Risk: `0.50%` per trade
- RR: `2.0`
- Max spread: `0` points (disabled by default for smoother optimization)
- Session filter: `OFF` by default
- Max trades/day: `0` (disabled by default)
- Max daily loss: `0` (disabled by default)

You should still optimize these per your broker feed and execution quality.

---

## Installation

1. Open MT5.
2. Go to `File -> Open Data Folder`.
3. Copy `ICT_Gold_Breaker_EA.mq5` into `MQL5/Experts/`.
4. In MetaEditor, compile the file.
5. Attach EA to your broker's gold chart (for example `XAUUSD`, `XAUUSDm`, etc.).
6. Enable Algo Trading.

### Ultima Markets note

For Ultima Markets backtesting/optimization:

- Keep `InpSymbol` empty (`""`) so the EA automatically uses the exact tester chart symbol.
- Run optimization on your gold symbol in that server (including any suffix/prefix).
- After optimization, optionally re-enable spread/session/day-risk guards for live use.

---

## Optimization workflow (important)

1. In Strategy Tester, pick high-quality tick data for XAUUSD.
2. Optimize in stages:
   - Stage 1: structural parameters  
     (`InpHTF`, `InpLTF`, `InpOrderBlockSearchBars`, `InpPatternLookbackBars`)
   - Stage 2: execution parameters  
     (`InpBreakBufferPoints`, `InpSweepBufferPoints`, `InpMaxSweepToBreakBars`)
   - Stage 3: risk parameters  
     (`InpRiskPercent`, `InpRewardRisk`, `InpBreakEvenAtR`)
3. Validate out-of-sample on unseen date ranges.
4. Forward test on demo before any live deployment.

---

## Reality check

No EA can guarantee being "highly profitable" in all conditions.  
This implementation focuses on:

- strategy fidelity,
- disciplined risk controls,
- optimization-ready inputs,
- repeatable execution.

Profitability depends on data quality, broker conditions, regime changes, and robust walk-forward validation.
