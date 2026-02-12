---
name: fabia_scalping_model
description: Fabia Valentina scalping model (AMT/Market Profile proxy).
metadata: { "openclaw": { "requires": { "bins": ["node"] } } }
---

# Fabia Valentina Scalping Model

This skill implements a **proxy** version of Fabia's AMT + Order Flow model.
Because full order-flow + market profile data isn't available, this uses
OHLCV candles to approximate a volume profile (POC/VAH/VAL/HVN/LVN) and
derives balanced vs imbalanced state.

## Commands (via exec)

- Signal snapshot:
  - `node {baseDir}/fabia.js signal --inst BTC-USDT --tf 5m --limit 240`
- Profile snapshot only:
  - `node {baseDir}/fabia.js profile --inst BTC-USDT --tf 5m --limit 240`

## Notes
- Trend model is preferred in **New York** session.
- Mean reversion model is preferred in **London** session.
- Any signal still requires **order-flow confirmation** before execution.
