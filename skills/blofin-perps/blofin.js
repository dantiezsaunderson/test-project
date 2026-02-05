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
  blofin.js report --days 7
  blofin.js positions
  blofin.js balance
  blofin.js order --inst BTC-USDT --side buy --type market --size 1 --confirm

Options:
  --limit <number>
  --days <number>
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
    if (entry.signal?.takeProfit) {
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

    const summary = {
        since: new Date(sinceMs).toISOString(),
        total: filtered.length,
        dryRun: filtered.filter((trade) => trade.status === 'dry-run').length,
        submitted: filtered.filter((trade) => trade.status !== 'dry-run').length,
        byInst: {},
        bySide: {}
    };

    filtered.forEach((trade) => {
        const instId = trade.instId || 'unknown';
        const side = trade.side || 'unknown';
        summary.byInst[instId] = (summary.byInst[instId] || 0) + 1;
        summary.bySide[side] = (summary.bySide[side] || 0) + 1;
    });

    const sample = filtered.slice(-Math.min(10, filtered.length));
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
