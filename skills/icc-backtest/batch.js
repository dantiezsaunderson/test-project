#!/usr/bin/env node

const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../../.env') });

const blofinClient = require('../../blofinClient');
const config = require('../../config');
const { runBacktest } = require('./backtest');

const helpText = `
ICC Batch Backtest

Usage:
  batch.js --top 20 --entry 5m --high 1H --entry-limit 1000 --high-limit 500

Options:
  --top <number>          (default: 20)
  --min-volume <number>   (default: 0)
  --entry <timeframe>     (default: 5m)
  --high <timeframe>      (default: 1H)
  --entry-limit <number>  (default: 1000)
  --high-limit <number>   (default: 500)
  --risk-pct <number>     (default: 0.01)
  --initial <number>      (default: 10000)
  --fee-bps <number>      (default: 0)
  --slippage-bps <number> (default: 0)
  --corr-threshold <num>
  --swing-pivot <num>
  --entry-pivot <num>
  --structure-lookback <num>
  --structure-swings <num>
  --min-displacement <num>
  --min-swing-pct <num>
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

const toNumber = (value, fallback) => {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
};

const buildOverrides = (options) => ({
    correctionThreshold: options['corr-threshold']
        ? Number(options['corr-threshold'])
        : undefined,
    swingPivot: options['swing-pivot'] ? Number(options['swing-pivot']) : undefined,
    entryPivot: options['entry-pivot'] ? Number(options['entry-pivot']) : undefined,
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
});

const runBatch = async (options) => {
    const top = toNumber(options.top, 20);
    const minVolume = toNumber(options['min-volume'], 0);
    const entryTf = options.entry || '5m';
    const highTf = options.high || '1H';
    const entryLimit = toNumber(options['entry-limit'], 1000);
    const highLimit = toNumber(options['high-limit'], 500);
    const riskPct = toNumber(options['risk-pct'], 0.01);
    const initialEquity = toNumber(options.initial, 10000);
    const feeBps = toNumber(options['fee-bps'], 0);
    const slippageBps = toNumber(options['slippage-bps'], 0);
    const strategyOverride = buildOverrides(options);

    const [tickers, instruments] = await Promise.all([
        blofinClient.fetchTickers(),
        blofinClient.fetchInstruments(config.markets.blofin.instType)
    ]);
    const instrumentSet = new Set(
        instruments
            .filter((inst) => inst.instType === config.markets.blofin.instType)
            .map((inst) => inst.instId)
    );

    const ranked = tickers
        .filter((ticker) => instrumentSet.has(ticker.instId))
        .map((ticker) => ({
            instId: ticker.instId,
            volume24h: Number(ticker.volCurrency24h) || 0
        }))
        .filter((item) => item.volume24h >= minVolume)
        .sort((a, b) => b.volume24h - a.volume24h)
        .slice(0, top);

    const results = [];
    for (const item of ranked) {
        const res = await runBacktest({
            instId: item.instId,
            entryTf,
            highTf,
            entryLimit,
            highLimit,
            riskPct,
            initialEquity,
            feeBps,
            slippageBps,
            strategyOverride,
            debug: false
        });
        results.push({
            instId: item.instId,
            volume24h: item.volume24h,
            summary: res.summary
        });
    }

    return {
        generatedAt: new Date().toISOString(),
        top,
        entryTf,
        highTf,
        entryLimit,
        highLimit,
        results: results.sort((a, b) => b.summary.returnPct - a.summary.returnPct)
    };
};

const main = async () => {
    const { options } = parseArgs(process.argv.slice(2));
    if (!options.top && !options.inst) {
        console.log(helpText);
        return;
    }
    const output = await runBatch(options);
    console.log(JSON.stringify(output, null, 2));
};

main().catch((error) => {
    console.error('ICC batch backtest error:', error.message);
    process.exitCode = 1;
});
