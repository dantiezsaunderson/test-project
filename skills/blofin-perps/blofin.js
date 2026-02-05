#!/usr/bin/env node

const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../../.env') });

const config = require('../../config');
const blofinClient = require('../../blofinClient');
const blofinScanner = require('../../blofinScanner');
const { runBlofinAutoTrade } = require('../../autoTrader');
const dataStore = require('../../dataStore');

const helpText = `
Blofin Perps CLI

Usage:
  blofin.js scan --limit 5
  blofin.js auto --limit 5
  blofin.js report --days 7 [--perf]
  blofin.js positions
  blofin.js balance
  blofin.js order --inst BTC-USDT --side buy --type market --size 1 --confirm

Options:
  --limit <number>
  --days <number>
  --perf
  --inst <instId>
  --side buy|sell
  --type market|limit
  --size <number>
  --price <number>
  --confirm
`.trim();

const parseArgs = (args) => {
    const options = { flags: new Set() };
    const rest = [];
    for (let i = 0; i < args.length; i += 1) {
        const arg = args[i];
        if (arg.startsWith('--')) {
            const key = arg.replace(/^--/, '');
            if (key === 'confirm') {
                options.flags.add('confirm');
            } else if (key === 'perf' || key === 'performance') {
                options.flags.add('perf');
            } else {
                options[key] = args[i + 1];
                i += 1;
            }
        } else {
            rest.push(arg);
        }
    }
    return { options, rest };
};

const toNumber = (value, fallback = null) => {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
};

const sortCandles = (candles) =>
    [...candles].sort((a, b) => Number(a.ts) - Number(b.ts));

const getSessionLabel = (timestamp) => {
    const date = new Date(timestamp);
    if (Number.isNaN(date.getTime())) {
        return 'unknown';
    }
    const hour = date.getUTCHours();
    if (hour >= 13 && hour < 16) {
        return 'london_ny';
    }
    if (hour >= 7 && hour < 13) {
        return 'london';
    }
    if (hour >= 16 && hour < 22) {
        return 'ny';
    }
    return 'asia';
};

const computeSharpe = (values) => {
    if (!values.length) {
        return 0;
    }
    const mean =
        values.reduce((acc, value) => acc + value, 0) / values.length;
    const variance =
        values.reduce((acc, value) => acc + (value - mean) ** 2, 0) /
        values.length;
    const std = Math.sqrt(variance);
    if (std === 0) {
        return 0;
    }
    return (mean / std) * Math.sqrt(values.length);
};

const normalizeSplits = (splits, count) => {
    if (!count) {
        return [];
    }
    if (!Array.isArray(splits) || splits.length !== count) {
        return Array(count).fill(1 / count);
    }
    const total = splits.reduce((acc, value) => acc + value, 0);
    if (!(total > 0)) {
        return Array(count).fill(1 / count);
    }
    return splits.map((value) => value / total);
};

const buildTargetPlan = (trade, entryPrice, isBuy) => {
    let levels = [];
    if (Array.isArray(trade.takeProfitLevels) && trade.takeProfitLevels.length) {
        levels = trade.takeProfitLevels;
    } else if (
        Array.isArray(trade.signal?.takeProfitLevels) &&
        trade.signal.takeProfitLevels.length
    ) {
        levels = trade.signal.takeProfitLevels;
    } else {
        const fallback = toNumber(
            trade.takeProfit ?? trade.signal?.takeProfit,
            null
        );
        if (Number.isFinite(fallback)) {
            levels = [fallback];
        }
    }

    const filtered = levels
        .map((level) => toNumber(level, null))
        .filter((level) => Number.isFinite(level))
        .filter((level) => (isBuy ? level > entryPrice : level < entryPrice))
        .sort((a, b) => (isBuy ? a - b : b - a));

    if (!filtered.length) {
        return [];
    }

    const splits = Array.isArray(trade.takeProfitSplits)
        ? trade.takeProfitSplits
        : trade.signal?.takeProfitSplits;
    const normalized = normalizeSplits(splits, filtered.length);
    return filtered.map((level, index) => ({
        level,
        split: normalized[index],
        hit: false
    }));
};

const evaluateTrade = (trade, candles) => {
    const entryPrice = toNumber(trade.price, null);
    const stopLoss = toNumber(
        trade.stopLoss ?? trade.signal?.stopLoss,
        null
    );
    const tradeTime = new Date(trade.timestamp || '').getTime();
    if (!Number.isFinite(tradeTime)) {
        return { outcome: 'invalid', reason: 'missing_timestamp' };
    }
    if (!Number.isFinite(entryPrice)) {
        return { outcome: 'invalid', reason: 'missing_entry_price' };
    }
    if (!Number.isFinite(stopLoss)) {
        return { outcome: 'invalid', reason: 'missing_stop_loss' };
    }
    if (!trade.side || !['buy', 'sell'].includes(trade.side)) {
        return { outcome: 'invalid', reason: 'missing_side' };
    }

    const isBuy = trade.side === 'buy';
    const risk = isBuy ? entryPrice - stopLoss : stopLoss - entryPrice;
    if (!(risk > 0)) {
        return { outcome: 'invalid', reason: 'invalid_stop_distance' };
    }
    const targetPlan = buildTargetPlan(trade, entryPrice, isBuy);
    if (!targetPlan.length) {
        return { outcome: 'invalid', reason: 'missing_targets' };
    }

    const timeline = candles.filter((candle) => candle.ts >= tradeTime);
    if (!timeline.length) {
        return { outcome: 'insufficient_data', reason: 'no_future_candles' };
    }

    let remaining = 1;
    let totalR = 0;
    const partials = [];

    for (const candle of timeline) {
        const stopHit = isBuy
            ? candle.low <= stopLoss
            : candle.high >= stopLoss;
        const targetHitInCandle = targetPlan.some((target) =>
            isBuy ? candle.high >= target.level : candle.low <= target.level
        );

        if (stopHit) {
            if (remaining > 0) {
                totalR += -1 * remaining;
            }
            const outcome =
                totalR > 0 ? 'win' : totalR < 0 ? 'loss' : 'breakeven';
            return {
                outcome,
                exitPrice: stopLoss,
                exitTime: candle.ts,
                exitReason: targetHitInCandle
                    ? 'stop_and_target_same_candle'
                    : 'stop_hit',
                rMultiple: totalR,
                partials
            };
        }

        for (const target of targetPlan) {
            if (target.hit) {
                continue;
            }
            const hit = isBuy
                ? candle.high >= target.level
                : candle.low <= target.level;
            if (!hit) {
                continue;
            }
            target.hit = true;
            const reward = isBuy
                ? target.level - entryPrice
                : entryPrice - target.level;
            const rMultiple = reward / risk;
            const split = Math.min(target.split, remaining);
            totalR += rMultiple * split;
            remaining -= split;
            partials.push({
                level: target.level,
                split,
                rMultiple,
                time: candle.ts
            });
        }

        if (remaining <= 1e-6) {
            const outcome =
                totalR > 0 ? 'win' : totalR < 0 ? 'loss' : 'breakeven';
            const lastTarget = partials[partials.length - 1];
            return {
                outcome,
                exitPrice: lastTarget ? lastTarget.level : undefined,
                exitTime: lastTarget ? lastTarget.time : candle.ts,
                exitReason: 'all_targets_hit',
                rMultiple: totalR,
                partials
            };
        }
    }

    const last = timeline[timeline.length - 1];
    const unrealized = isBuy
        ? (last.close - entryPrice) / risk
        : (entryPrice - last.close) / risk;
    return {
        outcome: 'open',
        exitReason: 'still_open',
        rMultiple: totalR,
        unrealizedR: unrealized,
        remainingFraction: remaining,
        partials,
        lastPrice: last.close,
        lastTime: last.ts
    };
};

const formatSignal = (entry) => {
    const status = entry.signal?.status || 'WAIT';
    const bias = entry.signal?.bias || 'neutral';
    const reason = Array.isArray(entry.signal?.reasons)
        ? entry.signal.reasons.join('; ')
        : '';
    const levels = [];
    if (entry.signal?.indicationLevel) {
        levels.push(`indication ${entry.signal.indicationLevel}`);
    }
    if (entry.signal?.stopLoss) {
        levels.push(`SL ${entry.signal.stopLoss}`);
    }
    if (
        Array.isArray(entry.signal?.takeProfitLevels) &&
        entry.signal.takeProfitLevels.length
    ) {
        const preview = entry.signal.takeProfitLevels
            .slice(0, 2)
            .map((level) => Number(level).toFixed(2));
        const suffix =
            entry.signal.takeProfitLevels.length > 2 ? ' +' : '';
        levels.push(`TPs ${preview.join(', ')}${suffix}`);
    } else if (entry.signal?.takeProfit) {
        levels.push(`TP ${entry.signal.takeProfit}`);
    }
    const levelText = levels.length ? ` | ${levels.join(' / ')}` : '';
    return `${entry.instId} | ${status} (${bias})${levelText} | ${reason}`;
};

const scanSignals = async (options) => {
    const scan = await blofinScanner.fetchSignals();
    const limit = Number(options.limit || 5);
    const list = scan.signals.slice(0, limit);
    if (!list.length) {
        console.log('No signals found.');
        return;
    }
    list.forEach((entry) => {
        console.log(formatSignal(entry));
    });
};

const autoTradeOnce = async (options) => {
    const scan = await blofinScanner.fetchSignals();
    const limit = Number(options.limit || 0);
    const signals = limit > 0 ? scan.signals.slice(0, limit) : scan.signals;
    const result = await runBlofinAutoTrade({
        signals,
        reason: 'cli-auto'
    });
    console.log(JSON.stringify(result, null, 2));
};

const reportAutoTrades = async (options) => {
    const days = Number(options.days || 7);
    const sinceMs = Date.now() - days * 24 * 60 * 60 * 1000;
    const trades = await dataStore.getAutoTrades();
    const filtered = trades.filter((trade) => {
        if (!trade || !trade.timestamp) {
            return false;
        }
        const ts = new Date(trade.timestamp).getTime();
        return Number.isFinite(ts) && ts >= sinceMs;
    });

    if (options.flags.has('perf') && filtered.length) {
        const grouped = filtered.reduce((acc, trade) => {
            if (!trade.instId) {
                return acc;
            }
            acc[trade.instId] = acc[trade.instId] || [];
            acc[trade.instId].push(trade);
            return acc;
        }, {});

        const updates = new Map();
        for (const instId of Object.keys(grouped)) {
            const candles = await blofinClient.fetchCandles({
                instId,
                bar: config.markets.blofin.entryTimeframe,
                limit: config.markets.blofin.performanceCandleLimit
            });
            const sorted = sortCandles(candles);
            grouped[instId].forEach((trade) => {
                const evaluation = evaluateTrade(trade, sorted);
                updates.set(trade.tradeId || trade.timestamp, {
                    ...trade,
                    evaluation: {
                        ...evaluation,
                        evaluatedAt: new Date().toISOString()
                    }
                });
            });
        }

        if (updates.size) {
            await dataStore.updateAutoTrades((allTrades) =>
                allTrades.map((trade) => {
                    const key = trade.tradeId || trade.timestamp;
                    return updates.get(key) || trade;
                })
            );
        }
    }

    const refreshed = await dataStore.getAutoTrades();
    const evaluated = refreshed.filter((trade) => {
        if (!trade || !trade.timestamp) {
            return false;
        }
        const ts = new Date(trade.timestamp).getTime();
        return Number.isFinite(ts) && ts >= sinceMs;
    });

    const summary = {
        since: new Date(sinceMs).toISOString(),
        total: evaluated.length,
        dryRun: evaluated.filter((trade) => trade.status === 'dry-run').length,
        submitted: evaluated.filter((trade) => trade.status !== 'dry-run').length,
        totalClosed: 0,
        totalOpen: 0,
        totalNotional: 0,
        avgNotional: 0,
        totalRiskUsd: 0,
        avgRiskUsd: 0,
        totalR: 0,
        avgR: 0,
        sharpeR: 0,
        profitFactor: 0,
        winRate: 0,
        outcomes: {},
        byMode: {},
        byInst: {},
        bySide: {},
        bySession: {},
        winRateByInst: {},
        equityCurve: []
    };

    const closedTrades = [];
    const rSeries = [];
    let wins = 0;
    let losses = 0;
    let grossWin = 0;
    let grossLoss = 0;

    evaluated.forEach((trade) => {
        const instId = trade.instId || 'unknown';
        const side = trade.side || 'unknown';
        const mode = trade.sizingMode || 'unknown';
        const notional = Number(trade.notional || 0);
        const riskUsd = Number(trade.riskUsdActual || 0);
        const outcome = trade.evaluation?.outcome || 'unknown';
        const rMultiple = Number(trade.evaluation?.rMultiple);
        summary.byInst[instId] = (summary.byInst[instId] || 0) + 1;
        summary.bySide[side] = (summary.bySide[side] || 0) + 1;
        summary.byMode[mode] = (summary.byMode[mode] || 0) + 1;
        summary.outcomes[outcome] = (summary.outcomes[outcome] || 0) + 1;
        summary.totalNotional += Number.isFinite(notional) ? notional : 0;
        summary.totalRiskUsd += Number.isFinite(riskUsd) ? riskUsd : 0;

        if (outcome === 'win' || outcome === 'loss' || outcome === 'breakeven') {
            summary.totalClosed += 1;
            closedTrades.push(trade);
            if (Number.isFinite(rMultiple)) {
                rSeries.push(rMultiple);
                summary.totalR += rMultiple;
                if (outcome === 'win') {
                    wins += 1;
                    grossWin += rMultiple;
                } else if (outcome === 'loss') {
                    losses += 1;
                    grossLoss += Math.abs(rMultiple);
                }
            }
        } else if (outcome === 'open') {
            summary.totalOpen += 1;
        }

        const session = getSessionLabel(trade.timestamp);
        summary.bySession[session] = summary.bySession[session] || {
            total: 0,
            wins: 0,
            losses: 0,
            winRate: 0
        };
        summary.bySession[session].total += 1;
        if (outcome === 'win') {
            summary.bySession[session].wins += 1;
        }
        if (outcome === 'loss') {
            summary.bySession[session].losses += 1;
        }
        summary.bySession[session].winRate =
            summary.bySession[session].wins +
                summary.bySession[session].losses >
            0
                ? summary.bySession[session].wins /
                  (summary.bySession[session].wins +
                      summary.bySession[session].losses)
                : 0;
    });

    if (summary.total > 0) {
        summary.avgNotional = summary.totalNotional / summary.total;
        summary.avgRiskUsd = summary.totalRiskUsd / summary.total;
    }
    if (summary.totalClosed > 0) {
        summary.avgR = summary.totalR / summary.totalClosed;
        summary.sharpeR = computeSharpe(rSeries);
        summary.profitFactor = grossLoss > 0 ? grossWin / grossLoss : 0;
        summary.winRate = wins + losses > 0 ? wins / (wins + losses) : 0;
    }

    closedTrades.forEach((trade) => {
        const instId = trade.instId || 'unknown';
        summary.winRateByInst[instId] = summary.winRateByInst[instId] || {
            wins: 0,
            losses: 0,
            winRate: 0
        };
        if (trade.evaluation?.outcome === 'win') {
            summary.winRateByInst[instId].wins += 1;
        }
        if (trade.evaluation?.outcome === 'loss') {
            summary.winRateByInst[instId].losses += 1;
        }
        const bucket = summary.winRateByInst[instId];
        bucket.winRate =
            bucket.wins + bucket.losses > 0
                ? bucket.wins / (bucket.wins + bucket.losses)
                : 0;
    });

    const equityCurve = [];
    let cumulative = 0;
    closedTrades
        .sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime())
        .forEach((trade) => {
            const rMultiple = Number(trade.evaluation?.rMultiple);
            if (!Number.isFinite(rMultiple)) {
                return;
            }
            cumulative += rMultiple;
            equityCurve.push({
                timestamp: trade.timestamp,
                rMultiple,
                cumulativeR: cumulative
            });
        });
    summary.equityCurve = equityCurve.slice(-100);

    const sample = evaluated.slice(-Math.min(10, evaluated.length));
    console.log(JSON.stringify({ summary, sample }, null, 2));
};

const showPositions = async () => {
    const positions = await blofinClient.fetchPositions();
    console.log(JSON.stringify(positions, null, 2));
};

const showBalance = async () => {
    const balance = await blofinClient.fetchAccountBalance();
    console.log(JSON.stringify(balance, null, 2));
};

const placeOrder = async (options) => {
    if (!config.markets.blofin.allowTrading) {
        throw new Error('Trading disabled. Set BLOFIN_ALLOW_TRADING=true.');
    }
    if (config.markets.blofin.dryRun) {
        throw new Error('BLOFIN_DRY_RUN=true. Disable to place orders.');
    }
    if (!options.flags.has('confirm')) {
        throw new Error('Order requires --confirm.');
    }

    const instId = options.inst;
    const side = options.side;
    const orderType = options.type || 'market';
    const size = Number(options.size);
    const price = options.price ? Number(options.price) : undefined;

    if (!instId) {
        throw new Error('Missing --inst.');
    }
    if (!['buy', 'sell'].includes(side)) {
        throw new Error('Side must be buy or sell.');
    }
    if (!['market', 'limit'].includes(orderType)) {
        throw new Error('Type must be market or limit.');
    }
    if (!Number.isFinite(size) || size <= 0) {
        throw new Error('Size must be a positive number.');
    }
    if (orderType === 'limit' && (!Number.isFinite(price) || price <= 0)) {
        throw new Error('Limit orders require --price.');
    }
    if (size > config.markets.blofin.maxOrderUsdt) {
        throw new Error(
            `Size exceeds max order size (${config.markets.blofin.maxOrderUsdt}).`
        );
    }

    if (config.markets.blofin.leverage) {
        await blofinClient.setLeverage({
            instId,
            leverage: config.markets.blofin.leverage,
            marginMode: config.markets.blofin.marginMode
        });
    }

    const result = await blofinClient.placeOrder({
        instId,
        side,
        orderType,
        size,
        price,
        marginMode: config.markets.blofin.marginMode,
        positionSide:
            config.markets.blofin.positionMode === 'long_short_mode'
                ? side === 'buy'
                    ? 'long'
                    : 'short'
                : undefined
    });
    console.log(JSON.stringify(result, null, 2));
};

const main = async () => {
    const { options, rest } = parseArgs(process.argv.slice(2));
    const command = rest[0];

    if (!command || command === '--help' || command === 'help') {
        console.log(helpText);
        return;
    }

    if (command === 'scan') {
        await scanSignals(options);
        return;
    }
    if (command === 'auto') {
        await autoTradeOnce(options);
        return;
    }
    if (command === 'report') {
        await reportAutoTrades(options);
        return;
    }
    if (command === 'positions') {
        await showPositions();
        return;
    }
    if (command === 'balance') {
        await showBalance();
        return;
    }
    if (command === 'order') {
        await placeOrder(options);
        return;
    }

    console.log(helpText);
};

main().catch((error) => {
    console.error('Blofin CLI error:', error.message);
    process.exitCode = 1;
});
