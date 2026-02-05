# Clawd Bot Trading Assistant

This project is a lightweight landing page that outlines how to set up a personal
Clawd bot trading assistant powered by [openclaw.ai](https://openclaw.ai).
It highlights multi-market edge discovery across crypto, forex, collectibles,
and meme coins while emphasizing risk guardrails.

It also includes a quick-start guide on how to use the bot in practice, from
defining a thesis and connecting data to paper testing and go-live guardrails.

The landing page now lists example public API sources and directories that can
be used for market data, macro data, collectibles, and sentiment.

## Project Structure
- index.html - Main HTML layout and content
- styles.css - Styling for the landing page
- script.js - Interactive market playbook, copy-to-clipboard, live status
- server.js - Express API for live bot status and alerts
- bot.js - Bot runner that fetches data and generates signals
- dataStore.js - Local JSON storage for snapshots and signals
- fetchers.js - Public API data connectors
- signalEngine.js - Rule-based signal generator
- notifier.js - Console and webhook alert delivery
- config.js - Environment-driven settings

## Setup
1. Install dependencies:
   ```bash
   npm install
   ```
2. Copy the sample environment file:
   ```bash
   cp .env.example .env
   ```
3. Start the bot server:
   ```bash
   npm start
   ```

The landing page will be available at `http://localhost:3000` and will show
live bot status once the server is running.

## Run once (manual refresh)
```bash
npm run run:once
```

## API Endpoints
- `GET /api/status` - current bot status and last run summary
- `GET /api/signals?limit=5` - most recent signals
- `GET /api/snapshots/:market` - latest snapshot for a market
- `POST /api/run` - manual run (optional API key)

## Configuration
Update `.env` to tailor watchlists, thresholds, and alerts.

Key options:
- `INTERVAL_MINUTES` - how often the bot runs
- `WEBHOOK_URL` - send alerts to Slack, Discord, or custom webhooks
- `CRYPTO_IDS`, `MEME_IDS`, `FOREX_SYMBOLS` - watchlist configuration
- `POKEMON_TCG_API_KEY` - increase Pokemon TCG API rate limits

## OpenClaw integration (real Clawd bot)
This repo ships an OpenClaw skill that connects to the local bot API.

1. Install OpenClaw (CLI):
   ```bash
   npm install -g openclaw@latest
   openclaw onboard --install-daemon
   ```
2. Ensure the bot API is running:
   ```bash
   npm start
   ```
3. Make the skill available to OpenClaw (choose one):
   - Use this repo as your OpenClaw workspace, or
   - Add the skills directory to `skills.load.extraDirs` in `~/.openclaw/openclaw.json`:
     ```json5
     {
       skills: {
         load: {
           extraDirs: ["/absolute/path/to/this-repo/skills"],
         },
       },
     }
     ```
4. Ask OpenClaw to refresh skills or restart the gateway.

Example commands OpenClaw can run (via exec tool):
- `node /absolute/path/to/this-repo/skills/clawd-bot/clawd-bot.js status`
- `node /absolute/path/to/this-repo/skills/clawd-bot/clawd-bot.js signals --limit 10`
- `node /absolute/path/to/this-repo/skills/clawd-bot/clawd-bot.js run`

If you set `BOT_API_KEY` on the bot server, also export `CLAWD_BOT_API_KEY`
for OpenClaw before invoking the skill.

## Notes
- This bot is for research and alerting only.
- It does not place trades or provide financial advice.
- Always manage risk and keep humans in the loop.
