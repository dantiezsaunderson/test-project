const clamp = (value, min, max) => Math.max(min, Math.min(max, value));

const computeRsi = (closes, period) => {
    if (!Array.isArray(closes) || closes.length < period + 1) {
        return null;
    }

    let gains = 0;
    let losses = 0;
    for (let i = closes.length - period; i < closes.length; i += 1) {
        const prev = closes[i - 1];
        const cur = closes[i];
        const diff = cur - prev;
        if (diff > 0) gains += diff;
        else losses += -diff;
    }

    const avgGain = gains / period;
    const avgLoss = losses / period;
    if (avgLoss === 0) return 100;
    const rs = avgGain / avgLoss;
    const rsi = 100 - 100 / (1 + rs);
    return clamp(rsi, 0, 100);
};

const sma = (values, period) => {
    if (!Array.isArray(values) || values.length < period) return null;
    const slice = values.slice(values.length - period);
    const sum = slice.reduce((a, b) => a + b, 0);
    return sum / period;
};

const slopeLast = (values, points) => {
    if (!Array.isArray(values) || values.length < points) return null;
    const slice = values.slice(values.length - points);
    const first = slice[0];
    const last = slice[slice.length - 1];
    return (last - first) / (points - 1);
};

const ema = (values, period) => {
    if (!Array.isArray(values) || values.length < period) return null;
    const k = 2 / (period + 1);
    let prev = values[0];
    for (let i = 1; i < values.length; i += 1) {
        prev = values[i] * k + prev * (1 - k);
    }
    return prev;
};

const computeMacd = (closes, fast, slow, signal) => {
    if (!Array.isArray(closes) || closes.length < slow + signal) return null;

    const fastEma = ema(closes, fast);
    const slowEma = ema(closes, slow);
    if (fastEma === null || slowEma === null) return null;

    const macdLine = fastEma - slowEma;

    const macdSeries = [];
    for (let i = 0; i < closes.length; i += 1) {
        const sub = closes.slice(0, i + 1);
        const f = ema(sub, fast);
        const s = ema(sub, slow);
        if (f === null || s === null) continue;
        macdSeries.push(f - s);
    }

    const signalLine = ema(macdSeries, signal);
    if (signalLine === null) return null;

    const hist = macdLine - signalLine;
    const prevHist =
        macdSeries.length >= signal + 1
            ? macdSeries[macdSeries.length - 2] -
              ema(macdSeries.slice(0, macdSeries.length - 1), signal)
            : null;

    return {
        macd: macdLine,
        signal: signalLine,
        hist,
        histDelta: prevHist === null ? null : hist - prevHist
    };
};

const computeHeikenAshi = (candles) => {
    if (!Array.isArray(candles) || candles.length === 0) return [];

    const ha = [];
    for (let i = 0; i < candles.length; i += 1) {
        const c = candles[i];
        const haClose = (c.open + c.high + c.low + c.close) / 4;

        const prev = ha[i - 1];
        const haOpen = prev ? (prev.open + prev.close) / 2 : (c.open + c.close) / 2;

        const haHigh = Math.max(c.high, haOpen, haClose);
        const haLow = Math.min(c.low, haOpen, haClose);

        ha.push({
            open: haOpen,
            high: haHigh,
            low: haLow,
            close: haClose,
            isGreen: haClose >= haOpen,
            body: Math.abs(haClose - haOpen)
        });
    }
    return ha;
};

const countConsecutive = (haCandles) => {
    if (!Array.isArray(haCandles) || haCandles.length === 0) {
        return { color: null, count: 0 };
    }

    const last = haCandles[haCandles.length - 1];
    const target = last.isGreen ? 'green' : 'red';

    let count = 0;
    for (let i = haCandles.length - 1; i >= 0; i -= 1) {
        const c = haCandles[i];
        const color = c.isGreen ? 'green' : 'red';
        if (color !== target) break;
        count += 1;
    }

    return { color: target, count };
};

const computeSessionVwap = (candles) => {
    if (!Array.isArray(candles) || candles.length === 0) return null;

    let pv = 0;
    let v = 0;
    for (const c of candles) {
        const tp = (c.high + c.low + c.close) / 3;
        pv += tp * c.volume;
        v += c.volume;
    }
    if (v === 0) return null;
    return pv / v;
};

const computeVwapSeries = (candles) => {
    const series = [];
    for (let i = 0; i < candles.length; i += 1) {
        const sub = candles.slice(0, i + 1);
        series.push(computeSessionVwap(sub));
    }
    return series;
};

module.exports = {
    computeRsi,
    sma,
    slopeLast,
    computeMacd,
    computeHeikenAshi,
    countConsecutive,
    computeSessionVwap,
    computeVwapSeries,
    ema
};
