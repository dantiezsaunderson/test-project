# RLVR CSV Replay Harness

Bar-by-bar validation of **sweep**, **reclaim**, and **invalidation** logic against historical M5 CSV — without MT5.

Implements formal spec §7–9. Reference parameters: `docs/rlvr/PARAMETER-DEFAULTS.json`.

---

## Quick start

```bash
# Run unit tests
python3 -m unittest discover -s tools/rlvr_replay/tests -v

# Replay synthetic fixture
python3 -m tools.rlvr_replay \
  tools/rlvr_replay/fixtures/upside_sweep_reclaim_m5.csv \
  --levels-csv tools/rlvr_replay/fixtures/manual_level_2400.csv \
  --no-pdh-pdl \
  --output /tmp/rlvr_events.csv
```

---

## M5 CSV format

Required columns (case-insensitive):

| Column | Example |
|---|---|
| `datetime` or `time` | `2025-06-10 08:00:00` |
| `open` | `2396.00` |
| `high` | `2396.60` |
| `low` | `2395.40` |
| `close` | `2396.00` |

Supports MT5 export style (`YYYY.MM.DD HH:MM:SS`).

---

## Manual levels CSV (optional)

```csv
level_id,type,price,created_at,expires_at,quality_score
TEST_PDH_2400,MANUAL,2400.00,2025-06-10 08:00:00,2025-06-10 20:00:00,0.90
```

If omitted, harness builds **PDH/PDL** from prior-day M5 aggregates.

---

## CLI options

| Flag | Description |
|---|---|
| `--levels-csv` | Manual liquidity levels |
| `--no-pdh-pdl` | Disable auto PDH/PDL (controlled tests) |
| `--no-body-filter` | Disable reclaim rejection-body filter |
| `--config` | Alternate `PARAMETER-DEFAULTS.json` |
| `--output` | Write event log CSV |
| `--summary-json` | Write summary counts JSON |

---

## Event types emitted

| Event | Meaning |
|---|---|
| `SWEEP_START` | Penetration ≥ d_min |
| `SWEEP_TOO_DEEP` | Penetration > d_max → expired |
| `SWEEP_TIMEOUT` | No reclaim within sweep window bars |
| `RECLAIM` | M5 close back inside level |
| `RECLAIM_TTL_EXPIRED` | No reclaim within TTL |
| `INVALIDATION` | Post-reclaim structural break |

---

## Module layout

```text
tools/rlvr_replay/
  replay_engine.py    # Orchestrator
  sweep.py            # §7 SweepDetector (reference impl)
  reclaim.py          # §8 ReclaimDetector
  invalidation.py     # §9 Invalidation
  levels.py           # PDH/PDL for replay
  atr.py              # Wilder ATR(14)
  io_csv.py           # Loaders / writers
  cli.py              # Entry point
  tests/              # Unit tests
  fixtures/           # Synthetic CSV + generator
```

---

## Exporting data from MT5

1. Strategy Tester → XAUUSD M5 → Export bars to CSV  
2. Run replay on exported file  
3. Compare event counts and timestamps with EA dry-run logs (future)

---

## Validation workflow (Phase 9)

1. **Multi-year replay** — event rate by month/session  
2. **Sensitivity** — sweep `d_min` / `d_max` / window / TTL  
3. **Stress** — verify `SWEEP_TOO_DEEP` rate on trend weeks  
4. **Parity** — MQL5 dry-run must match Python on same CSV  

---

## Parity check (Python vs MT5)

```bash
# Generate Python reference + compare to MT5 telemetry export
python3 -m tools.rlvr_replay fixtures/upside_sweep_reclaim_m5.csv \
  --levels-csv fixtures/manual_level_2400.csv \
  --no-pdh-pdl \
  --output /tmp/py_events.csv

python3 -m tools.rlvr_replay.parity_compare \
  --python-events /tmp/py_events.csv \
  --mt5-events /path/to/terminal/Common/Files/RLVR_events.csv
```

## Deep-dive docs

- LevelsEngine: `docs/rlvr/modules/LEVELS-ENGINE-PSEUDOCODE.md`
- SweepDetector: `docs/rlvr/modules/SWEEP-DETECTOR-PSEUDOCODE.md`
- Full system spec: `docs/rlvr/RLVR-FORMAL-SPECIFICATION.md`
- MQL5 scaffold: `MQL5/README.md`
