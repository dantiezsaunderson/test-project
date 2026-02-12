---
name: icc_backtest
description: Backtest ICC strategy on recent candles.
metadata: { "openclaw": { "requires": { "bins": ["node"] } } }
---

# ICC Backtest

Runs an ICC backtest over the most recent candles from Blofin.

## Commands (via exec)

- Backtest BTC/USDT:
  - `node {baseDir}/backtest.js --inst BTC-USDT --entry 5m --high 1H --entry-limit 1000 --high-limit 500`
- Batch backtest top volume:
  - `node {baseDir}/batch.js --top 20 --entry 5m --high 1H --entry-limit 1000 --high-limit 500`
- Batch backtest explicit symbols:
  - `node {baseDir}/batch.js --symbols BTC-USDT,ETH-USDT,SOL-USDT --entry 5m --high 1H --entry-limit 1000 --high-limit 500`
- Optimize BTC parameters:
  - `node {baseDir}/optimize.js --inst BTC-USDT --entry 5m --high 1H --entry-limit 6500 --high-limit 800`

## Notes
- Uses recent candles only (Blofin API does not expose arbitrary ranges here).
- Multi‑TP logic mirrors the ICC signal takeProfitLevels/splits.
