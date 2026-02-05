#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const DATA_PATH = path.resolve(__dirname, '../../bot-data.json');

const parseArgs = (args) => {
    const options = {};
    for (let i = 0; i < args.length; i += 1) {
        const arg = args[i];
        if (arg === '--limit') {
            options.limit = Number(args[i + 1]);
            i += 1;
        } else if (arg === '--market') {
            options.market = args[i + 1];
            i += 1;
        } else if (arg === '--summary') {
            options.summary = true;
        }
    }
    return options;
};

const formatDate = (value) => {
    if (!value) {
        return 'N/A';
    }
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? value : date.toLocaleString();
};

const normalizeMarketFilter = (value) => {
    if (!value) {
        return null;
    }
    return value
        .split(',')
        .map((market) => market.trim().toLowerCase())
        .filter(Boolean);
};

const loadSignals = () => {
    if (!fs.existsSync(DATA_PATH)) {
        throw new Error('Missing bot-data.json. Run the bot first.');
    }
    const raw = fs.readFileSync(DATA_PATH, 'utf8');
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed.signals) ? parsed.signals : [];
};

const summarizeSignals = (signals) =>
    signals.reduce((acc, signal) => {
        acc[signal.market] = (acc[signal.market] || 0) + 1;
        return acc;
    }, {});

const printSummary = (signals) => {
    const counts = summarizeSignals(signals);
    console.log('Signal counts:');
    Object.entries(counts).forEach(([market, count]) => {
        console.log(`- ${market}: ${count}`);
    });
    if (!signals.length) {
        console.log('No signals found.');
        return;
    }
    const latest = signals[signals.length - 1];
    console.log(`Latest signal: ${formatDate(latest.timestamp)}`);
};

const printSignals = (signals) => {
    signals.forEach((signal) => {
        console.log(
            `[${signal.market}] ${formatDate(signal.timestamp)} - ${signal.message}`
        );
    });
};

const main = () => {
    const options = parseArgs(process.argv.slice(2));
    const signals = loadSignals();
    const markets = normalizeMarketFilter(options.market);

    const filtered = markets
        ? signals.filter((signal) => markets.includes(signal.market))
        : signals;

    const limit = Number.isFinite(options.limit) ? options.limit : 10;
    const recent = filtered.slice(Math.max(filtered.length - limit, 0));

    printSummary(filtered);
    if (!options.summary) {
        console.log('');
        printSignals(recent);
    }
};

try {
    main();
} catch (error) {
    console.error('Market signals error:', error.message);
    process.exitCode = 1;
}
