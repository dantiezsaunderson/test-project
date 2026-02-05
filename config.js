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
        }
    }
};

module.exports = config;
