---
name: blofin_perps
description: Scan Blofin perps with ICC-style signals and place manual orders.
metadata: { "openclaw": { "requires": { "bins": ["node"] } } }
---

# Blofin Perps Assistant

This skill scans Blofin perpetuals using the ICC (Indication → Correction →
Continuation) model and can place **manual** orders when explicitly confirmed.

## Commands (via exec)

- Scan signals (public):
  - `node {baseDir}/blofin.js scan --limit 5`
- View positions (private):
  - `node {baseDir}/blofin.js positions`
- View balances (private):
  - `node {baseDir}/blofin.js balance`
- Place an order (manual only):
  - `node {baseDir}/blofin.js order --inst BTC-USDT --side buy --type market --size 1 --confirm`

## Safety

Trading is blocked unless:
- `BLOFIN_ALLOW_TRADING=true`
- `BLOFIN_DRY_RUN=false`
- `--confirm` flag is provided

Never enable withdrawals/transfer on the API key. Always review signals first.
