---
name: polymarket_assistant
description: Discover Polymarket opportunities, generate signals, and place trades on request.
metadata: { "openclaw": { "emoji": "🟣", "requires": { "bins": ["node"] } } }
---

# Polymarket Assistant

This skill connects OpenClaw to the Polymarket signals and trading CLI in this repo.
It **scans the Polymarket website by default** (no API credentials required) and
is research-only unless explicitly enabled for trading.

## Requirements

- Bot repo dependencies installed (`npm install`)
- Optional: `.env` configured with Polymarket credentials
- Default API hosts:
  - `https://gamma-api.polymarket.com`
  - `https://clob.polymarket.com`

## Commands (via exec)

- Status (best current market, website scan):
  - `node {baseDir}/polymarket.js status --source web`
- Discover top candidates:
  - `node {baseDir}/polymarket.js discover --source web`
- Recent signals:
  - `node {baseDir}/polymarket.js signals --limit 5 --source web`
- Balance/allowance:
  - `node {baseDir}/polymarket.js balance --asset collateral`
- Derive L2 API credentials (requires PRIVATE KEY env vars):
  - `node {baseDir}/polymarket.js derive --write-env`
- Place a trade (requires explicit confirmation):
  - `node {baseDir}/polymarket.js trade --confirm`

## Safety

Trading is blocked unless:
- `POLYMARKET_ALLOW_TRADING=true`
- `POLYMARKET_DRY_RUN=false`
- `--confirm` flag is provided

Always summarize the plan before any trade attempt and require user approval.
