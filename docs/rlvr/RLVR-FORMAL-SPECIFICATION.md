# RLVR Formal Specification v1.0

**System**: Reclaimed Liquidity Void Reset  
**Platform**: MetaTrader 5 (MQL5)  
**Symbol**: XAUUSD (broker-adaptive)  
**Document type**: Implementation-ready design specification  
**Status**: Draft for build  
**Martingale role**: Secondary, bounded recovery layer only  

---

## 0. Document control

| Field | Value |
|---|---|
| Version | 1.0.0 |
| Authors | Strategy design session |
| Depends on | Concept design phases 1–10 (RLVR selected) |
| Implementation target | Single-chart EA, one active basket maximum |
| Non-goals | Hedging grids, symmetric pip grids, blind doubling, multi-symbol portfolio v1 |

### Revision policy

Any change to **structural invalidation**, **max ladder depth**, or **forced-flatten priority** requires version bump and re-validation.

---

## 1. Glossary

| Term | Definition |
|---|---|
| **L** | Reference liquidity level (session/day/equal-high-low pool) |
| **Sweep** | Penetration of L beyond minimum depth within sweep window |
| **Void** | Price interval between L and sweep extreme E |
| **Reclaim** | M5 close back on prior side of L after sweep |
| **Acceptance** | Sustained trade beyond L suggesting true breakout (failure of fade thesis) |
| **Rung** | Predefined void-relative add location R0–R4 |
| **Basket** | All positions opened for one RLVR event |
| **U₀** | Base unit lot size after equity scaling |
| **TTL** | Time-to-live for thesis validity |
| **ARMED** | Level tagged; system waiting for sweep |

---

## 2. System thesis (implementation anchor)

RLVR trades **inventory rebalance after failed acceptance** following a liquidity sweep of a pre-qualified reference level.

**Standalone edge (no martingale):**  
If sweep depth ∈ [d_min, d_max], reclaim occurs within reclaim_TTL, and acceptance does not occur, then fade direction has positive expectancy to void midpoint with structural stop at E + buffer.

**Martingale role:**  
If price moves adversely after R0 while reclaim remains valid, add at void rungs R1–R4 under capped geometric sizing to improve basket breakeven and closure probability. Adds are forbidden without structural eligibility.

---

## 3. Architecture

### 3.1 Module map

```
┌─────────────────────────────────────────────────────────────┐
│                     RLVR EA (OnTick/OnTimer)                │
├─────────────────────────────────────────────────────────────┤
│  Clock & Session Manager                                    │
│  News Calendar Gate                                         │
│  Regime Filter                                              │
│  Levels Engine ──► Active Level Queue (max 3 armed)           │
│  Sweep Detector                                             │
│  Reclaim Detector                                           │
│  State Machine Controller                                   │
│  Entry Engine (R0)                                            │
│  Recovery Engine (R1–R4)                                      │
│  Basket Manager (PnL, VWAP, age, depth)                     │
│  Exit Manager (partial, trail, basket TP, flatten)          │
│  Risk Manager (DD, margin, exposure)                        │
│  Anti-Blowup Controller (kill-switches, cooldown)           │
│  Telemetry Logger                                           │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Execution model

| Setting | Value |
|---|---|
| Event clock | `OnTimer(1s)` for state/TTL; M5 bar events for structure |
| Order type | Market execution for entries; no pending limits in v1 |
| Magic number | Configurable; single strategy magic |
| Position comment | `RLVR|{level_id}|R{n}|{state}` |
| Max concurrent baskets | 1 |
| Max concurrent armed levels | 3 (different L); only 1 may progress to basket |

### 3.3 Timeframe hierarchy

| TF | Role |
|---|---|
| D1 | Prior day high/low (PDH/PDL) |
| H1 | Prior session H/L (Asia, London), swing structure for runaway detector |
| M15 | ATR regime, vol kill-switch |
| M5 | Sweep, reclaim, acceptance, invalidation (primary structure TF) |
| M1 | Optional: sweep extremum precision (v1.1) |

---

## 4. Data model

### 4.1 Level object (`LiquidityLevel`)

```text
level_id          : string   // e.g. "PDH_2025-06-10"
type              : enum     // PDH, PDL, PSH, PSL, ASIA_H, ASIA_L, LONDON_H, LONDON_L, EQH, EQL, ROUND
price             : double   // L
quality_score     : double   // 0.0–1.0
created_at        : datetime
expires_at        : datetime
session_tag       : enum
state             : enum     // IDLE, ARMED, SWEEP_DETECTED, RECLAIM_CONFIRMED, CONSUMED, EXPIRED
sweep_extreme     : double   // E, updated during sweep
sweep_start_time  : datetime
reclaim_time      : datetime
direction         : enum     // FADE_SELL (sweep above), FADE_BUY (sweep below)
void_midpoint     : double   // (L + E) / 2
```

### 4.2 Basket object (`Basket`)

```text
basket_id         : string
level_id          : string
direction         : enum
open_time         : datetime
positions         : array<PositionLeg>
depth             : int      // 0–4
vwap_price        : double
gross_lots        : double
floating_pnl      : double
floating_dd_pct   : double
max_adverse_exc   : double   // worst price vs basket
max_favorable_exc : double
age_seconds       : int
reclaim_valid     : bool
state             : enum     // see state machine
```

### 4.3 Position leg (`PositionLeg`)

```text
ticket            : ulong
rung              : int      // 0–4
lots              : double
open_price        : double
open_time         : datetime
```

### 4.4 Global runtime (`SystemState`)

```text
ea_state          : enum     // global EA mode
active_basket     : Basket | null
armed_levels      : array<LiquidityLevel>
cooldown_until    : datetime
daily_pnl_pct     : double
daily_dd_pct      : double
weekly_dd_pct     : double
last_emergency    : datetime
regime_snapshot   : RegimeFlags
```

---

## 5. Levels engine

### 5.1 Level sources (priority order)

Levels are computed at session boundaries and stored in a queue. Higher priority wins if prices are within `level_merge_distance`.

| Priority | Type | Definition | Expiry |
|---:|---|---|---|
| 1 | PDH / PDL | Prior D1 high/low (broker day) | End of current D1 |
| 2 | ASIA_H / ASIA_L | High/low of 00:00–07:59 server (configurable) | London open + 4h |
| 3 | LONDON_H / LONDON_L | High/low of 08:00–12:59 server | NY open + 4h |
| 4 | EQH / EQL | Most recent equal highs/lows (≥2 touches, ±merge) | 24h or until consumed |
| 5 | ROUND | Round numbers every `round_step` (default 50.0) near price | Rolling 12h |

### 5.2 Level quality score

Each level receives `quality_score` ∈ [0, 1]:

```text
score = w1 * touch_count_norm
      + w2 * recency_norm
      + w3 * session_relevance
      + w4 * round_number_bonus
```

Default weights: w1=0.35, w2=0.25, w3=0.30, w4=0.10

**Arm threshold:** `quality_score >= 0.55`

### 5.3 Level merge rule

If two levels are within:

```text
level_merge_distance = max(0.10 * ATR_M15, spread * 5)
```

keep higher-priority level only.

### 5.4 Equal highs/lows detection

- Swing pivot on M15: fractal lookback = 3/3
- Equal cluster if ≥2 pivots within `equal_hl_tolerance = 0.08 * ATR_M15`
- EQH = cluster max; EQL = cluster min

### 5.5 Round number filter

- `round_step = 50.0` for XAUUSD (input)
- Only arm round levels if current price within `0.5 * ATR_H1` of round level

---

## 6. Regime filter

All conditions must pass to transition from global `IDLE` to level `ARMED`.

### 6.1 Regime flags (`RegimeFlags`)

| Flag | Pass condition |
|---|---|
| `session_liquid` | Server hour ∈ [07:00, 20:00] OR explicit Asia mode disabled |
| `news_clear` | No tier-1 event ±30m; no tier-2 ±15m |
| `vol_ok` | ATR_M15 ∈ [p20, p95] of 60-day rolling distribution |
| `not_runaway` | No 4h displacement > 3.0 × ATR_H1 without 0.5 × ATR_H1 pullback |
| `spread_ok` | Current spread <= 2.5 × median spread (30-day rolling, same hour) |
| `cooldown_clear` | `TimeCurrent() >= cooldown_until` |
| `daily_dd_ok` | `daily_dd_pct < daily_dd_limit` |
| `no_active_basket` | `active_basket == null` |

### 6.2 ATR percentile calculation

- Store daily ATR_M15 values for 60 days
- p20, p95 by sorted interpolation
- Recompute at D1 open

### 6.3 Trend-runaway detector

```text
displacement_4h = abs(price_now - price_4h_ago)
if displacement_4h > 3.0 * ATR_H1:
    pullback = max pullback against displacement since impulse start
    if pullback < 0.5 * ATR_H1:
        not_runaway = false
```

---

## 7. Sweep detector

Operates on armed levels only.

### 7.1 Sweep initiation

For level L with side:

- **Upside pool** (fade sell): track sweeps above L
- **Downside pool** (fade buy): track sweeps below L

**Sweep start** when price penetrates:

```text
d_min = sweep_depth_min_atr * ATR_M5    // default 0.15
penetration >= d_min
```

Record:
- `sweep_start_time = now`
- `sweep_extreme E` = current extremum since penetration
- level state → `SWEEP_DETECTED`

### 7.2 Sweep window

```text
sweep_window_bars = 20   // M5 bars
```

If no valid reclaim and window expires → level state `EXPIRED`, return to scan.

### 7.3 Sweep depth disqualification

If penetration exceeds:

```text
d_max = sweep_depth_max_atr * ATR_M5    // default 0.80
```

Mark as **true breakout candidate** → level `EXPIRED` (do not fade). Log `SWEEP_TOO_DEEP`.

### 7.4 Sweep extremum update

While in `SWEEP_DETECTED`, update E on new M5 bar:

- Upside: `E = max(E, bid_high)`
- Downside: `E = min(E, bid_low)`

---

## 8. Reclaim detector

### 8.1 Reclaim confirmation

On **M5 bar close**:

**Upside sweep (fade sell):**

```text
reclaim if close < L
```

**Downside sweep (fade buy):**

```text
reclaim if close > L
```

Optional quality filter (enabled by default):

```text
rejection_body = abs(close - open) / (high - low) >= 0.30
close in outer 30% of candle toward reclaimed side
```

### 8.2 Reclaim TTL

```text
reclaim_ttl_seconds = 5400   // 90 minutes from sweep_start_time
```

If reclaim not confirmed before TTL → `EXPIRED`.

### 8.3 Reclaim acceptance

On reclaim:
- `reclaim_time = now`
- `void_midpoint = (L + E) / 2`
- `direction` set (FADE_SELL / FADE_BUY)
- level state → `RECLAIM_CONFIRMED`
- trigger Entry Engine R0

---

## 9. Acceptance / invalidation detector

Thesis invalidation is **structural**, evaluated on M5 close unless emergency.

### 9.1 Hard invalidation (immediate flatten)

| ID | Condition |
|---|---|
| INV-1 | Upside fade: M5 close > E + invalidation_buffer |
| INV-2 | Downside fade: M5 close < E - invalidation_buffer |
| INV-3 | `now - sweep_start_time > reclaim_ttl_seconds` while basket open |
| INV-4 | Vol kill: ATR_M5 > vol_kill_atr_mult × entry_ATR_M5 (default 2.0) |
| INV-5 | Spread kill: spread > spread_kill_mult × entry_spread (default 3.0) |
| INV-6 | Re-acceptance: M5 close beyond L by acceptance_distance |

Where:

```text
invalidation_buffer = 0.10 * ATR_M5
acceptance_distance = 0.20 * ATR_M5 beyond L
```

### 9.2 Soft invalidation (no new adds; manage exit)

| ID | Condition |
|---|---|
| SOFT-1 | Basket age > 0.5 × reclaim_ttl AND floating_dd_pct > 0.5 × basket_dd_limit |
| SOFT-2 | M15 structure break against basket (swing break) |

---

## 10. State machine

### 10.1 Global EA states

| State | Description |
|---|---|
| `OFF` | EA disabled / init |
| `IDLE` | Scanning, no basket |
| `BASKET_ACTIVE` | One basket open |
| `COOLDOWN` | Post-exit pause |
| `DEFENSIVE_HALT` | Circuit breaker; manual or auto reset |

### 10.2 Per-level states

`IDLE → ARMED → SWEEP_DETECTED → RECLAIM_CONFIRMED → CONSUMED | EXPIRED`

### 10.3 Basket sub-states

| State | Code |
|---|---|
| Initial entry | `INITIAL_ENTRY` |
| Controlled adverse | `CONTROLLED_ADVERSE` |
| Recovery eligible | `RECOVERY_ELIGIBLE` |
| Rescue active | `RESCUE_ACTIVE` |
| Profit compression | `PROFIT_COMPRESSION` |
| Basket exit | `BASKET_EXIT` |
| Defensive shutdown | `DEFENSIVE_SHUTDOWN` |

### 10.4 Transition table

| From | Event | Guard | Action | To |
|---|---|---|---|---|
| IDLE | level qualified | regime OK | tag level ARMED | ARMED |
| ARMED | penetration ≥ d_min | regime OK | record sweep | SWEEP_DETECTED |
| SWEEP_DETECTED | penetration > d_max | — | expire level | EXPIRED |
| SWEEP_DETECTED | reclaim M5 close | TTL OK | set direction | RECLAIM_CONFIRMED |
| SWEEP_DETECTED | sweep window timeout | — | expire | EXPIRED |
| RECLAIM_CONFIRMED | R0 filled | risk OK | open basket | INITIAL_ENTRY |
| INITIAL_ENTRY | price adverse | — | monitor | CONTROLLED_ADVERSE |
| INITIAL_ENTRY | favorable | — | manage | PROFIT_COMPRESSION |
| CONTROLLED_ADVERSE | rung hit + reclaim valid | depth < max | add leg | RECOVERY_ELIGIBLE → RESCUE_ACTIVE |
| CONTROLLED_ADVERSE | invalidation | — | flatten | DEFENSIVE_SHUTDOWN |
| RESCUE_ACTIVE | partial TP hit | — | close partial | PROFIT_COMPRESSION |
| RESCUE_ACTIVE | max depth | no invalidation | no more adds | CONTROLLED_ADVERSE |
| PROFIT_COMPRESSION | basket TP | — | close all | BASKET_EXIT |
| PROFIT_COMPRESSION | trail stop | — | close all | BASKET_EXIT |
| * | daily DD breach | — | flatten all | DEFENSIVE_HALT |
| BASKET_EXIT | — | — | start cooldown | COOLDOWN |
| DEFENSIVE_SHUTDOWN | — | — | cooldown + count failure | COOLDOWN |
| COOLDOWN | timer elapsed | regime OK | resume scan | IDLE |

---

## 11. Entry engine (R0)

### 11.1 Trigger

Execute within `entry_delay_seconds` (default 0–5s) after reclaim bar close confirmation.

### 11.2 Direction

| Sweep | R0 direction |
|---|---|
| Above L | SELL |
| Below L | BUY |

### 11.3 Initial stop (virtual; enforced by invalidation)

Not a broker SL in v1 (avoids stop hunting); EA monitors INV-1/2.

Optional protective SL for brokerage compliance:

```text
SL_distance = (abs(E - L) + invalidation_buffer) * 1.10
```

### 11.4 R0 sizing

```text
U0 = floor_to_lot_step( equity * risk_per_basket / worst_case_loss_per_unit )
```

Default `risk_per_basket = 0.0125` (1.25% equity)

Worst case = full ladder to R4 + invalidation slippage estimate.

---

## 12. Recovery engine (R1–R4)

### 12.1 Recovery eligibility

ALL required:

```text
reclaim_valid == true
basket.depth < max_rung_depth (4)
invalidation not triggered
recovery_forbidden == false
floating_dd_pct < basket_dd_limit
margin_usage < margin_limit
basket.age < reclaim_ttl_seconds
ATR_M5 <= vol_add_max_atr_mult * entry_ATR_M5   // default 1.5
price crossed next rung threshold
min_rung_spacing satisfied
```

### 12.2 Rung price formulas

Let `void_width = abs(E - L)`.

**Fade sell (sweep above L):**

| Rung | Threshold price |
|---|---|
| R0 | reclaim entry price |
| R1 | L + 0.25 × void_width |
| R2 | L + 0.50 × void_width (midpoint) |
| R3 | L + 0.75 × void_width |
| R4 | E - 0.05 × void_width |

**Fade buy (sweep below L):** mirror below L.

### 12.3 Minimum rung spacing

```text
min_spacing = max(0.20 * ATR_M5, spread * 8)
```

Next rung must be at least `min_spacing` from last fill price.

### 12.4 Size progression

| Rung | Multiplier | Example lots (U0=0.01) |
|---|---|---|
| R0 | 1.0 | 0.01 |
| R1 | 1.3 | 0.013 |
| R2 | 1.6 | 0.016 |
| R3 | 1.9 | 0.019 |
| R4 | 2.2 | 0.022 |

```text
leg_lots = floor_to_lot_step(U0 * multiplier[rung])
```

**Max gross exposure:** `sum(leg_lots) <= 7.0 * U0`

### 12.5 Recovery forbidden matrix

| Condition | Add allowed |
|---|---|
| Re-acceptance beyond L | NO |
| Close beyond E + buffer | NO |
| TTL expired | NO |
| daily_dd >= limit | NO |
| 2 failures today | NO |
| news window | NO |
| ATR spike | NO |
| SOFT-1 | NO |

---

## 13. Basket exit manager

### 13.1 Partial exit at midpoint

When price touches R2 (void midpoint):

- Close `partial_close_pct` of gross lots (default 40%)
- Only if after close: remaining basket DD <= 0.75 × basket_dd_limit OR basket net positive

### 13.2 Basket take-profit

Close all when:

```text
basket_pnl >= basket_tp_atr * ATR_M5 * pip_value * gross_lots
```

Default `basket_tp_atr = 0.25`

Alternative money target (whichever first):

```text
basket_pnl_money >= basket_tp_money_min
```

### 13.3 Breakeven trail (post-midpoint)

After partial at midpoint:

```text
trail_stop = vwap_price -/+ (trail_buffer_atr * ATR_M5)
trail_buffer_atr default = 0.15
```

### 13.4 Time-based exit

If:

```text
basket.age > reclaim_ttl_seconds * 0.90
AND floating_dd_pct < 0.35 * basket_dd_limit
```

Close all at market (scratch/small outcome). Prevents zombie baskets.

### 13.5 Exit priority

1. Hard invalidation → market flatten all  
2. Daily/basket DD breach → flatten  
3. Basket TP / trail hit → close  
4. Time-based scratch  
5. Partial midpoint (not full exit)  

---

## 14. Risk manager

### 14.1 Drawdown accounting

```text
floating_dd_pct = -min(0, floating_pnl) / equity
daily_dd_pct = -min(0, daily_closed_pnl + floating_pnl) / day_start_equity
```

### 14.2 Limits (defaults, prop-style $100k)

| Parameter | Default |
|---|---|
| `basket_dd_limit` | 1.25% |
| `daily_dd_limit` | 2.50% |
| `weekly_dd_limit` | 5.00% |
| `margin_limit` | 25% of free margin |
| `max_rung_depth` | 4 |

### 14.3 Pre-trade risk gate

Before R0 and each add:

```text
projected_worst_case <= basket_risk_budget
margin_after_order < margin_limit
```

If fail → do not open; if basket active → SOFT-1 path.

---

## 15. Anti-blowup controller

### 15.1 Circuit breakers

| Breaker | Trigger | Action | Cooldown |
|---|---|---|---|
| CB-1 Basket DD | floating_dd_pct >= basket_dd_limit | flatten | 4h |
| CB-2 Daily DD | daily_dd_pct >= daily_dd_limit | flatten + halt day | 24h |
| CB-3 Weekly DD | weekly_dd_pct >= weekly_dd_limit | flatten + halt week | 7d |
| CB-4 Margin | margin_usage >= margin_limit | flatten | 4h |
| CB-5 Vol chaos | ATR_M15 > p95 | no new arms | until ATR normal |
| CB-6 Double failure | 2 DEFENSIVE_SHUTDOWN same session | halt session | session end |
| CB-7 Rollover | ±30m rollover | no new entries | 30m |

### 15.2 Forced flatten pseudocode

```text
on trigger:
    disable new orders
    for each leg in basket.positions (deepest first):
        market close with max 3 retries
    if not fully closed within 10s:
        alert + set DEFENSIVE_HALT
    log emergency event
    cooldown_until = now + cooldown_seconds
```

### 15.3 Cooldown

Default `cooldown_seconds = 14400` (4h) after emergency; `1800` (30m) after normal basket exit.

---

## 16. News calendar gate

### 16.1 Tier definitions

| Tier | Events | Buffer |
|---|---|---|
| T1 | CPI, NFP, FOMC rate/decision/minutes, Core PCE | ±30 min |
| T2 | GDP, Retail Sales, ISM PMI, Fed chair speech | ±15 min |

### 16.2 Implementation

v1: external CSV loaded in `Files/` folder, or manual `NewsEvent[]` input array.

```text
NewsEvent { datetime, tier, currency, title }
```

Block if currency ∈ {USD, XAU} or title contains "Gold"/"FOMC".

---

## 17. Session manager

### 17.1 Server time sessions (default)

| Session | Hours (server) |
|---|---|
| Asia | 00:00–07:59 |
| London | 08:00–12:59 |
| NY overlap | 13:00–17:59 |
| Late NY | 18:00–20:59 |

### 17.2 Trading windows

`session_liquid` = London + NY overlap + Late NY  
Optional input: `allow_asia_trading = false` (default false for v1)

### 17.3 Rollover

Default rollover reference: 00:00 server.  
Block new arms `rollover_lock_minutes` = 30 before and after.

---

## 18. Parameter defaults (v1.0)

### 18.1 Structure

| Input | Default | Range |
|---|---|---|
| `sweep_depth_min_atr` | 0.15 | 0.10–0.25 |
| `sweep_depth_max_atr` | 0.80 | 0.60–1.00 |
| `sweep_window_bars` | 20 | 10–30 |
| `reclaim_ttl_seconds` | 5400 | 2700–7200 |
| `reclaim_body_filter` | true | bool |
| `invalidation_buffer_atr` | 0.10 | 0.05–0.20 |
| `acceptance_distance_atr` | 0.20 | 0.10–0.30 |

### 18.2 Recovery

| Input | Default | Range |
|---|---|---|
| `max_rung_depth` | 4 | 2–4 |
| `rung_mult_0..4` | 1.0,1.3,1.6,1.9,2.2 | cap 2.5 each |
| `min_rung_spacing_atr` | 0.20 | 0.15–0.35 |
| `vol_add_max_atr_mult` | 1.5 | 1.2–2.0 |
| `partial_close_pct` | 0.40 | 0.25–0.50 |
| `basket_tp_atr` | 0.25 | 0.15–0.40 |
| `trail_buffer_atr` | 0.15 | 0.10–0.25 |

### 18.3 Risk

| Input | Default | Range |
|---|---|---|
| `risk_per_basket` | 0.0125 | 0.005–0.015 |
| `basket_dd_limit` | 0.0125 | fixed |
| `daily_dd_limit` | 0.025 | fixed |
| `weekly_dd_limit` | 0.05 | fixed |
| `margin_limit` | 0.25 | 0.15–0.30 |
| `max_gross_mult` | 7.0 | 5.0–8.0 |

### 18.4 Regime

| Input | Default |
|---|---|
| `atr_percentile_lookback_days` | 60 |
| `vol_ok_p20` | 20 |
| `vol_ok_p95` | 95 |
| `runaway_displacement_mult` | 3.0 |
| `runaway_pullback_min_mult` | 0.5 |
| `spread_kill_mult` | 3.0 |

### 18.5 Non-optimizable in v1 (frozen)

These must not be curve-fit in first validation pass:

- `sweep_depth_max_atr`
- `reclaim_ttl_seconds`
- `rung_multipliers`
- `daily_dd_limit`

---

## 19. MT5 implementation notes

### 19.1 File layout (proposed)

```text
MQL5/
  Experts/RLVR/
    RLVR_EA.mq5
  Include/RLVR/
    Types.mqh
    LevelsEngine.mqh
    SweepDetector.mqh
    ReclaimDetector.mqh
    StateMachine.mqh
    EntryEngine.mqh
    RecoveryEngine.mqh
    BasketManager.mqh
    ExitManager.mqh
    RiskManager.mqh
    AntiBlowup.mqh
    SessionManager.mqh
    NewsGate.mqh
    Telemetry.mqh
    Config.mqh
```

### 19.2 Key MQL5 considerations

| Topic | Requirement |
|---|---|
| Filling mode | Detect `SYMBOL_FILLING_MODE`; fail gracefully |
| Lot step | `SymbolInfoDouble(SYMBOL_VOLUME_STEP)` |
| Stops level | Respect `SYMBOL_TRADE_STOPS_LEVEL` if SL used |
| Trade context | Serialize order sends; handle `TRADE_RETCODE_REQUOTE` |
| Tester | Use tick data or real ticks; model 2× spread stress mode |
| Multi-broker | `SYMBOL_POINT`, digits, contract size abstraction |

### 19.3 OnTick vs OnTimer

- **OnTimer(1s):** TTL, cooldown, DD checks, forced flatten
- **OnTradeTransaction:** position updates, basket VWAP refresh
- **New M5 bar hook:** sweep, reclaim, invalidation

### 19.4 Broker stop-out safety

Even with virtual SL logic, send emergency broker SL at `2 × structural invalidation` distance when gross lots > 3 × U0.

---

## 20. Telemetry and logging

### 20.1 Event log schema

```text
timestamp, event_type, level_id, basket_id, state, price, dd_pct, depth, message
```

### 20.2 Required events

`LEVEL_ARMED, SWEEP_START, SWEEP_DEEP_DISQ, RECLAIM, R0_OPEN, RN_ADD, PARTIAL_CLOSE, BASKET_TP, INV_TRIGGER, CB_TRIGGER, FLATTEN, COOLDOWN_START`

### 20.3 Per-basket summary (on close)

```text
basket_id, level_type, void_width, depth_max, duration, pnl, mae, mfe, exit_reason
```

### 20.4 CSV export

Daily export for validation pipeline: `RLVR_trades_YYYYMMDD.csv`

---

## 21. Validation hooks (built into EA)

| Hook | Purpose |
|---|---|
| `StressSpreadMult` input | Multiply live spread for forward sim |
| `StressSlippagePoints` input | Add to fill price |
| `DryRun` mode | Log signals without orders |
| `ForceRungDepth` test | QA recovery logic |
| `ReplayLevelId` | Deterministic integration test |

---

## 22. Acceptance criteria for v1 build

EA v1 is **spec-complete** when:

1. State machine matches Section 10 transition table.
2. No add occurs when any forbidden condition (Section 12.5) is true.
3. Max 5 rungs enforced; gross lots cap enforced.
4. Hard invalidation flattens within 1 timer tick + 10s.
5. Daily DD halt prevents new R0 after breach.
6. Dry-run logs 100% of signals with correct state transitions.
7. Backtest on 1 year XAUUSD passes **no structural rule violations** (assertion mode).

EA v1 is **validation-complete** when external validation plan (Phase 9) passes OOS gates.

---

## 23. Build sequence (recommended)

| Step | Deliverable |
|---:|---|
| 1 | `Types.mqh`, `Config.mqh`, `StateMachine.mqh` (dry-run) |
| 2 | `LevelsEngine.mqh` + unit tests in script |
| 3 | Sweep + Reclaim detectors (bar replay) |
| 4 | `BasketManager` + `RiskManager` |
| 5 | Entry + Recovery (live orders disabled) |
| 6 | Exit + AntiBlowup |
| 7 | Full EA + assertion mode |
| 8 | 5-year tick backtest + stress modes |
| 9 | Micro live forward test |

---

## 24. Open decisions (v1.1 backlog)

| Item | Options |
|---|---|
| M1 sweep precision | Reduce false E on wicks |
| Pending limits at rungs | Better fills vs miss rate |
| Asia session arming | Disabled in v1 |
| Multiple symbol | Not planned |
| VWAP value-area variant | FAVR merge |

---

## 25. Sign-off checklist

- [ ] Thesis restated in code comments matches Section 2
- [ ] Martingale adds impossible without `RECOVERY_ELIGIBLE`
- [ ] Frozen parameters documented in set file
- [ ] Emergency flatten tested with 3× spread
- [ ] Walk-forward script consumes CSV telemetry

---

*End of RLVR Formal Specification v1.0*
