# RLVR MQL5

## Single-file build (recommended)

Copy **one file** into your terminal and compile:

```text
MQL5/Experts/RLVR/RLVR_AllInOne.mq5  →  Experts/RLVR/RLVR_AllInOne.mq5
```

No `Include/RLVR/` folder required. Only dependency is the standard library `Trade/Trade.mqh`.

1. Open `RLVR_AllInOne.mq5` in MetaEditor  
2. Press **Compile** (F7)  
3. Attach to **XAUUSD M5**  

### Regenerate after editing modules

If you change files under `Include/RLVR/`:

```bash
python3 MQL5/scripts/merge_all_in_one.py
```

This rebuilds `RLVR_AllInOne.mq5` from all modules + `RLVR_EA.mq5` inputs.

---

## Modular build (developers)

For split modules, copy both:

```text
MQL5/Experts/RLVR/RLVR_EA.mq5
MQL5/Include/RLVR/*.mqh
```

Compile `RLVR_EA.mq5` (requires Include path).

---

## Modes

| `InpDryRun` | Behavior |
|---|---|
| `true` (default) | Full pipeline + CSV log, no orders |
| `false` | Live trading |

## Key inputs

| Input | Default |
|---|---|
| `InpRiskPerBasket` | 0.0125 (1.25%) |
| `InpBasketDdLimit` | 0.0125 |
| `InpDailyDdLimit` | 0.025 |
| `InpDryRun` | true |

Telemetry: `Common/Files/RLVR_events.csv`

## Docs

- [Formal spec](../docs/rlvr/RLVR-FORMAL-SPECIFICATION.md)
- [Python harness](../tools/rlvr_replay/README.md)
