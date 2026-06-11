# RLVR MQL5 Dry-Run Scaffold

MetaTrader 5 implementation of RLVR structure detection (no orders in v1).

## Layout

```text
MQL5/
  Experts/RLVR/RLVR_EA.mq5
  Include/RLVR/
    Types.mqh
    Config.mqh
    AtrUtils.mqh
    Telemetry.mqh
    LevelsEngine.mqh
    SweepDetector.mqh
    ReclaimDetector.mqh
    Invalidation.mqh
    StateMachine.mqh
```

## Install

1. Copy `MQL5/Experts/RLVR/` → terminal `MQL5/Experts/RLVR/`
2. Copy `MQL5/Include/RLVR/` → terminal `MQL5/Include/RLVR/`
3. Compile `RLVR_EA.mq5` in MetaEditor

## Dry-run usage

1. Attach `RLVR_EA` to **XAUUSD M5** chart
2. Ensure `InpDryRun = true` (default)
3. Events write to `Common/Files/RLVR_events.csv`

### Parity test (match Python harness)

Strategy Tester settings:

| Input | Value |
|---|---|
| `InpDryRun` | true |
| `InpAutoPdhPdl` | false |
| `InpAutoSessionLevels` | false |
| `InpAutoRoundLevels` | false |
| `InpManualLevelEnable` | true |
| `InpManualLevelPrice` | 2400.0 |
| `InpManualLevelId` | TEST_PDH_2400 |

Run tester on same period as `tools/rlvr_replay/fixtures/upside_sweep_reclaim_m5.csv`, then:

```bash
python3 -m tools.rlvr_replay.parity_compare \
  tools/rlvr_replay/fixtures/upside_sweep_reclaim_m5.csv \
  --python-events /tmp/py_events.csv \
  --mt5-events /path/to/RLVR_events.csv
```

## Parity rules

Python `sweep.py` / `reclaim.py` / `invalidation.py` are the reference. MQL5 must match on:

- `event_type`
- `level_id`
- `direction` (when present)

`bar_index` may differ (internal counter); timestamps should align within one M5 bar.

## Module docs

- [LevelsEngine pseudocode](../docs/rlvr/modules/LEVELS-ENGINE-PSEUDOCODE.md)
- [SweepDetector pseudocode](../docs/rlvr/modules/SWEEP-DETECTOR-PSEUDOCODE.md)
- [Formal specification](../docs/rlvr/RLVR-FORMAL-SPECIFICATION.md)

## v1 scope

- Dry-run only (no `OrderSend`)
- Levels: PDH/PDL, session H/L, round, manual
- EQH/EQL: not in v1 (see LevelsEngine doc)
- Recovery / basket: not in v1
