#!/usr/bin/env node

const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../../.env') });

const blofinClient = require('../../blofinClient');
const { runBacktest } = require('./backtest');

const helpText = `
ICC Backtest Optimizer (BTC focus)

Usage:
  optimize.js --inst BTC-USDT --entry 5m --high 1H --entry-limit 6500 --high-limit 800

Optional grids:
  --corr-list 0.05,0.1,0.15
  --swing-pivot-list 1,2
  --entry-pivot-list 1,2
  --structure-swings-list 2,3
  --min-displacement-list 0,0.001
  --min-swing-pct-list 0,0.002

Common options:
  --risk-pct <number>     (default: 0.01)
  --initial <number>      (default: 10000)
  --fee-bps <number>      (default: 0)
  --slippage-bps <number> (default: 0)
`.trim();

const parseArgs = (args) => {
    const options = {};
    const rest = [];
    for (let i = 0; i < args.length; i += 1) {
        const arg = args[i];
        if (arg.startsWith('--')) {
            const key = arg.replace(/^--/, '');
            options[key] = args[i + 1];
            i += 1;
        } else {
            rest.push(arg);
        }
    }
    return { options, rest };
};

const parseList = (value, fallback) => {
    if (!value) {
        return fallback;
    }
    return value
        .split(',')
        .map((item) => Number(item.trim()))
        .filter((item) => Number.isFinite(item));
};

const toNumber = (value, fallback) => {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
};

const cartesian = (arrays) =>
    arrays.reduce(
        (acc, curr) =>
            acc.flatMap((combo) => curr.map((value) => [...combo, value])),
        [[]]
    );

const main = async () => {
    const { options } = parseArgs(process.argv.slice(2));
    const instId = options.inst || 'BTC-USDT';
    if (!instId) {
        console.log(helpText);
        return;
    }

    const entryTf = options.entry || '5m';
    const highTf = options.high || '1H';
    const entryLimit = toNumber(options['entry-limit'], 6500);
    const highLimit = toNumber(options['high-limit'], 800);
    const riskPct = toNumber(options['risk-pct'], 0.01);
    const initialEquity = toNumber(options.initial, 10000);
    const feeBps = toNumber(options['fee-bps'], 0);
    const slippageBps = toNumber(options['slippage-bps'], 0);

    const corrList = parseList(options['corr-list'], [0.05, 0.1, 0.15]);
    const swingPivotList = parseList(options['swing-pivot-list'], [1, 2]);
    const entryPivotList = parseList(options['entry-pivot-list'], [1, 2]);
    const structureSwingsList = parseList(options['structure-swings-list'], [2, 3]);
    const minDisplacementList = parseList(options['min-displacement-list'], [0]);
    const minSwingPctList = parseList(options['min-swing-pct-list'], [0]);

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

    const grid = cartesian([
        corrList,
        swingPivotList,
        entryPivotList,
        structureSwingsList,
        minDisplacementList,
        minSwingPctList
    ]);

    const results = [];
    for (const combo of grid) {
        const [
            correctionThreshold,
            swingPivot,
            entryPivot,
            structureSwingCount,
            minDisplacementPct,
            minSwingPct
        ] = combo;

        const res = await runBacktest({
            instId,
            entryTf,
            highTf,
            entryLimit,
            highLimit,
            riskPct,
            initialEquity,
            feeBps,
            slippageBps,
            entryCandlesRaw,
            highCandlesRaw,
            strategyOverride: {
                correctionThreshold,
                swingPivot,
                entryPivot,
                structureSwingCount,
                minDisplacementPct,
                minSwingPct
            },
            debug: false
        });
        results.push({
            params: {
                correctionThreshold,
                swingPivot,
                entryPivot,
                structureSwingCount,
                minDisplacementPct,
                minSwingPct
            },
            summary: res.summary
        });
    }

    const ranked = results
        .sort((a, b) => b.summary.returnPct - a.summary.returnPct)
        .slice(0, 10);

    console.log(
        JSON.stringify(
            {
                instId,
                entryTf,
                highTf,
                entryLimit,
                highLimit,
                totalCombos: results.length,
                best: ranked[0] || null,
                top10: ranked
            },
            null,
            2
        )
    );
};

main().catch((error) => {
    console.error('ICC optimize error:', error.message);
    process.exitCode = 1;
});
