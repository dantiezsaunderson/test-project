# Goldman Sachs Systematic Trading Desk - Quantitative Strategy Memorandum

**Document type:** Strategy Architecture Memo  
**Strategy code:** AURIC-MSX (Adaptive Unified Regime-Informed Composite, Multi-Strategy Execution)  
**Primary market:** XAU/USD (spot or CFD execution)  
**Secondary deployment:** Major FX pairs, index CFDs/futures, liquid commodity symbols  
**Horizon mix:** Sub-minute scalping, intraday tactical, multi-day swing  

---

## 1) Investment Thesis and Market Inefficiency

### Core thesis
XAU/USD exhibits persistent and exploitable structure across multiple horizons:

1. **Microstructure imbalance** in liquid sessions (London/NY overlap) supports short-horizon scalping.
2. **Volatility clustering and breakout persistence** after compression supports momentum systems.
3. **Short-horizon mean reversion** around intraday fair value (VWAP) in range regimes.
4. **Range-bound inventory rebalancing** enables controlled grid capture when trend risk is explicitly filtered.
5. **Macro/trend persistence** on H4/D1 enables swing-following overlays.

No finite engine can include literally "every known profitable strategy."  
This architecture captures the major orthogonal alpha families (microstructure, trend, mean-reversion, volatility transition, market making/grid, and swing trend) with a unified risk layer.

---

## 2) Universe Selection

### Primary execution universe (Tier 1)
- **XAU/USD spot/CFD** (primary alpha source and optimization target)
- **COMEX Gold futures (GC, MGC)** for institutional benchmark and robustness checks
- **Gold ETFs (GLD, IAU)** for cross-venue confirmation of trend regime

### Secondary expansion universe (Tier 2)
- **G10 FX majors:** EURUSD, GBPUSD, USDJPY, AUDUSD, USDCAD, USDCHF, NZDUSD
- **Metal/commodity proxies:** XAG/USD, XPT/USD, XBR/USD (if available with reliable execution)
- **Index futures/CFDs:** ES, NQ, DAX, FTSE (for transfer-learning tests)

### Selection rationale
- High liquidity, tight spreads, and strong session effects.
- Mixture of trend and mean-reverting behavior by regime.
- Strong transferability of volatility-scaled signal logic across symbols.

---

## 3) Data, Features, and Regime Engine

## 3.1 Base definitions

Let:
- \( P_t \): mid-price at time \( t \)
- \( r_t = \ln(P_t / P_{t-1}) \): log return
- \( TR_t = \max(H_t-L_t,\ |H_t-C_{t-1}|,\ |L_t-C_{t-1}|) \)
- \( ATR_n(t) = EMA_n(TR_t) \)
- \( VWAP_{sess}(t) \): session VWAP

Realized volatility estimate:
\[
\hat{\sigma}_{t,n}=\sqrt{252 \cdot \frac{1}{n}\sum_{i=1}^{n}r_{t-i}^2}
\]

### 3.2 Core normalized features

1. **Trend score**
\[
TS_t=\tanh\left(\frac{EMA_{20}(t)-EMA_{100}(t)}{1.5\cdot ATR_{14}(t)}\right)
+0.5\cdot\tanh\left(\frac{EMA_{50}(t)-EMA_{50}(t-10)}{ATR_{14}(t)}\right)
\]

2. **VWAP deviation z-score**
\[
Z_t=\frac{P_t-VWAP_{sess}(t)}{0.8\cdot ATR_{14}(t)}
\]

3. **Breakout score**
\[
BO_t^{long}=\frac{P_t-DonchianHigh_{20}(t)}{ATR_{14}(t)},\quad
BO_t^{short}=\frac{DonchianLow_{20}(t)-P_t}{ATR_{14}(t)}
\]

4. **Tick/order-flow imbalance proxy**
\[
OFI_t=\frac{\sum_{k=1}^{m} sign(\Delta p_k)\cdot v_k}{\sum_{k=1}^{m}v_k}
\]
(Use true tick volume proxy if level-2 data unavailable.)

5. **Volatility percentile**
\[
VP_t = PercentileRank(ATR_{14}(t),\ 252)
\]

### 3.3 Regime classification (deterministic)

Regime labels:
- **Trend:** \( ADX_{14}\ge 22 \) and \( |TS_t|\ge 0.20 \)
- **Range:** \( ADX_{14}<18 \) and \( |TS_t|<0.15 \)
- **Transition:** otherwise

Volatility state:
- **Low/normal vol:** \( VP_t \le 0.75 \)
- **High vol:** \( VP_t > 0.75 \)

---

## 4) Signal Stack (Multi-Strategy Alpha Modules)

All modules output normalized directional signal \( s_i \in [-1,1] \).

## S1) High-speed micro scalper (M1 + tick)

Raw score:
\[
raw_1 = 0.45\cdot OFI_{30s}
+0.35\cdot\frac{P_t - VWAP_{5m}}{0.25\cdot ATR_{1m}}
+0.20\cdot\frac{P_t-P_{t-20ticks}}{ATR_{1m}}
\]
\[
s_1=\text{clip}(raw_1,-1,1)
\]

**Entry conditions (all true):**
- \( s_1 > 0.65 \) for long, \( s_1 < -0.65 \) for short
- Spread \( \le 1.10 \times \) 30-min median spread
- Not in blackout window around high-impact events (default +/- 5 min)
- Session filter: London/NY liquid hours

**Exit:**
- TP = \(0.35 \cdot ATR_{1m}\)
- SL = \(0.25 \cdot ATR_{1m}\)
- Time stop = 180 seconds
- Signal reversal exit if \( s_1 \) crosses opposite sign with magnitude \(>0.20\)

## S2) Intraday momentum breakout (M5/M15)

\[
raw_2=0.50\cdot BO_t +0.30\cdot TS_t +0.20\cdot\text{clip}\left(\frac{ADX_{14}-20}{20},-1,1\right)
\]
\[
s_2=\text{clip}(raw_2,-1,1)
\]

**Entry conditions (all true):**
- Long: \( Close > DonchianHigh_{20} + 0.10\cdot ATR_{14} \)
- Short: \( Close < DonchianLow_{20} - 0.10\cdot ATR_{14} \)
- \( ADX_{14} > 22 \)
- \( |TS_t| > 0.25 \)
- Not in news blackout (default +/- 15 min)

**Exit:**
- Initial SL = \(1.2\cdot ATR_{14}\)
- TP1 = 1.5R (close 50%)
- TP2 = Chandelier trail \(3.0\cdot ATR_{14}\)
- Time stop = 24 bars on M5 (about 2 hours)
- Reversal exit on opposite breakout confirmation

## S3) Intraday mean reversion (M5)

\[
raw_3 = -Z_t \cdot \left(1-\min(1,\frac{ADX_{14}}{30})\right),\quad
s_3=\text{clip}(raw_3,-1,1)
\]

**Entry conditions (all true):**
- Long: \( Z_t \le -2.0 \)
- Short: \( Z_t \ge +2.0 \)
- \( ADX_{14} < 18 \)
- Bollinger bandwidth below 60th percentile of last 60 bars

**Exit:**
- Primary target: return to VWAP (or \( Z_t \) crosses -0.2/+0.2)
- Hard TP = \(1.3\cdot ATR_{14}\)
- SL = \(1.0\cdot ATR_{14}\)
- Time stop = 18 bars on M5 (about 90 min)
- Reversal exit if \( Z_t \) overshoots opposite side beyond 1.5

## S4) Volatility squeeze breakout (M15/H1)

Squeeze definition:
- \( BBWidth_{20} \le P20(BBWidth_{252}) \) for at least 8 bars
- rising volatility transition condition: \( \Delta ATR_{14} > 0 \)

Signal:
\[
raw_4 = \frac{Close - RangeMid_{20}}{RangeWidth_{20}/2},\quad
s_4=\text{clip}(raw_4,-1,1)
\]

**Entry conditions (all true):**
- Long breakout above \( High_{20} + 0.05\cdot ATR_{14} \)
- Short breakout below \( Low_{20} - 0.05\cdot ATR_{14} \)
- Tick volume \(> 1.2 \times SMA_{20}(\text{tick volume})\)

**Exit:**
- SL = \(1.4\cdot ATR_{14}\)
- TP = \(2.8\cdot ATR_{14}\) or trailing stop at \(2.0\cdot ATR_{14}\)
- Time stop = 16 bars on M15 (about 4 hours)

## S5) Adaptive grid market making (M1/M5, range-only)

**Enable only if all true:**
- \( ADX_{14} < 15 \)
- \( |TS_t| < 0.15 \)
- \( 0.15 \le VP_t \le 0.65 \)
- No high-impact event within +/- 30 minutes

Grid:
- Anchor \( A = VWAP_{sess} \)
- Spacing \( g = 0.35\cdot ATR_{14}(M5) \)
- Levels: \( A \pm k\cdot g,\ k=1..4 \)

Order logic:
- Buy limits below anchor; sell limits above anchor
- Each fill TP at next inner grid level
- SL per leg = \(1.2g\)

Inventory controls:
- Max net grid inventory = 2.5 x base grid lot
- Emergency flatten if \( |P_t-A| > 1.8\cdot ATR_{14} \) OR \( ADX_{14}>20 \)
- Hard disable for 60 minutes after emergency flatten

## S6) Swing trend overlay (H4/D1)

\[
Trend_{D1}=\frac{EMA_{50,D1}-EMA_{200,D1}}{1.5\cdot ATR_{20,D1}}
\]
\[
Break_{55}=\frac{Close_{D1}-DonchianHigh_{55,D1}}{ATR_{20,D1}}
\]
\[
raw_6=0.4\cdot Trend_{D1}+0.3\cdot Break_{55}+0.3\cdot PullbackScore_{H4}
\]
\[
s_6=\text{clip}(raw_6,-1,1)
\]

**Entry conditions (all true):**
- Long: \( EMA_{50,D1}>EMA_{200,D1} \), \( ADX_{D1}>20 \), valid H4 pullback and bullish re-entry trigger
- Short: symmetric bearish conditions

**Exit:**
- SL = \(2.5\cdot ATR_{H4}\)
- Initial TP = \(4.0\cdot ATR_{H4}\)
- Trail with \(3.0\cdot ATR_{H4}\) after +2R
- Time stop = 15 trading days
- Trend reversal exit on EMA cross

---

## 5) Entry/Exit Orchestration and Signal Arbitration

### 5.1 Regime risk budget (percent of deployable daily risk)

| Strategy | Trend/Low Vol | Trend/High Vol | Range/Low Vol | Range/High Vol |
|---|---:|---:|---:|---:|
| S1 Micro scalper | 15% | 10% | 10% | 5% |
| S2 Momentum breakout | 30% | 35% | 10% | 15% |
| S3 Mean reversion | 5% | 0% | 30% | 20% |
| S4 Squeeze breakout | 15% | 25% | 10% | 20% |
| S5 Adaptive grid | 0% | 0% | 30% | 5% |
| S6 Swing trend | 35% | 30% | 10% | 35% |

### 5.2 Conflict rules
- If trend strategies (S2/S6) and mean-reversion/grid (S3/S5) conflict, prioritize regime-majority signals.
- If \( ADX_{14}>22 \), automatically set S5 risk budget to zero.
- If open risk exceeds cap, keep higher expected value signal:
  \[
  EV_i = p_i \cdot W_i - (1-p_i)\cdot L_i
  \]
  where \( p_i \) is rolling hit-rate estimate, \( W_i \) average win, \( L_i \) average loss.

---

## 6) Position Sizing Model

Let:
- \( E_t \): current equity
- \( R_{day} \): max deployable daily risk fraction (default 0.80%)
- \( b_{i,r} \): budget weight for strategy \( i \) in regime \( r \)
- \( c_i = \text{clip}(|s_i|/\theta_i, 0.5, 1.5) \): conviction multiplier
- \( \lambda_t = \text{clip}(\sigma^*/\hat{\sigma}_{20}, 0.5, 1.5) \): vol-targeting scaler

Per-strategy risk:
\[
RiskUSD_i = E_t \cdot R_{day} \cdot b_{i,r} \cdot c_i \cdot \lambda_t
\]

Lot size:
\[
Lots_i=\frac{RiskUSD_i}{SL_{pips,i}\cdot PipValue}
\]
(Round to broker minimum lot step and max notional rules.)

### Portfolio overlay constraints
- Total open risk:
\[
\sum_i OpenRisk_i \le 3.5\%\cdot E_t
\]
- Maximum gross leverage: 4.0x notional equivalent (default for XAU/FX mix)
- Single-trade risk cap:
  - S1: 0.15% equity
  - S2/S3/S4: 0.25% equity
  - S5: 0.10% per leg, 0.40% aggregate
  - S6: 0.35% equity

---

## 7) Risk Parameters (Institutional Guardrails)

| Risk Control | Parameter | Action if breached |
|---|---:|---|
| Soft drawdown limit | 8% from high-water mark | Reduce all risk budgets by 50% |
| Hard drawdown limit | 12% from high-water mark | Flatten all, disable trading, require revalidation |
| Daily loss limit | 2.0% equity | Flatten and halt until next UTC day |
| Weekly loss limit | 4.0% equity | Next week risk budgets reduced 35% |
| Max open positions | 12 total | Reject new entries until below limit |
| Max correlated cluster risk | 35% of open risk | Scale down smallest-conviction positions |
| Pairwise correlation threshold | \(|\rho_{60d}| > 0.75\) | Reduce smaller position by factor \(1-(|\rho|-0.75)/0.25\) |
| Sector cap: precious metals | 40% risk | Block additional metal exposure |
| Sector cap: USD-linked FX bucket | 50% risk | Block additional USD-correlated exposure |
| Slippage breach monitor | 2 consecutive fills > 95th pct expected slippage | Disable affected strategy for 60 min |

---

## 8) Backtesting and Research Framework

## 8.1 Data requirements
- Tick bid/ask history for XAU/USD (minimum 8-10 years if possible)
- Historical spread and trading-session metadata
- High-impact macro calendar timestamps (NFP, CPI, FOMC, ECB, BOE)
- Optional cross-asset features (DXY, US10Y real-yield proxy)

## 8.2 Simulation quality standards
- Event-driven tick simulation (not bar-close only)
- Realistic order book assumptions:
  - Market orders cross spread at touch
  - Limit orders fill only on touched-through price with queue probability
- Commission + spread + slippage model:
\[
Slippage_t = a + b\cdot \sigma_{1m,t} + c\cdot \frac{OrderSize}{ADV_t}
\]

## 8.3 Validation protocol
1. **Anchored walk-forward**
   - Train: 24 months
   - Validate: next 3 months
   - Roll forward monthly
2. **Purged CV / embargo**
   - Prevent leakage from overlapping labels
3. **Robustness tests**
   - Spread x1.5 and x2.0
   - Slippage +1 standard deviation
   - Latency shock +150ms and +300ms
4. **Monte Carlo trade-path bootstrap**
   - 10,000 resamples of trade sequence

## 8.4 Promotion criteria (research to production)
- Out-of-sample Sharpe >= 1.20
- Calmar >= 1.00
- Profit factor >= 1.25
- Max drawdown <= 12%
- Deflated Sharpe Ratio passes 5% significance
- Performance stable across at least 3 distinct macro regimes

---

## 9) Benchmark Framework

### Primary benchmark
1. **Vol-targeted XAU/USD buy-and-hold (12% annualized vol target)**  
Best apples-to-apples baseline versus an active strategy with volatility control.

### Secondary benchmarks
2. **Raw XAU/USD buy-and-hold**
3. **Simple 50/200 EMA trend system on XAU/USD**
4. **Cash benchmark (SOFR or broker cash yield proxy)**

### Why this benchmark set
- Captures both passive metal beta and standard systematic trend beta.
- Distinguishes true alpha from leverage/volatility engineering.

---

## 10) Edge Decay Monitoring (Live Production)

Track each strategy and aggregate portfolio with rolling control charts:

1. **Rolling expectancy**
\[
Exp_{60} = \frac{1}{60}\sum_{j=1}^{60}R_j
\]

2. **Performance drift z-score**
\[
Z_{drift} = \frac{\mu_{live,90d}-\mu_{OOS}}{\sigma_{OOS}/\sqrt{N}}
\]

3. **Feature drift (Population Stability Index)**
- PSI > 0.20: caution
- PSI > 0.30: critical

4. **Execution drift**
- Live slippage vs modeled slippage spread

### Decay trigger policy
- **Yellow state** (any 2 conditions):
  - \( Exp_{60} < 0 \)
  - 90-day Sharpe < 50% of expected OOS Sharpe
  - PSI > 0.20
  - Action: cut strategy risk budget by 50%
- **Red state** (any 1 condition):
  - \( Exp_{100} < -0.15R \)
  - Live drawdown exceeds 95th percentile simulated drawdown
  - \( |Z_{drift}| > 2.58 \) (about 99% confidence break)
  - Action: disable strategy, trigger research review and re-calibration

---

## 11) EA Pseudocode (Implementation Blueprint)

```pseudo
on_tick(symbol):
    update_tick_cache(symbol)
    update_multitimeframe_bars(symbol)
    update_features(symbol)

    if global_kill_switch_triggered():
        flatten_all_positions()
        return

    regime = classify_regime(ADX14, TS, VP)
    budget = risk_budget_table[regime]
    vol_scaler = clip(target_vol / realized_vol_20d, 0.5, 1.5)

    for strategy in [S1, S2, S3, S4, S5, S6]:
        if not strategy_enabled(strategy):
            continue
        if not preconditions_ok(strategy, spread, session, news, regime):
            continue

        s = compute_signal(strategy, features)     # in [-1, 1]
        if abs(s) < strategy.entry_threshold:
            manage_existing_positions(strategy, s)
            continue

        conviction = clip(abs(s)/strategy.entry_threshold, 0.5, 1.5)
        risk_usd = equity * daily_risk * budget[strategy] * conviction * vol_scaler
        size = risk_usd / stop_value_usd(strategy, current_atr)
        size = apply_correlation_and_sector_caps(size, strategy, portfolio_state)

        if risk_checks_pass(strategy, size, portfolio_state):
            place_orders(strategy, direction=sign(s), size=size)

    enforce_position_limits()
    enforce_drawdown_limits()
    log_metrics_and_drift_stats()
```

---

## 12) Starting Parameters for XAU/USD (Backtest-Ready)

Use these as initial values before walk-forward optimization.

| Parameter | Default | Search Range | Step |
|---|---:|---:|---:|
| ATR period | 14 | 10-30 | 2 |
| ADX trend threshold | 22 | 18-30 | 1 |
| ADX range threshold | 18 | 12-22 | 1 |
| TS trend threshold | 0.20 | 0.10-0.40 | 0.05 |
| S1 entry threshold | 0.65 | 0.50-0.85 | 0.05 |
| S1 TP (ATR1m) | 0.35 | 0.20-0.60 | 0.05 |
| S1 SL (ATR1m) | 0.25 | 0.15-0.45 | 0.05 |
| S2 Donchian length | 20 | 15-55 | 5 |
| S2 breakout buffer (ATR) | 0.10 | 0.00-0.30 | 0.05 |
| S2 SL (ATR) | 1.20 | 0.8-2.0 | 0.2 |
| S3 z-entry abs value | 2.00 | 1.2-3.0 | 0.2 |
| S3 SL (ATR) | 1.00 | 0.8-1.6 | 0.1 |
| S4 squeeze percentile | 20 | 10-35 | 5 |
| S4 SL (ATR) | 1.40 | 1.0-2.2 | 0.2 |
| S5 grid spacing (ATR) | 0.35 | 0.20-0.60 | 0.05 |
| S5 grid levels per side | 4 | 2-6 | 1 |
| S5 emergency distance (ATR) | 1.80 | 1.2-2.5 | 0.1 |
| S6 stop (ATR H4) | 2.50 | 1.5-4.0 | 0.5 |
| Daily risk deployable | 0.80% | 0.30%-1.20% | 0.10% |
| Hard portfolio DD | 12.0% | 8%-15% | 1% |

---

## 13) Implementation Notes for "Works in All Markets/Pairs"

To port from XAU/USD to other symbols, do **not** retune from scratch:
1. Keep signal forms unchanged.
2. Normalize all thresholds by ATR/volatility.
3. Re-estimate only:
   - spread/slippage model coefficients
   - session liquidity filters
   - volatility percentile mapping
4. Re-run walk-forward with the same parameter grid logic.

This maintains structural consistency and avoids overfitting to one instrument.

---

## 14) Governance and Deployment

- Run paper-trading shadow mode for 4 weeks before capital deployment.
- Capital ramp: 10% -> 25% -> 50% -> 100% after each monthly risk review.
- Mandatory weekly model risk report:
  - PnL attribution by strategy
  - capacity and slippage drift
  - benchmark-relative alpha
  - decay-state dashboard (green/yellow/red)

---

## 15) Practical Summary

This architecture gives you:
- A true **multi-strategy EA framework** from scalping to swing.
- Explicit formulas, entries, exits, and risk caps.
- A realistic **institutional backtesting process**.
- A parameter set that is immediately backtestable on XAU/USD and portable to other symbols.

If you want, the next step is converting this memo directly into:
1) an MT5 EA module layout (`RegimeEngine.mqh`, `RiskManager.mqh`, `SignalS1..S6.mqh`), and  
2) a CSV/JSON parameter pack for automated walk-forward runs.
