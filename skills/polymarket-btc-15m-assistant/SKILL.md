---
name: polymarket_btc_15m_assistant
description: Run the Polymarket BTC 15m assistant (real-time console) from FrondEnt.
metadata: { "openclaw": { "requires": { "bins": ["node", "git", "npm"] } } }
---

# Polymarket BTC 15m Assistant

This skill installs and runs the open-source Polymarket BTC 15m console assistant:
https://github.com/FrondEnt/PolymarketBTC15mAssistant/

It is a real-time console monitor (long-running). Use it in a dedicated terminal.

## Commands (via exec)

- Check install status:
  - `node {baseDir}/btc15m.js status`
- Install/update the assistant (clones repo + npm install):
  - `node {baseDir}/btc15m.js install`
- Start the live console (long-running):
  - `node {baseDir}/btc15m.js start`
- Capture a short snapshot (non-blocking):
  - `node {baseDir}/btc15m.js snapshot --seconds 8`

## Optional environment variables

You can set these before running:

- `BTC15M_PRICE_SOURCE` (`blofin` default or `binance`)
- `BLOFIN_BASE_URL` (default `https://openapi.blofin.com`)
- `BLOFIN_INST_ID` (default `BTC-USDT`)
- `POLYGON_RPC_URL` / `POLYGON_RPC_URLS`
- `POLYGON_WSS_URLS`
- `POLYMARKET_AUTO_SELECT_LATEST` (default true)
- `POLYMARKET_SLUG` (pin a specific market)

## Notes

- This is not financial advice. Use at your own risk.
- The assistant is a live console app; stop with Ctrl+C.
