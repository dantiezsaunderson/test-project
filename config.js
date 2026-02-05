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
        maxSignals: parseNumber(process.env.MAX_SIGNALS, 200)
    },
    alerts: {
        webhookUrl: process.env.WEBHOOK_URL || '',
        enableConsole: process.env.ALERT_CONSOLE !== 'false'
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
        }
    }
};

module.exports = config;
