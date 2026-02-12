const config = require('./config');
const dataStore = require('./dataStore');
const fetchers = require('./fetchers');
const { generateSignals } = require('./signalEngine');
const { notify } = require('./notifier');
const { runBlofinAutoTrade, runAutoTradeWithSettings } = require('./autoTrader');
const fabiaScanner = require('./fabiaScanner');

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
    const autoTrades = [];

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
                if (market === 'blofin') {
                    try {
                        const autoSummary = await runBlofinAutoTrade({
                            snapshot,
                            reason
                        });
                        if (autoSummary?.actions?.length) {
                            autoTrades.push(...autoSummary.actions);
                        }
                        if (config.markets.blofin.fabiaDryTest) {
                            const fabiaScan = await fabiaScanner.fetchSignals();
                            const fabiaSummary = await runAutoTradeWithSettings({
                                signals: fabiaScan.signals,
                                reason: 'fabia-dry',
                                overrides: {
                                    autoTrade: true,
                                    allowTrading: true,
                                    dryRun: true,
                                    autoTradeKillSwitch: false,
                                    autoPauseAfterTrade: false,
                                    autoPauseAfterLoss: false,
                                    autoBrackets: false,
                                    autoTradeSessions: [],
                                    autoDryMaxActions:
                                        config.markets.blofin.fabiaDryMaxActions,
                                    maxOpenPositionsDry: 0
                                },
                                strategyLabel: 'fabia'
                            });
                            if (fabiaSummary?.actions?.length) {
                                autoTrades.push(...fabiaSummary.actions);
                            }
                        }
                    } catch (autoError) {
                        errors.push({
                            market: 'blofin-auto',
                            message: autoError.message || 'Auto trade error'
                        });
                    }
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
            autoTradeCount: autoTrades.length,
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
