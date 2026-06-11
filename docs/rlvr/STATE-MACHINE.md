# RLVR State Machine Reference

Quick-reference companion to `RLVR-FORMAL-SPECIFICATION.md`.

## Global EA flow

```mermaid
stateDiagram-v2
    direction LR
    OFF --> IDLE: init ok
    IDLE --> BASKET_ACTIVE: R0 opened
    BASKET_ACTIVE --> COOLDOWN: normal exit
    BASKET_ACTIVE --> DEFENSIVE_HALT: circuit breaker
    COOLDOWN --> IDLE: timer done
    DEFENSIVE_HALT --> IDLE: manual reset / next day
```

## Per-level lifecycle

```mermaid
stateDiagram-v2
    direction TB
    IDLE --> ARMED: quality >= 0.55 + regime OK
    ARMED --> SWEEP_DETECTED: penetration >= d_min
    SWEEP_DETECTED --> EXPIRED: too deep / timeout
    SWEEP_DETECTED --> RECLAIM_CONFIRMED: M5 reclaim
    RECLAIM_CONFIRMED --> CONSUMED: basket opened
    CONSUMED --> EXPIRED: basket closed
```

## Basket sub-state flow

```mermaid
stateDiagram-v2
    direction TB
    INITIAL_ENTRY --> CONTROLLED_ADVERSE: price against
    INITIAL_ENTRY --> PROFIT_COMPRESSION: price favorable
    CONTROLLED_ADVERSE --> RECOVERY_ELIGIBLE: rung + valid reclaim
    RECOVERY_ELIGIBLE --> RESCUE_ACTIVE: add filled
    RESCUE_ACTIVE --> CONTROLLED_ADVERSE: max depth / no add
    RESCUE_ACTIVE --> PROFIT_COMPRESSION: partial / improve
    CONTROLLED_ADVERSE --> DEFENSIVE_SHUTDOWN: invalidation
    PROFIT_COMPRESSION --> BASKET_EXIT: TP / trail
    DEFENSIVE_SHUTDOWN --> BASKET_EXIT: flattened
```

## Decision precedence (highest first)

| Priority | Check | Result |
|---:|---|---|
| 1 | Hard invalidation INV-1..6 | Flatten immediately |
| 2 | CB-2 Daily DD | Flatten + halt day |
| 3 | CB-1 Basket DD | Flatten + cooldown |
| 4 | CB-4 Margin | Flatten |
| 5 | SOFT-1 | No adds; manage exit |
| 6 | Recovery eligible | Allow R1–R4 |
| 7 | Profit rules | Partial / TP / trail |

## Forbidden add conditions (must be false to add)

```text
reacceptance_beyond_L
close_beyond_sweep_extreme_plus_buffer
reclaim_ttl_expired
daily_dd_breached
two_failures_this_session
news_window_active
atr_spike_kill
soft_invalidation_active
margin_over_limit
projected_risk_over_budget
```

## Timer responsibilities (1s)

| Check | Frequency |
|---|---|
| TTL expiry | every tick |
| Cooldown elapsed | every tick |
| DD / margin | every tick |
| Forced flatten retries | every tick when active |
| Level expiry | every tick |
| New M5 bar events | on bar change only |
