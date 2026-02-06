#!/usr/bin/env node

const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../../.env') });

const blofinClient = require('../../blofinClient');
const config = require('../../config');
const { buildFabiaSignal } = require('../../fabiaStrategy');

const helpText = `
Fabia Scalping Model (AMT + Order Flow proxy)

Usage:
  fabia.js signal --inst BTC-USDT --tf 5m --limit 240
  fabia.js profile --inst BTC-USDT --tf 5m --limit 240

Options:
  --inst <instId>
  --tf <timeframe> (default: 5m)
  --limit <number> (default: 240)
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

const runSignal = async (options) => {
    const instId = options.inst;
    if (!instId) {
        throw new Error('Missing --inst.');
    }
    const bar = options.tf || '5m';
    const limit = Number(options.limit || 240);
    const candles = await blofinClient.fetchCandles({ instId, bar, limit });
    const signal = buildFabiaSignal(candles, config.markets.blofin.fabia);
    console.log(JSON.stringify(signal, null, 2));
};

const runProfile = async (options) => {
    const instId = options.inst;
    if (!instId) {
        throw new Error('Missing --inst.');
    }
    const bar = options.tf || '5m';
    const limit = Number(options.limit || 240);
    const candles = await blofinClient.fetchCandles({ instId, bar, limit });
    const signal = buildFabiaSignal(candles, config.markets.blofin.fabia);
    console.log(JSON.stringify(signal.profile || {}, null, 2));
};

const main = async () => {
    const { options, rest } = parseArgs(process.argv.slice(2));
    const command = rest[0];

    if (!command || command === 'help' || command === '--help') {
        console.log(helpText);
        return;
    }
    if (command === 'signal') {
        await runSignal(options);
        return;
    }
    if (command === 'profile') {
        await runProfile(options);
        return;
    }

    console.log(helpText);
};

main().catch((error) => {
    console.error('Fabia scalping error:', error.message);
    process.exitCode = 1;
});
