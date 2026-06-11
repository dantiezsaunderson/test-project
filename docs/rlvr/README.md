# RLVR — Reclaimed Liquidity Void Reset

Implementation-ready design package for the XAUUSD bounded-martingale system.

## Documents

| File | Purpose |
|---|---|
| [RLVR-FORMAL-SPECIFICATION.md](./RLVR-FORMAL-SPECIFICATION.md) | Full build spec: modules, data model, detectors, state machine, risk |
| [STATE-MACHINE.md](./STATE-MACHINE.md) | Quick-reference diagrams and decision precedence |
| [PARAMETER-DEFAULTS.json](./PARAMETER-DEFAULTS.json) | Machine-readable default inputs and frozen parameters |

## Build order

1. Read formal specification Sections 2–10 (thesis + state machine)
2. Implement dry-run with `Types.mqh`, `StateMachine.mqh`, `LevelsEngine.mqh`
3. Add sweep/reclaim detectors on M5 bar replay
4. Wire basket, recovery, exit, anti-blowup per Sections 11–15
5. Run validation plan from concept Phase 9 before live sizing

## Next step

MQL5 scaffold under `MQL5/Experts/RLVR/` per specification Section 19.1.
