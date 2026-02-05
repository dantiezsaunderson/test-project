const indicators = require('./blofinIndicators');

const getLast = (array) => array[array.length - 1];

const detectFvg = (candles, lookback) => {
    if (candles.length < 3) {
        return null;
    }
    const start = Math.max(2, candles.length - lookback);
    for (let i = candles.length - 1; i >= start; i -= 1) {
        const c0 = candles[i - 2];
        const c2 = candles[i];
        if (!c0 || !c2) continue;
        if (c0.high < c2.low) {
            return {
                direction: 'bullish',
                low: c0.high,
                high: c2.low
            };
        }
        if (c0.low > c2.high) {
            return {
                direction: 'bearish',
                low: c2.high,
                high: c0.low
            };
        }
    }
    return null;
};

const findSwingLevels = (candles, lookback) => {
    const slice = candles.slice(Math.max(0, candles.length - lookback));
    let swingHigh = null;
    let swingLow = null;
    slice.forEach((candle) => {
        if (swingHigh === null || candle.high > swingHigh) {
            swingHigh = candle.high;
        }
        if (swingLow === null || candle.low < swingLow) {
            swingLow = candle.low;
        }
    });
    return { swingHigh, swingLow };
};

const detectLiquiditySweep = (candles, lookback) => {
    if (candles.length < 2) {
        return { bullish: false, bearish: false };
    }
    const last = getLast(candles);
    const slice = candles.slice(Math.max(0, candles.length - lookback - 1), -1);
    const lows = slice.map((c) => c.low);
    const highs = slice.map((c) => c.high);
    const minLow = Math.min(...lows);
    const maxHigh = Math.max(...highs);
    const bullish = last.low < minLow && last.close > last.open;
    const bearish = last.high > maxHigh && last.close < last.open;
    return { bullish, bearish };
};

const computeBias = (closes, fast, slow) => {
    const fastEma = indicators.ema(closes, fast);
    const slowEma = indicators.ema(closes, slow);
    if (fastEma === null || slowEma === null) {
        return { bias: 'neutral', fastEma, slowEma };
    }
    if (fastEma > slowEma) {
        return { bias: 'bullish', fastEma, slowEma };
    }
    if (fastEma < slowEma) {
        return { bias: 'bearish', fastEma, slowEma };
    }
    return { bias: 'neutral', fastEma, slowEma };
};

const buildIccSignal = (candles, options) => {
    if (!Array.isArray(candles) || candles.length < options.minCandles) {
        return null;
    }
    const last = getLast(candles);
    const closes = candles.map((c) => c.close);
    const biasInfo = computeBias(closes, options.emaFast, options.emaSlow);
    const swing = findSwingLevels(candles, options.mssLookback);
    const sweep = detectLiquiditySweep(candles, options.sweepLookback);
    const fvg = detectFvg(candles, options.fvgLookback);
    const rsi = indicators.computeRsi(closes, options.rsiPeriod);
    const macd = indicators.computeMacd(
        closes,
        options.macdFast,
        options.macdSlow,
        options.macdSignal
    );
    const vwapSeries = indicators.computeVwapSeries(candles);
    const vwap = getLast(vwapSeries);
    const vwapDist =
        vwap && vwap !== 0 ? (last.close - vwap) / vwap : null;
    const heiken = indicators.computeHeikenAshi(candles);
    const heikenTrend = indicators.countConsecutive(heiken);

    const mssBullish = swing.swingHigh !== null && last.close > swing.swingHigh;
    const mssBearish = swing.swingLow !== null && last.close < swing.swingLow;

    const reasons = [];
    let score = 0;
    const direction = biasInfo.bias;

    if (direction === 'bullish') {
        score += 1;
        reasons.push('EMA bias bullish');
    } else if (direction === 'bearish') {
        score += 1;
        reasons.push('EMA bias bearish');
    }

    if (sweep.bullish && direction === 'bullish') {
        score += 1;
        reasons.push('Liquidity sweep down');
    }
    if (sweep.bearish && direction === 'bearish') {
        score += 1;
        reasons.push('Liquidity sweep up');
    }

    if (mssBullish && direction === 'bullish') {
        score += 1;
        reasons.push('Market structure shift up');
    }
    if (mssBearish && direction === 'bearish') {
        score += 1;
        reasons.push('Market structure shift down');
    }

    if (fvg && fvg.direction === direction) {
        score += 1;
        reasons.push('FVG aligns with bias');
    }

    if (
        rsi !== null &&
        ((direction === 'bullish' && rsi >= options.rsiBull) ||
            (direction === 'bearish' && rsi <= options.rsiBear))
    ) {
        score += 1;
        reasons.push('RSI momentum confirmation');
    }

    if (
        macd &&
        ((direction === 'bullish' && macd.hist > 0) ||
            (direction === 'bearish' && macd.hist < 0))
    ) {
        score += 1;
        reasons.push('MACD confirmation');
    }

    const setup = score >= options.minScore ? direction : 'wait';

    return {
        bias: direction,
        score,
        setup,
        reasons,
        sweep,
        mss: { bullish: mssBullish, bearish: mssBearish },
        fvg,
        rsi,
        macd,
        vwap,
        vwapDist,
        heiken: heikenTrend,
        lastClose: last.close
    };
};

module.exports = {
    buildIccSignal
};
