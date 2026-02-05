const path = require('path');

const parseNumber = (value, fallback) => {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
};

const parseList = (value, fallback) => {
    if (!value) {
        return fallback;
    }
    return value
        .split(',')
        .map((item) => item.trim())
        .filter(Boolean);
};

const parseNumberList = (value, fallback) => {
    if (!value) {
        return fallback;
    }
    const list = value
        .split(',')
        .map((item) => Number(item.trim()))
        .filter((item) => Number.isFinite(item));
    return list.length ? list : fallback;
};

const config = {
    server: {
        port: parseNumber(process.env.PORT, 3000),
        apiKey: process.env.BOT_API_KEY || ''
    },
    scheduler: {
        intervalMinutes: parseNumber(process.env.INTERVAL_MINUTES, 15),
        disabled: process.env.DISABLE_SCHEDULER === 'true'
    },
    storage: {
        filePath: path.resolve(__dirname, process.env.DATA_FILE || 'bot-data.json'),
        maxSnapshots: parseNumber(process.env.MAX_SNAPSHOTS, 50),
        maxSignals: parseNumber(process.env.MAX_SIGNALS, 200),
        maxAutoTrades: parseNumber(process.env.MAX_AUTO_TRADES, 200)
    },
    alerts: {
        webhookUrl: process.env.WEBHOOK_URL || '',
        enableConsole: process.env.ALERT_CONSOLE !== 'false',
        email: {
            enabled: process.env.EMAIL_ALERT_ENABLED === 'true',
            smtpHost: process.env.EMAIL_SMTP_HOST || '',
            smtpPort: parseNumber(process.env.EMAIL_SMTP_PORT, 587),
            smtpSecure: process.env.EMAIL_SMTP_SECURE === 'true',
            smtpUser: process.env.EMAIL_SMTP_USER || '',
            smtpPass: process.env.EMAIL_SMTP_PASS || '',
            from: process.env.EMAIL_ALERT_FROM || '',
            to: parseList(process.env.EMAIL_ALERT_TO, []),
            includeDryRun: process.env.EMAIL_ALERT_INCLUDE_DRY_RUN === 'true'
        }
    },
    apiKeys: {
        pokemonTcg: process.env.POKEMON_TCG_API_KEY || ''
    },
    markets: {
        crypto: {
            enabled: process.env.CRYPTO_ENABLED !== 'false',
            ids: parseList(process.env.CRYPTO_IDS, [
                'bitcoin',
                'ethereum',
                'solana',
                'dogecoin',
                'pepe'
            ]),
            vsCurrency: process.env.CRYPTO_VS_CURRENCY || 'usd',
            percentMoveAlert: parseNumber(process.env.CRYPTO_MOVE_ALERT, 2)
        },
        meme: {
            enabled: process.env.MEME_ENABLED !== 'false',
            ids: parseList(process.env.MEME_IDS, [
                'dogecoin',
                'shiba-inu',
                'pepe',
                'bonk'
            ]),
            vsCurrency: process.env.MEME_VS_CURRENCY || 'usd',
            percentMoveAlert: parseNumber(process.env.MEME_MOVE_ALERT, 6)
        },
        forex: {
            enabled: process.env.FOREX_ENABLED !== 'false',
            base: process.env.FOREX_BASE || 'USD',
            symbols: parseList(process.env.FOREX_SYMBOLS, [
                'EUR',
                'GBP',
                'JPY',
                'CHF',
                'AUD',
                'CAD'
            ]),
            percentMoveAlert: parseNumber(process.env.FOREX_MOVE_ALERT, 0.4)
        },
        collectibles: {
            enabled: process.env.COLLECTIBLES_ENABLED !== 'false',
            setsPageSize: parseNumber(process.env.POKEMON_PAGE_SIZE, 6)
        },
        polymarket: {
            enabled: process.env.POLYMARKET_ENABLED !== 'false',
            source: (process.env.POLYMARKET_SOURCE || 'web').toLowerCase(),
            webUrl: process.env.POLYMARKET_WEB_URL || 'https://polymarket.com/markets',
            webMaxMarkets: parseNumber(process.env.POLYMARKET_WEB_MAX_MARKETS, 200),
            gammaHost: process.env.POLYMARKET_GAMMA_HOST || 'https://gamma-api.polymarket.com',
            clobHost: process.env.POLYMARKET_CLOB_HOST || 'https://clob.polymarket.com',
            chainId: parseNumber(process.env.POLYMARKET_CHAIN_ID, 137),
            minLiquidity: parseNumber(process.env.POLYMARKET_MIN_LIQUIDITY, 20000),
            minVolume: parseNumber(process.env.POLYMARKET_MIN_VOLUME, 20000),
            candidates: parseNumber(process.env.POLYMARKET_CANDIDATES, 80),
            spreadCheckTop: parseNumber(process.env.POLYMARKET_SPREAD_CHECK_TOP, 20),
            pickSide: (process.env.POLYMARKET_PICK_SIDE || 'YES').toUpperCase(),
            signalTop: parseNumber(process.env.POLYMARKET_SIGNAL_TOP, 5),
            spreadAlert: parseNumber(process.env.POLYMARKET_SPREAD_ALERT, 0.02),
            priceMoveAlert: parseNumber(process.env.POLYMARKET_PRICE_MOVE_ALERT, 0.05),
            allowTrading: process.env.POLYMARKET_ALLOW_TRADING === 'true',
            dryRun: process.env.POLYMARKET_DRY_RUN !== 'false',
            maxOrderUsdc: parseNumber(process.env.POLYMARKET_MAX_ORDER_USDC, 10)
        },
        blofin: {
            enabled: process.env.BLOFIN_ENABLED !== 'false',
            useDemo: process.env.BLOFIN_USE_DEMO === 'true',
            baseUrl: process.env.BLOFIN_API_BASE || 'https://openapi.blofin.com',
            demoBaseUrl:
                process.env.BLOFIN_DEMO_BASE ||
                'https://demo-trading-openapi.blofin.com',
            wsPublic:
                process.env.BLOFIN_WS_PUBLIC ||
                'wss://openapi.blofin.com/ws/public',
            wsPrivate:
                process.env.BLOFIN_WS_PRIVATE ||
                'wss://openapi.blofin.com/ws/private',
            apiKey: process.env.BLOFIN_API_KEY || '',
            apiSecret: process.env.BLOFIN_API_SECRET || '',
            apiPassphrase: process.env.BLOFIN_API_PASSPHRASE || '',
            instType: process.env.BLOFIN_INST_TYPE || 'SWAP',
            instruments: parseList(process.env.BLOFIN_INSTRUMENTS, [
                'BTC-USDT',
                'ETH-USDT'
            ]),
            highTimeframe: process.env.BLOFIN_HIGH_TIMEFRAME || '1H',
            entryTimeframe: process.env.BLOFIN_ENTRY_TIMEFRAME || '5m',
            highCandleLimit: parseNumber(process.env.BLOFIN_HIGH_CANDLE_LIMIT, 200),
            entryCandleLimit: parseNumber(process.env.BLOFIN_ENTRY_CANDLE_LIMIT, 200),
            performanceCandleLimit: parseNumber(
                process.env.BLOFIN_PERF_CANDLE_LIMIT,
                2000
            ),
            scanTop: parseNumber(process.env.BLOFIN_SCAN_TOP, 5),
            minVolume24h: parseNumber(process.env.BLOFIN_MIN_VOL_24H, 0),
            allowTrading: process.env.BLOFIN_ALLOW_TRADING === 'true',
            dryRun: process.env.BLOFIN_DRY_RUN !== 'false',
            maxOrderUsdt: parseNumber(process.env.BLOFIN_MAX_ORDER_USDT, 10),
            leverage: parseNumber(process.env.BLOFIN_LEVERAGE, 5),
            marginMode: process.env.BLOFIN_MARGIN_MODE || 'cross',
            positionMode:
                process.env.BLOFIN_POSITION_MODE || 'net_mode',
            autoTrade: process.env.BLOFIN_AUTO_TRADE === 'true',
            autoTradeKillSwitch: process.env.BLOFIN_KILL_SWITCH === 'true',
            autoTradeCooldownMinutes: parseNumber(
                process.env.BLOFIN_AUTO_COOLDOWN_MINUTES,
                60
            ),
            autoTradeSessions: parseList(
                process.env.BLOFIN_AUTO_SESSION_WINDOWS,
                []
            ),
            riskPerTradeUsdt: parseNumber(process.env.BLOFIN_RISK_USDT, 2),
            riskPerTradePct: parseNumber(process.env.BLOFIN_RISK_PCT, 0),
            maxOpenPositions: parseNumber(
                process.env.BLOFIN_MAX_OPEN_POSITIONS,
                1
            ),
            maxOpenPositionsDry: parseNumber(
                process.env.BLOFIN_MAX_OPEN_POSITIONS_DRY,
                10
            ),
            autoDryMaxActions: parseNumber(
                process.env.BLOFIN_AUTO_DRY_MAX_ACTIONS,
                0
            ),
            autoOrderType: (process.env.BLOFIN_AUTO_ORDER_TYPE || 'market').toLowerCase(),
            strategy: {
                minCandles: parseNumber(process.env.BLOFIN_ICC_MIN_CANDLES, 120),
                entryMinCandles: parseNumber(
                    process.env.BLOFIN_ICC_ENTRY_MIN_CANDLES,
                    120
                ),
                swingLookback: parseNumber(
                    process.env.BLOFIN_ICC_SWING_LOOKBACK,
                    160
                ),
                entryLookback: parseNumber(
                    process.env.BLOFIN_ICC_ENTRY_LOOKBACK,
                    80
                ),
                swingPivot: parseNumber(
                    process.env.BLOFIN_ICC_SWING_PIVOT,
                    2
                ),
                entryPivot: parseNumber(
                    process.env.BLOFIN_ICC_ENTRY_PIVOT,
                    2
                ),
                correctionThreshold: parseNumber(
                    process.env.BLOFIN_ICC_CORR_THRESHOLD,
                    0.382
                ),
                minDisplacementPct: parseNumber(
                    process.env.BLOFIN_ICC_MIN_DISPLACEMENT_PCT,
                    0
                ),
                liquidityTolerancePct: parseNumber(
                    process.env.BLOFIN_ICC_LIQUIDITY_TOL_PCT,
                    0
                ),
                liquidityMinTouches: parseNumber(
                    process.env.BLOFIN_ICC_LIQUIDITY_MIN_TOUCHES,
                    2
                ),
                requireLiquidityZone:
                    process.env.BLOFIN_ICC_REQUIRE_LIQUIDITY_ZONE === 'true',
                requireLiquiditySweep:
                    process.env.BLOFIN_ICC_REQUIRE_SWEEP === 'true',
                sweepLookback: parseNumber(
                    process.env.BLOFIN_ICC_SWEEP_LOOKBACK,
                    40
                ),
                sweepMinPct: parseNumber(
                    process.env.BLOFIN_ICC_SWEEP_MIN_PCT,
                    0
                ),
                targetR1: parseNumber(process.env.BLOFIN_ICC_TARGET_R1, 1),
                targetR2: parseNumber(process.env.BLOFIN_ICC_TARGET_R2, 2),
                targetR3: parseNumber(process.env.BLOFIN_ICC_TARGET_R3, 3),
                takeProfitSplits: parseNumberList(
                    process.env.BLOFIN_ICC_TP_SPLITS,
                    [0.4, 0.3, 0.3]
                )
            }
        }
    }
};

module.exports = config;
