const config = require('./config');
const dataStore = require('./dataStore');
const fetchers = require('./fetchers');
const { generateSignals } = require('./signalEngine');
const { notify } = require('./notifier');

const marketFetchers = {
    crypto: fetchers.fetchCrypto,
    forex: fetchers.fetchForex,
    collectibles: fetchers.fetchCollectibles,
    meme: fetchers.fetchMeme,
    polymarket: fetchers.fetchPolymarket,
    blofin: fetchers.fetchBlofinPerps
};

let isRunning = false;

const runBot = async ({ reason } = {}) => {
    if (isRunning) {
        return { status: 'busy' };
    }

    isRunning = true;
    const startedAt = Date.now();
    const errors = [];
    const signals = [];
    const marketsRun = [];

    try {
        for (const [market, fetcher] of Object.entries(marketFetchers)) {
            if (!config.markets[market] || !config.markets[market].enabled) {
                continue;
            }
            try {
                const previousSnapshot = await dataStore.getLatestSnapshot(market);
                const data = await fetcher();
                const snapshot = {
                    timestamp: new Date().toISOString(),
                    market,
                    data
                };
                await dataStore.addSnapshot(market, snapshot);
                const marketSignals = generateSignals(
                    market,
                    snapshot,
                    previousSnapshot
                );
                if (marketSignals.length) {
                    signals.push(...marketSignals);
                }
                marketsRun.push(market);
            } catch (error) {
                errors.push({
                    market,
                    message: error.message || 'Unknown error'
                });
            }
        }

        if (signals.length) {
            await dataStore.addSignals(signals);
            await notify(signals);
        }

        const durationMs = Date.now() - startedAt;
        const summary = {
            at: new Date().toISOString(),
            durationMs,
            reason: reason || 'scheduled',
            signalCount: signals.length,
            marketsRun,
            errors
        };
        await dataStore.setLastRun(summary);

        return {
            status: errors.length ? 'partial' : 'ok',
            summary
        };
    } finally {
        isRunning = false;
    }
};

module.exports = {
    runBot
};
