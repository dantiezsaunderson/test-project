---
name: clawd_bot
description: Query the local Clawd trading bot API and summarize signals.
metadata: { "openclaw": { "emoji": "📈", "requires": { "bins": ["node"] } } }
---

# Clawd Bot (local trading assistant)

This skill connects OpenClaw to the local Clawd trading bot API in this repo.
Use it to fetch status, snapshots, and signals. The bot is **research-only** —
do not place trades.

## Requirements

- The bot server is running locally: `npm start`
- Default URL: `http://localhost:3000`
- Optional env vars for the CLI:
  - `CLAWD_BOT_URL` (override the base URL)
  - `CLAWD_BOT_API_KEY` or `BOT_API_KEY` (if POST /api/run is protected)

## How to use

Use the `exec` tool to run the helper CLI script:

- Status:
  - `node {baseDir}/clawd-bot.js status`
- Recent signals:
  - `node {baseDir}/clawd-bot.js signals --limit 10`
- Latest snapshot:
  - `node {baseDir}/clawd-bot.js snapshot crypto`
- Trigger a manual run:
  - `node {baseDir}/clawd-bot.js run`

When reporting back, provide a short, actionable summary (market, signal, timestamp).
