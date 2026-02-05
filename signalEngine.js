const config = require('./config');

const percentChange = (current, previous) => {
    if (!Number.isFinite(current) || !Number.isFinite(previous) || previous === 0) {
        return null;
    }
    return ((current - previous) / previous) * 100;
};

const createSignal = (market, type, message, data) => ({
    id: `${market}-${Date.now()}-${Math.random().toString(16).slice(2, 8)}`,
    timestamp: new Date().toISOString(),
    market,
    type,
    message,
    data
});

const generatePriceSignals = (market, current, previous, threshold) => {
    if (!previous || !current || !current.prices) {
        return [];
    }

    return Object.entries(current.prices).reduce((signals, [asset, info]) => {
        const previousInfo = previous.prices ? previous.prices[asset] : null;
        if (!previousInfo || !Number.isFinite(previousInfo.price)) {
            return signals;
        }

        const pct = percentChange(info.price, previousInfo.price);
        if (pct !== null && Math.abs(pct) >= threshold) {
            signals.push(
                createSignal(
                    market,
                    'price-move',
                    `${asset} moved ${pct.toFixed(2)}% since last snapshot.`,
                    {
                        asset,
                        percentChange: pct,
                        price: info.price,
                        previousPrice: previousInfo.price
                    }
                )
            );
        }

        if (
            Number.isFinite(info.change24h) &&
            Math.abs(info.change24h) >= threshold * 2
        ) {
            signals.push(
                createSignal(
                    market,
                    'daily-volatility',
                    `${asset} is ${info.change24h.toFixed(2)}% over 24h.`,
                    {
                        asset,
                        change24h: info.change24h,
                        price: info.price
                    }
                )
            );
        }

        return signals;
    }, []);
};

const generateForexSignals = (current, previous, threshold) => {
    if (!previous || !current || !current.rates) {
        return [];
    }

    return Object.entries(current.rates).reduce((signals, [symbol, rate]) => {
        const previousRate =
            previous.rates && Number.isFinite(previous.rates[symbol])
                ? previous.rates[symbol]
                : null;
        const pct = percentChange(rate, previousRate);
        if (pct !== null && Math.abs(pct) >= threshold) {
            signals.push(
                createSignal(
                    'forex',
                    'rate-move',
                    `${symbol}/${current.base} moved ${pct.toFixed(2)}% since last snapshot.`,
                    {
                        symbol,
                        rate,
                        previousRate,
                        percentChange: pct
                    }
                )
            );
        }
        return signals;
    }, []);
};

const generateCollectibleSignals = (current, previous) => {
    if (!current || !Array.isArray(current.sets)) {
        return [];
    }

    const previousIds = new Set(
        Array.isArray(previous && previous.sets)
            ? previous.sets.map((set) => set.id)
            : []
    );

    const newSets = current.sets.filter((set) => !previousIds.has(set.id));
    if (!newSets.length) {
        return [];
    }

    return newSets.map((set) =>
        createSignal(
            'collectibles',
            'new-set',
            `New Pokemon set detected: ${set.name} (${set.releaseDate || 'TBD'}).`,
            {
                setId: set.id,
                name: set.name,
                releaseDate: set.releaseDate
            }
        )
    );
};

const generateSignals = (market, currentSnapshot, previousSnapshot) => {
    const currentData = currentSnapshot ? currentSnapshot.data : null;
    const previousData = previousSnapshot ? previousSnapshot.data : null;

    if (market === 'crypto') {
        return generatePriceSignals(
            market,
            currentData,
            previousData,
            config.markets.crypto.percentMoveAlert
        );
    }

    if (market === 'meme') {
        return generatePriceSignals(
            market,
            currentData,
            previousData,
            config.markets.meme.percentMoveAlert
        );
    }

    if (market === 'forex') {
        return generateForexSignals(
            currentData,
            previousData,
            config.markets.forex.percentMoveAlert
        );
    }

    if (market === 'collectibles') {
        return generateCollectibleSignals(currentData, previousData);
    }

    return [];
};

module.exports = {
    generateSignals
};
