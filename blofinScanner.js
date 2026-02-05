const blofinClient = require('./blofinClient');
const config = require('./config');
const { buildIccSignal } = require('./blofinStrategy');

const parseNumber = (value) => {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
};

const buildTickerMap = (tickers) => {
    const map = new Map();
    tickers.forEach((ticker) => {
        if (ticker && ticker.instId) {
            map.set(ticker.instId, ticker);
        }
    });
    return map;
};

const selectInstruments = (instruments, tickers, settings) => {
    const watchlist =
        Array.isArray(settings.instruments) && settings.instruments.length
            ? settings.instruments
            : null;

    const instrumentIds = instruments
        .filter((instrument) => instrument.instType === settings.instType)
        .map((instrument) => instrument.instId);

    let candidates = watchlist
        ? instrumentIds.filter((id) => watchlist.includes(id))
        : instrumentIds;

    if (settings.scanTop && tickers.length) {
        const tickerMap = buildTickerMap(tickers);
        candidates = candidates
            .map((id) => {
                const ticker = tickerMap.get(id);
                return {
                    instId: id,
                    volume24h: parseNumber(ticker ? ticker.volCurrency24h : 0)
                };
            })
            .filter((item) => item.volume24h >= settings.minVolume24h)
            .sort((a, b) => b.volume24h - a.volume24h)
            .slice(0, settings.scanTop)
            .map((item) => item.instId);
    }

    return candidates;
};

const fetchSignals = async () => {
    const settings = config.markets.blofin;
    const [instruments, tickers] = await Promise.all([
        blofinClient.fetchInstruments(settings.instType),
        blofinClient.fetchTickers()
    ]);

    const selected = selectInstruments(instruments, tickers, settings);
    const tickerMap = buildTickerMap(tickers);
    const signals = [];
    const errors = [];

    for (const instId of selected) {
        try {
            const candles = await blofinClient.fetchCandles({
                instId,
                bar: settings.timeframe,
                limit: settings.candleLimit
            });
            const signal = buildIccSignal(candles, settings.strategy);
            if (!signal) {
                continue;
            }
            const ticker = tickerMap.get(instId);
            signals.push({
                instId,
                last: parseNumber(ticker ? ticker.last : null),
                volume24h: parseNumber(ticker ? ticker.volCurrency24h : null),
                signal
            });
        } catch (error) {
            errors.push({ instId, message: error.message });
        }
    }

    return {
        generatedAt: new Date().toISOString(),
        instType: settings.instType,
        timeframe: settings.timeframe,
        total: selected.length,
        signals,
        errors
    };
};

module.exports = {
    fetchSignals
};
