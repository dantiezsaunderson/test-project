const getLast = (array) => array[array.length - 1];

const findSwings = (candles, pivot) => {
    const highs = [];
    const lows = [];
    for (let i = pivot; i < candles.length - pivot; i += 1) {
        const currentHigh = candles[i].high;
        const currentLow = candles[i].low;
        let isHigh = true;
        let isLow = true;
        for (let j = 1; j <= pivot; j += 1) {
            if (candles[i - j].high >= currentHigh || candles[i + j].high > currentHigh) {
                isHigh = false;
            }
            if (candles[i - j].low <= currentLow || candles[i + j].low < currentLow) {
                isLow = false;
            }
        }
        if (isHigh) {
            highs.push({ index: i, price: currentHigh });
        }
        if (isLow) {
            lows.push({ index: i, price: currentLow });
        }
    }
    return { highs, lows };
};

const determineTrend = (highs, lows) => {
    if (highs.length < 2 || lows.length < 2) {
        return 'unknown';
    }
    const lastHigh = highs[highs.length - 1].price;
    const prevHigh = highs[highs.length - 2].price;
    const lastLow = lows[lows.length - 1].price;
    const prevLow = lows[lows.length - 2].price;

    if (lastHigh > prevHigh && lastLow > prevLow) {
        return 'up';
    }
    if (lastHigh < prevHigh && lastLow < prevLow) {
        return 'down';
    }
    return 'consolidation';
};

const getRangeSlice = (candles, startIndex) =>
    candles.slice(Math.max(0, startIndex));

const buildIccSignal = (highCandles, entryCandles, options) => {
    if (
        !Array.isArray(highCandles) ||
        !Array.isArray(entryCandles) ||
        highCandles.length < options.minCandles ||
        entryCandles.length < options.entryMinCandles
    ) {
        return null;
    }

    const highSlice = highCandles.slice(
        Math.max(0, highCandles.length - options.swingLookback)
    );
    const highOffset = highCandles.length - highSlice.length;
    const { highs, lows } = findSwings(highSlice, options.swingPivot);
    const swingHighs = highs.map((h) => ({
        index: h.index + highOffset,
        price: h.price
    }));
    const swingLows = lows.map((l) => ({
        index: l.index + highOffset,
        price: l.price
    }));

    const trend = determineTrend(swingHighs, swingLows);
    const lastCandle = getLast(highCandles);
    const reasons = [];

    if (trend === 'consolidation' || trend === 'unknown') {
        return {
            status: 'NO_TRADE',
            bias: 'neutral',
            reasons: ['No clear market structure'],
            lastClose: lastCandle.close
        };
    }

    const lastSwingHigh = swingHighs[swingHighs.length - 1];
    const prevSwingHigh = swingHighs[swingHighs.length - 2];
    const lastSwingLow = swingLows[swingLows.length - 1];
    const prevSwingLow = swingLows[swingLows.length - 2];

    const indicationBullish =
        trend === 'up' && lastCandle.close > lastSwingHigh.price;
    const indicationBearish =
        trend === 'down' && lastCandle.close < lastSwingLow.price;

    if (!indicationBullish && !indicationBearish) {
        return {
            status: 'WAIT',
            bias: trend === 'up' ? 'bullish' : 'bearish',
            reasons: ['Waiting for indication'],
            lastClose: lastCandle.close,
            swingHigh: lastSwingHigh.price,
            swingLow: lastSwingLow.price
        };
    }

    const indicationDirection = indicationBullish ? 'bullish' : 'bearish';
    const indicationLevel = indicationBullish
        ? lastSwingHigh.price
        : lastSwingLow.price;
    const indicationIndex = indicationBullish
        ? lastSwingHigh.index
        : lastSwingLow.index;
    const rangeSlice = getRangeSlice(highCandles, indicationIndex);
    const impulseHigh = Math.max(...rangeSlice.map((c) => c.high));
    const impulseLow = Math.min(...rangeSlice.map((c) => c.low));

    let correctionComplete = false;
    let retrace = null;
    let correctionExtreme = null;
    let correctionTarget = null;

    if (indicationBullish) {
        const range = impulseHigh - prevSwingLow.price;
        retrace = range > 0 ? (impulseHigh - lastCandle.close) / range : null;
        correctionComplete = retrace !== null && retrace >= options.correctionThreshold;
        correctionExtreme = impulseLow;
        correctionTarget = prevSwingLow.price;
    } else {
        const range = prevSwingHigh.price - impulseLow;
        retrace = range > 0 ? (lastCandle.close - impulseLow) / range : null;
        correctionComplete = retrace !== null && retrace >= options.correctionThreshold;
        correctionExtreme = impulseHigh;
        correctionTarget = prevSwingHigh.price;
    }

    if (!correctionComplete) {
        return {
            status: 'WAIT_CORRECTION',
            bias: indicationDirection,
            reasons: ['Indication detected, waiting for correction'],
            indicationLevel,
            retrace,
            correctionTarget,
            lastClose: lastCandle.close
        };
    }

    const entrySlice = entryCandles.slice(
        Math.max(0, entryCandles.length - options.entryLookback)
    );
    const entryOffset = entryCandles.length - entrySlice.length;
    const { highs: entryHighsRaw, lows: entryLowsRaw } = findSwings(
        entrySlice,
        options.entryPivot
    );
    const entryHighs = entryHighsRaw.map((h) => ({
        index: h.index + entryOffset,
        price: h.price
    }));
    const entryLows = entryLowsRaw.map((l) => ({
        index: l.index + entryOffset,
        price: l.price
    }));
    const entryLast = getLast(entryCandles);

    const lastEntryHigh =
        entryHighs.length > 0 ? entryHighs[entryHighs.length - 1].price : null;
    const lastEntryLow =
        entryLows.length > 0 ? entryLows[entryLows.length - 1].price : null;

    const continuationBullish =
        indicationBullish && lastEntryHigh !== null && entryLast.close > lastEntryHigh;
    const continuationBearish =
        indicationBearish && lastEntryLow !== null && entryLast.close < lastEntryLow;

    if (!(continuationBullish || continuationBearish)) {
        return {
            status: 'WAIT_CONTINUATION',
            bias: indicationDirection,
            reasons: ['Correction complete, waiting for continuation'],
            indicationLevel,
            correctionExtreme,
            retrace,
            entryBreak: indicationBullish ? lastEntryHigh : lastEntryLow,
            lastClose: entryLast.close
        };
    }

    const status = continuationBullish ? 'BUY' : 'SELL';
    const stopLoss = correctionExtreme;
    const takeProfit = indicationLevel;

    reasons.push('Continuation confirmed on entry timeframe');

    return {
        status,
        bias: indicationDirection,
        reasons,
        indicationLevel,
        stopLoss,
        takeProfit,
        entryBreak: continuationBullish ? lastEntryHigh : lastEntryLow,
        lastClose: entryLast.close
    };
};

module.exports = {
    buildIccSignal
};
