---
name: market_signals
description: Summarize crypto, forex, and Polymarket signals from local bot data.
metadata: { "openclaw": { "requires": { "bins": ["node"] } } }
---

# Market Signals (offline summary)

This skill summarizes **crypto, forex, and Polymarket** signals from the local
`bot-data.json` file. It does **not** call external APIs. Use it to review the
latest signals without any network access.

## Requirements

- Bot data file exists at the repo root (`bot-data.json`)
- Node.js available

## Commands (via exec)

- Summary + recent signals:
  - `node {baseDir}/market-signals.js --limit 10`
- Filter to a market:
  - `node {baseDir}/market-signals.js --market crypto`
  - `node {baseDir}/market-signals.js --market forex`
  - `node {baseDir}/market-signals.js --market polymarket`
- Counts only:
  - `node {baseDir}/market-signals.js --summary`

## Notes

- If you want **fresh** signals, run the bot separately (which may use public
  endpoints). This skill only reads what is already stored locally.
