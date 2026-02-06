const round = (value, digits = 4) => {
    const factor = 10 ** digits;
    return Math.round(value * factor) / factor;
};

const buildVolumeProfile = (candles, options) => {
    const prices = candles
        .map((candle) => candle.close)
        .filter((value) => Number.isFinite(value));
    if (!prices.length) {
        return null;
    }
    const minPrice = Math.min(...prices);
    const maxPrice = Math.max(...prices);
    const avgPrice = prices.reduce((acc, value) => acc + value, 0) / prices.length;
    const bucketSize = Math.max(avgPrice * options.bucketPct, 1e-6);
    const buckets = new Map();

    candles.forEach((candle) => {
        const price = candle.close;
        const volume = Number(candle.volume);
        if (!Number.isFinite(price) || !Number.isFinite(volume)) {
            return;
        }
        const index = Math.round((price - minPrice) / bucketSize);
        const bucketPrice = minPrice + index * bucketSize;
        const key = bucketPrice.toFixed(6);
        buckets.set(key, {
            price: bucketPrice,
            volume: (buckets.get(key)?.volume || 0) + volume
        });
    });

    const bucketList = Array.from(buckets.values()).sort(
        (a, b) => a.price - b.price
    );
    const totalVolume = bucketList.reduce((acc, bucket) => acc + bucket.volume, 0);
    if (!bucketList.length || totalVolume === 0) {
        return null;
    }

    const pocBucket = bucketList.reduce(
        (max, bucket) => (bucket.volume > max.volume ? bucket : max),
        bucketList[0]
    );
    const sortedByVolume = [...bucketList].sort(
        (a, b) => b.volume - a.volume
    );

    const valueAreaTarget = totalVolume * options.valueAreaPct;
    let accumulated = 0;
    const valueBuckets = [];
    for (const bucket of sortedByVolume) {
        if (accumulated >= valueAreaTarget) {
            break;
        }
        valueBuckets.push(bucket);
        accumulated += bucket.volume;
    }
    const valuePrices = valueBuckets.map((bucket) => bucket.price);
    const vah = Math.max(...valuePrices);
    const val = Math.min(...valuePrices);

    const maxVolume = pocBucket.volume;
    const hvn = bucketList.filter(
        (bucket) => bucket.volume >= maxVolume * options.hvnRatio
    );
    const lvn = bucketList.filter(
        (bucket) => bucket.volume <= maxVolume * options.lvnRatio
    );

    return {
        minPrice,
        maxPrice,
        poc: pocBucket.price,
        vah,
        val,
        hvn: hvn.map((bucket) => bucket.price),
        lvn: lvn.map((bucket) => bucket.price),
        buckets: bucketList
    };
};

const getSessionLabel = (now, options) => {
    const hour = now.getUTCHours();
    if (hour >= options.nyStartHour && hour < options.nyEndHour) {
        return 'new_york';
    }
    if (hour >= options.londonStartHour && hour < options.londonEndHour) {
        return 'london';
    }
    return 'off_session';
};

const buildFabiaSignal = (candles, options, now = new Date()) => {
    if (!Array.isArray(candles) || candles.length < 5) {
        return { status: 'insufficient_data' };
    }
    const sorted = [...candles].sort((a, b) => a.ts - b.ts);
    const profile = buildVolumeProfile(sorted, options);
    if (!profile) {
        return { status: 'profile_unavailable' };
    }

    const range = profile.maxPrice - profile.minPrice;
    const valueAreaWidth = profile.vah - profile.val;
    const valueAreaPct = range > 0 ? valueAreaWidth / range : 0;

    const firstClose = sorted[0].close;
    const lastClose = sorted[sorted.length - 1].close;
    const trendStrength =
        range > 0 ? Math.abs(lastClose - firstClose) / range : 0;
    const trendDirection = lastClose >= firstClose ? 'up' : 'down';

    const balanced =
        valueAreaPct >= options.balanceThreshold &&
        trendStrength < options.trendThreshold;

    const session = getSessionLabel(now, options);
    const sessionMode = options.sessionMode;
    const allowTrend =
        sessionMode === 'auto'
            ? session === 'new_york'
            : sessionMode === 'new_york';
    const allowMean =
        sessionMode === 'auto'
            ? session === 'london'
            : sessionMode === 'london';

    const prevClose = sorted[sorted.length - 2].close;
    const insideValue =
        lastClose <= profile.vah && lastClose >= profile.val;
    const prevOutsideAbove = prevClose > profile.vah;
    const prevOutsideBelow = prevClose < profile.val;

    const signal = {
        status: 'monitor',
        marketState: balanced ? 'balanced' : 'imbalanced',
        session,
        profile: {
            poc: round(profile.poc),
            vah: round(profile.vah),
            val: round(profile.val),
            hvn: profile.hvn.slice(0, 5).map((level) => round(level)),
            lvn: profile.lvn.slice(0, 5).map((level) => round(level))
        },
        trend: {
            direction: trendDirection,
            strength: round(trendStrength, 4),
            valueAreaPct: round(valueAreaPct, 4)
        },
        notes: []
    };

    if (balanced && allowMean && insideValue && (prevOutsideAbove || prevOutsideBelow)) {
        const direction = prevOutsideAbove ? 'sell' : 'buy';
        const stop =
            direction === 'sell'
                ? profile.vah * (1 + options.stopBufferPct)
                : profile.val * (1 - options.stopBufferPct);
        signal.status = 'mean_reversion';
        signal.direction = direction;
        signal.entry = round(lastClose);
        signal.target = round(profile.poc);
        signal.stop = round(stop);
        signal.notes.push('Failed breakout back into value area.');
        signal.notes.push('Order-flow confirmation required.');
        return signal;
    }

    if (!balanced && allowTrend) {
        const breakoutUp = prevClose <= profile.vah && lastClose > profile.vah;
        const breakoutDown = prevClose >= profile.val && lastClose < profile.val;
        const breakoutDirection = breakoutUp ? 'buy' : breakoutDown ? 'sell' : null;

        const pullbackLevel = breakoutDirection === 'buy' ? profile.vah : profile.val;
        const pullbackTolerance = pullbackLevel * options.pullbackTolerancePct;
        const pullback =
            breakoutDirection &&
            Math.abs(lastClose - pullbackLevel) <= pullbackTolerance;

        if (breakoutDirection) {
            signal.status = pullback ? 'trend_pullback' : 'trend_breakout';
            signal.direction = breakoutDirection;
            signal.entry = round(lastClose);
            signal.pullbackLevel = round(pullbackLevel);
            signal.notes.push(
                pullback
                    ? 'Pullback to value edge after breakout.'
                    : 'Breakout detected; waiting for pullback.'
            );
            signal.notes.push('Order-flow confirmation required.');
            return signal;
        }
    }

    return signal;
};

module.exports = {
    buildFabiaSignal
};
