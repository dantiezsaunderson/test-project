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

const normalizeSplits = (splits, targetCount) => {
    if (!targetCount) {
        return [];
    }
    if (!Array.isArray(splits) || splits.length !== targetCount) {
        return Array(targetCount).fill(1 / targetCount);
    }
    const sum = splits.reduce((acc, value) => acc + value, 0);
    if (!(sum > 0)) {
        return Array(targetCount).fill(1 / targetCount);
    }
    return splits.map((value) => value / sum);
};

const buildLiquidityPools = (levels, tolerancePct, minTouches) => {
    if (!Array.isArray(levels) || levels.length === 0) {
        return [];
    }
    if (!(tolerancePct > 0) || !(minTouches > 1)) {
        return [];
    }
    const sorted = [...levels].sort((a, b) => a - b);
    const pools = [];
    let bucket = [sorted[0]];
    for (let i = 1; i < sorted.length; i += 1) {
        const current = sorted[i];
        const last = bucket[bucket.length - 1];
        const within =
            Math.abs(current - last) / (last || 1) <= tolerancePct;
        if (within) {
            bucket.push(current);
        } else {
            if (bucket.length >= minTouches) {
                const avg =
                    bucket.reduce((acc, value) => acc + value, 0) /
                    bucket.length;
                pools.push({ price: avg, touches: bucket.length });
            }
            bucket = [current];
        }
    }
    if (bucket.length >= minTouches) {
        const avg = bucket.reduce((acc, value) => acc + value, 0) / bucket.length;
        pools.push({ price: avg, touches: bucket.length });
    }
    return pools;
};

const findNearestLiquidity = (pools, price, tolerancePct) => {
    if (!pools.length || !Number.isFinite(price)) {
        return null;
    }
    let nearest = null;
    pools.forEach((pool) => {
        const distancePct = Math.abs(price - pool.price) / (pool.price || 1);
        if (!nearest || distancePct < nearest.distancePct) {
            nearest = {
                level: pool.price,
                touches: pool.touches,
                distancePct,
                withinZone:
                    Number.isFinite(tolerancePct) && tolerancePct > 0
                        ? distancePct <= tolerancePct
                        : false
            };
        }
    });
    return nearest;
};

const buildTargets = ({
    direction,
    indicationLevel,
    correctionExtreme,
    swingHighs,
    swingLows,
    options
}) => {
    const riskDistance = Math.abs(indicationLevel - correctionExtreme);
    const dir = direction === 'bullish' ? 1 : -1;
    const highLevels = swingHighs.map((swing) => swing.price);
    const lowLevels = swingLows.map((swing) => swing.price);
    const liquidityPools = {
        highs: buildLiquidityPools(
            highLevels,
            options.liquidityTolerancePct,
            options.liquidityMinTouches
        ),
        lows: buildLiquidityPools(
            lowLevels,
            options.liquidityTolerancePct,
            options.liquidityMinTouches
        )
    };

    const poolLevels =
        direction === 'bullish'
            ? liquidityPools.highs.map((pool) => pool.price)
            : liquidityPools.lows.map((pool) => pool.price);
    const swingLevels = direction === 'bullish' ? highLevels : lowLevels;
    const candidates = (poolLevels.length ? poolLevels : swingLevels)
        .filter((level) =>
            direction === 'bullish'
                ? level > indicationLevel
                : level < indicationLevel
        )
        .sort((a, b) => (direction === 'bullish' ? a - b : b - a));

    const targets = [];
    const metadata = [];
    if (candidates.length) {
        targets.push(candidates[0]);
        metadata.push({
            level: candidates[0],
            source: poolLevels.length ? 'liquidity_pool' : 'swing'
        });
    }
    if (!targets.length && riskDistance > 0) {
        const level =
            indicationLevel + dir * riskDistance * (options.targetR1 || 1);
        targets.push(level);
        metadata.push({ level, source: 'extension_r1' });
    }
    if (candidates.length > 1) {
        targets.push(candidates[1]);
        metadata.push({
            level: candidates[1],
            source: poolLevels.length ? 'liquidity_pool' : 'swing'
        });
    } else if (riskDistance > 0) {
        const level =
            indicationLevel + dir * riskDistance * (options.targetR2 || 2);
        targets.push(level);
        metadata.push({ level, source: 'extension_r2' });
    }

    const uniqueTargets = [];
    const uniqueMeta = [];
    targets.forEach((level, index) => {
        if (!Number.isFinite(level)) {
            return;
        }
        if (
            direction === 'bullish' &&
            level <= indicationLevel
        ) {
            return;
        }
        if (
            direction === 'bearish' &&
            level >= indicationLevel
        ) {
            return;
        }
        if (uniqueTargets.some((existing) => Math.abs(existing - level) < 1e-8)) {
            return;
        }
        uniqueTargets.push(level);
        uniqueMeta.push(metadata[index]);
    });

    const takeProfitSplits = normalizeSplits(
        options.takeProfitSplits,
        uniqueTargets.length
    );

    const correctionPools =
        direction === 'bullish' ? liquidityPools.lows : liquidityPools.highs;
    const correctionLiquidity = findNearestLiquidity(
        correctionPools,
        correctionExtreme,
        options.liquidityTolerancePct
    );

    return {
        takeProfitLevels: uniqueTargets,
        takeProfitSplits,
        liquidityPools,
        liquidityTargets: uniqueMeta,
        correctionLiquidity
    };
};

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
    const displacementPct = indicationBullish
        ? (lastCandle.close - indicationLevel) / indicationLevel
        : (indicationLevel - lastCandle.close) / indicationLevel;

    if (
        Number.isFinite(options.minDisplacementPct) &&
        options.minDisplacementPct > 0 &&
        displacementPct < options.minDisplacementPct
    ) {
        return {
            status: 'WAIT',
            bias: indicationDirection,
            reasons: ['Indication without displacement'],
            indicationLevel,
            displacementPct,
            lastClose: lastCandle.close
        };
    }

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
    const targetPack = buildTargets({
        direction: indicationDirection,
        indicationLevel,
        correctionExtreme,
        swingHighs,
        swingLows,
        options
    });
    const takeProfit =
        targetPack.takeProfitLevels && targetPack.takeProfitLevels.length
            ? targetPack.takeProfitLevels[0]
            : indicationLevel;

    reasons.push('Continuation confirmed on entry timeframe');

    if (
        options.requireLiquidityZone &&
        targetPack.correctionLiquidity &&
        !targetPack.correctionLiquidity.withinZone
    ) {
        return {
            status: 'WAIT_CONTINUATION',
            bias: indicationDirection,
            reasons: ['Correction outside liquidity zone'],
            indicationLevel,
            correctionExtreme,
            correctionLiquidity: targetPack.correctionLiquidity,
            entryBreak: continuationBullish ? lastEntryHigh : lastEntryLow,
            lastClose: entryLast.close
        };
    }

    return {
        status,
        bias: indicationDirection,
        reasons,
        indicationLevel,
        stopLoss,
        takeProfit,
        takeProfitLevels: targetPack.takeProfitLevels,
        takeProfitSplits: targetPack.takeProfitSplits,
        liquidityPools: targetPack.liquidityPools,
        liquidityTargets: targetPack.liquidityTargets,
        correctionLiquidity: targetPack.correctionLiquidity,
        entryBreak: continuationBullish ? lastEntryHigh : lastEntryLow,
        lastClose: entryLast.close
    };
};

module.exports = {
    buildIccSignal
};
