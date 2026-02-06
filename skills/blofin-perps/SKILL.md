---
name: blofin_perps
description: Scan Blofin perps with ICC-style signals and place manual orders.
metadata: { "openclaw": { "requires": { "bins": ["node"] } } }
---

# Blofin Perps Assistant

This skill scans Blofin perpetuals using the ICC (Indication → Correction →
Continuation) model and can place **manual** orders when explicitly confirmed.
It can also run a single auto-trade cycle when the auto-trade guards are enabled.

## Commands (via exec)

- Scan signals (public):
  - `node {baseDir}/blofin.js scan --limit 5`
- Run one auto-trade cycle (safe by default):
  - `node {baseDir}/blofin.js auto --limit 5`
- Review recent auto-trades:
  - `node {baseDir}/blofin.js report --days 7`
- Evaluate performance (TP/SL hits):
  - `node {baseDir}/blofin.js report --days 7 --perf`
- View positions (private):
  - `node {baseDir}/blofin.js positions`
- View balances (private):
  - `node {baseDir}/blofin.js balance`
- Place an order (manual only):
  - `node {baseDir}/blofin.js order --inst BTC-USDT --side buy --type market --size 1 --confirm`
- Place a bracket order with multi-TP + SL:
  - `node {baseDir}/blofin.js bracket --inst BTC-USDT --side sell --size 0.3 --auto-targets --confirm`

## Safety

Trading is blocked unless:
- `BLOFIN_ALLOW_TRADING=true`
- `BLOFIN_DRY_RUN=false`
- `--confirm` flag is provided

Auto-trading is blocked unless all of the following are true:
- `BLOFIN_AUTO_TRADE=true`
- `BLOFIN_ALLOW_TRADING=true`
- `BLOFIN_DRY_RUN=false` (use dry-run to simulate)
- `BLOFIN_KILL_SWITCH=false`

Never enable withdrawals/transfer on the API key. Always review signals first.
