#!/usr/bin/env node

const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../../.env') });

const blofinClient = require('../../blofinClient');
const config = require('../../config');
const { buildIccSignal } = require('../../blofinStrategy');

const helpText = `
ICC Backtest Runner

Usage:
  backtest.js --inst BTC-USDT --entry 5m --high 1H --entry-limit 1000 --high-limit 500

Options:
  --inst <instId>
  --entry <timeframe>     (default: 5m)
  --high <timeframe>      (default: 1H)
  --entry-limit <number>  (default: 1000)
  --high-limit <number>   (default: 500)
  --risk-pct <number>     (default: 0.01)
  --initial <number>      (default: 10000)
  --fee-bps <number>      (default: 0)
  --slippage-bps <number> (default: 0)
  --corr-threshold <num>  (override correction threshold)
  --swing-pivot <num>     (override swing pivot)
  --entry-pivot <num>     (override entry pivot)
  --structure-lookback <num>
  --structure-swings <num>
  --min-displacement <num>
  --min-swing-pct <num>
  --debug                 (include signal stage counts)
`.trim();

const parseArgs = (args) => {
    const options = {};
    const rest = [];
    for (let i = 0; i < args.length; i += 1) {
        const arg = args[i];
        if (arg.startsWith('--')) {
            const key = arg.replace(/^--/, '');
            if (key === 'debug') {
                options[key] = true;
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

const applySlippage = (price, side, slippageBps) => {
    if (!Number.isFinite(price) || !(slippageBps > 0)) {
        return price;
    }
    const slippage = price * (slippageBps / 10000);
    return side === 'buy' ? price + slippage : price - slippage;
};

const evaluatePartial = ({
    entryPrice,
    exitPrice,
    side,
    size,
    feeBps
}) => {
    const pnl = (side === 'buy' ? exitPrice - entryPrice : entryPrice - exitPrice) * size;
    if (!(feeBps > 0)) {
        return pnl;
    }
    const notional = size * entryPrice;
    const fee = notional * (feeBps / 10000) * 2;
    return pnl - fee;
};

const runBacktest = async ({
    instId,
    entryTf,
    highTf,
    entryLimit,
    highLimit,
    riskPct,
    initialEquity,
    feeBps,
    slippageBps,
    strategyOverride,
    debug
}) => {
    const [entryCandlesRaw, highCandlesRaw] = await Promise.all([
        blofinClient.fetchCandles({
            instId,
            bar: entryTf,
            limit: entryLimit
        }),
        blofinClient.fetchCandles({
            instId,
            bar: highTf,
            limit: highLimit
        })
    ]);

    const entryCandles = [...entryCandlesRaw].sort((a, b) => a.ts - b.ts);
    const highCandles = [...highCandlesRaw].sort((a, b) => a.ts - b.ts);

    const strategy = Object.entries({
        ...config.markets.blofin.strategy,
        ...strategyOverride
    }).reduce((acc, [key, value]) => {
        if (value !== undefined) {
            acc[key] = value;
        }
        return acc;
    }, {});
    let highIndex = 0;
    let equity = initialEquity;
    let peakEquity = initialEquity;
    let maxDrawdown = 0;
    const trades = [];
    const equityCurve = [];
    const statusCounts = {};

    let openTrade = null;

    for (let i = 0; i < entryCandles.length; i += 1) {
        const candle = entryCandles[i];
        while (
            highIndex + 1 < highCandles.length &&
            highCandles[highIndex + 1].ts <= candle.ts
        ) {
            highIndex += 1;
        }
        if (highIndex + 1 < strategy.minCandles) {
            continue;
        }
        if (i + 1 < strategy.entryMinCandles) {
            continue;
        }

        if (openTrade) {
            const { side, stopLoss, targets, splits, sizeUnits, entryPrice } = openTrade;
            const stopHit = side === 'buy' ? candle.low <= stopLoss : candle.high >= stopLoss;
            const targetHit = targets.some((target) =>
                side === 'buy' ? candle.high >= target.level : candle.low <= target.level
            );

            if (stopHit) {
                const exitPrice = applySlippage(stopLoss, side, slippageBps);
                const pnl = evaluatePartial({
                    entryPrice: openTrade.entryPriceAdj,
                    exitPrice,
                    side,
                    size: sizeUnits * openTrade.remaining,
                    feeBps
                });
                openTrade.realizedPnl += pnl;
                openTrade.remaining = 0;
                openTrade.exitReason = targetHit ? 'stop_and_target_same_candle' : 'stop_hit';
            } else {
                for (const target of targets) {
                    if (target.hit) {
                        continue;
                    }
                    const hit = side === 'buy' ? candle.high >= target.level : candle.low <= target.level;
                    if (!hit) {
                        continue;
                    }
                    target.hit = true;
                    const exitPrice = applySlippage(target.level, side, slippageBps);
                    const portion = Math.min(target.split, openTrade.remaining);
                    const pnl = evaluatePartial({
                        entryPrice: openTrade.entryPriceAdj,
                        exitPrice,
                        side,
                        size: sizeUnits * portion,
                        feeBps
                    });
                    openTrade.realizedPnl += pnl;
                    openTrade.remaining -= portion;
                    openTrade.partials.push({
                        level: target.level,
                        split: portion,
                        ts: candle.ts
                    });
                }

                if (openTrade.remaining <= 0) {
                    openTrade.exitReason = 'all_targets_hit';
                }
            }

            if (openTrade.remaining <= 0) {
                const rMultiple = openTrade.realizedPnl / openTrade.riskUsd;
                equity += openTrade.realizedPnl;
                peakEquity = Math.max(peakEquity, equity);
                maxDrawdown = Math.min(maxDrawdown, (equity - peakEquity) / peakEquity);
                trades.push({
                    instId,
                    side,
                    entryTime: openTrade.entryTime,
                    exitTime: candle.ts,
                    entryPrice: openTrade.entryPriceAdj,
                    stopLoss,
                    targets: targets.map((target) => target.level),
                    pnl: openTrade.realizedPnl,
                    rMultiple,
                    exitReason: openTrade.exitReason,
                    partials: openTrade.partials
                });
                equityCurve.push({ ts: candle.ts, equity });
                openTrade = null;
            }
            continue;
        }

        const highSlice = highCandles.slice(0, highIndex + 1);
        const entrySlice = entryCandles.slice(0, i + 1);
        const signal = buildIccSignal(highSlice, entrySlice, strategy);
        if (signal && debug) {
            const key = signal.status || 'UNKNOWN';
            statusCounts[key] = (statusCounts[key] || 0) + 1;
        }
        if (!signal || !['BUY', 'SELL'].includes(signal.status)) {
            continue;
        }

        const entryPrice = candle.close;
        const side = signal.status === 'BUY' ? 'buy' : 'sell';
        const stopLoss = signal.stopLoss;
        const rawTargets = Array.isArray(signal.takeProfitLevels)
            ? signal.takeProfitLevels
            : Number.isFinite(signal.takeProfit)
                ? [signal.takeProfit]
                : [];
        const targets = rawTargets
            .map((level) => Number(level))
            .filter((level) => Number.isFinite(level))
            .filter((level) => (side === 'buy' ? level > entryPrice : level < entryPrice))
            .sort((a, b) => (side === 'buy' ? a - b : b - a));
        if (!targets.length || !Number.isFinite(stopLoss)) {
            continue;
        }

        const entryPriceAdj = applySlippage(entryPrice, side, slippageBps);
        const riskDistance = Math.abs(entryPriceAdj - stopLoss);
        if (!(riskDistance > 0)) {
            continue;
        }

        const riskUsd = equity * riskPct;
        const sizeUnits = riskUsd / riskDistance;
        const splits = normalizeSplits(signal.takeProfitSplits, targets.length);

        openTrade = {
            side,
            entryTime: candle.ts,
            entryPriceAdj,
            stopLoss,
            targets: targets.map((level, idx) => ({
                level,
                split: splits[idx],
                hit: false
            })),
            splits,
            sizeUnits,
            riskUsd,
            remaining: 1,
            realizedPnl: 0,
            exitReason: 'open',
            partials: []
        };
    }

    const closedTrades = trades.length;
    const wins = trades.filter((trade) => trade.pnl > 0).length;
    const losses = trades.filter((trade) => trade.pnl < 0).length;
    const profitFactor =
        trades
            .filter((trade) => trade.pnl > 0)
            .reduce((acc, trade) => acc + trade.pnl, 0) /
        Math.abs(
            trades
                .filter((trade) => trade.pnl < 0)
                .reduce((acc, trade) => acc + trade.pnl, 0) || 1
        );

    return {
        summary: {
            instId,
            entryTf,
            highTf,
            entryLimit,
            highLimit,
            trades: closedTrades,
            wins,
            losses,
            winRate: closedTrades ? wins / closedTrades : 0,
            endingEquity: equity,
            returnPct: initialEquity > 0 ? (equity - initialEquity) / initialEquity : 0,
            maxDrawdown: maxDrawdown,
            profitFactor: Number.isFinite(profitFactor) ? profitFactor : 0
        },
        trades: trades.slice(-20),
        equityCurve: equityCurve.slice(-100),
        signalStats: debug ? statusCounts : undefined
    };
};

const main = async () => {
    const { options } = parseArgs(process.argv.slice(2));
    const instId = options.inst;
    if (!instId) {
        console.log(helpText);
        return;
    }
    const result = await runBacktest({
        instId,
        entryTf: options.entry || '5m',
        highTf: options.high || '1H',
        entryLimit: Number(options['entry-limit'] || 1000),
        highLimit: Number(options['high-limit'] || 500),
        riskPct: Number(options['risk-pct'] || 0.01),
        initialEquity: Number(options.initial || 10000),
        feeBps: Number(options['fee-bps'] || 0),
        slippageBps: Number(options['slippage-bps'] || 0),
        strategyOverride: {
            correctionThreshold: options['corr-threshold']
                ? Number(options['corr-threshold'])
                : undefined,
            swingPivot: options['swing-pivot']
                ? Number(options['swing-pivot'])
                : undefined,
            entryPivot: options['entry-pivot']
                ? Number(options['entry-pivot'])
                : undefined,
            structureLookback: options['structure-lookback']
                ? Number(options['structure-lookback'])
                : undefined,
            structureSwingCount: options['structure-swings']
                ? Number(options['structure-swings'])
                : undefined,
            minDisplacementPct: options['min-displacement']
                ? Number(options['min-displacement'])
                : undefined,
            minSwingPct: options['min-swing-pct']
                ? Number(options['min-swing-pct'])
                : undefined
        },
        debug: options.debug === true || options.debug === 'true' || options.debug === '1'
    });
    console.log(JSON.stringify(result, null, 2));
};

main().catch((error) => {
    console.error('ICC backtest error:', error.message);
    process.exitCode = 1;
});
