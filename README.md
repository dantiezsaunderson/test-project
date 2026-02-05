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
- polymarketClient.js - Polymarket discovery and trading helpers
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
- `POLYMARKET_*` - Polymarket discovery and trading controls

## Polymarket integration
The bot can scan the Polymarket website, score liquidity/volume/spread, and
produce research-focused signals. Trading is **off by default** and requires
explicit opt-in.

Key variables (see `.env.example`):
- `POLYMARKET_SOURCE` - `web` (default) or `api`
- `POLYMARKET_WEB_URL` - page to scan (default Polymarket markets page)
- `POLYMARKET_WEB_MAX_MARKETS` - limit for parsed markets
- `POLYMARKET_GAMMA_HOST`, `POLYMARKET_CLOB_HOST` - API hosts
- `POLYMARKET_MIN_LIQUIDITY`, `POLYMARKET_MIN_VOLUME` - filters
- `POLYMARKET_PICK_SIDE` - YES or NO outcome token
- `POLYMARKET_PRICE_MOVE_ALERT` - momentum threshold for research signals
- `POLYMARKET_ALLOW_TRADING` - must be `true` to allow trade execution
- `POLYMARKET_DRY_RUN` - must be `false` to actually place orders

To derive L2 API credentials, use the OpenClaw skill or run:
```bash
node skills/polymarket/polymarket.js derive --write-env
```

To place a trade (explicit confirmation required):
```bash
export TOKEN_ID=your-token-id
export PRICE=0.48
export SIZE_USDC=5
POLYMARKET_ALLOW_TRADING=true POLYMARKET_DRY_RUN=false \
  node skills/polymarket/polymarket.js trade --confirm
```

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

### OpenClaw Polymarket skill
This repo also ships `skills/polymarket` to let OpenClaw query Polymarket
signals and (when explicitly allowed) place trades.

Example:
- `node /absolute/path/to/this-repo/skills/polymarket/polymarket.js signals --limit 5 --source web`
- `node /absolute/path/to/this-repo/skills/polymarket/polymarket.js balance --asset collateral`
- `node /absolute/path/to/this-repo/skills/polymarket/polymarket.js trade --confirm`

### Additional OpenClaw skills
- `skills/market-signals` - offline summary of crypto/forex/Polymarket signals
- `skills/passive-income-lab` - generate passive income opportunities and plans
- `skills/market-edge-lab` - formulate and test edge hypotheses

Example:
- `node /absolute/path/to/this-repo/skills/market-signals/market-signals.js --limit 10`

## Notes
- This bot is for research and alerting only.
- It does not place trades or provide financial advice.
- Always manage risk and keep humans in the loop.
