#!/usr/bin/env node

const DEFAULT_BASE_URL = 'http://localhost:3000';
const baseUrl = process.env.CLAWD_BOT_URL || DEFAULT_BASE_URL;
const apiKey =
    process.env.CLAWD_BOT_API_KEY || process.env.BOT_API_KEY || '';

const headers = apiKey ? { 'x-api-key': apiKey } : {};

const helpText = `
Clawd Bot CLI

Usage:
  clawd-bot.js status
  clawd-bot.js signals --limit 10
  clawd-bot.js snapshot <market>
  clawd-bot.js run

Environment:
  CLAWD_BOT_URL=http://localhost:3000
  CLAWD_BOT_API_KEY=your-key
`;

const parseArgs = (args) => {
    const options = {};
    const rest = [];
    for (let i = 0; i < args.length; i += 1) {
        const arg = args[i];
        if (arg === '--limit') {
            options.limit = Number(args[i + 1]);
            i += 1;
        } else {
            rest.push(arg);
        }
    }
    return { options, rest };
};

const requestJson = async (path, options = {}) => {
    const response = await fetch(`${baseUrl}${path}`, {
        headers: { ...headers, ...(options.headers || {}) },
        method: options.method || 'GET'
    });

    if (!response.ok) {
        const text = await response.text();
        throw new Error(
            `Request failed: ${response.status} ${response.statusText} ${text}`
        );
    }
    return response.json();
};

const formatDate = (value) => {
    if (!value) {
        return 'N/A';
    }
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? value : date.toLocaleString();
};

const renderStatus = (status) => {
    console.log(`Status: ${status.lastRun ? 'online' : 'idle'}`);
    console.log(`Last run: ${formatDate(status.lastRun && status.lastRun.at)}`);
    console.log(`Signals stored: ${status.signalCount ?? 0}`);
    if (status.snapshotCounts) {
        console.log('Snapshots:');
        Object.entries(status.snapshotCounts).forEach(([market, count]) => {
            console.log(`- ${market}: ${count}`);
        });
    }
};

const renderSignals = (signals) => {
    if (!signals.length) {
        console.log('No signals returned.');
        return;
    }
    signals.forEach((signal) => {
        console.log(
            `[${signal.market}] ${formatDate(signal.timestamp)} - ${signal.message}`
        );
    });
};

const renderSnapshot = (snapshot) => {
    console.log(`Market: ${snapshot.market}`);
    console.log(`Timestamp: ${formatDate(snapshot.timestamp)}`);
    console.log(JSON.stringify(snapshot.data, null, 2));
};

const main = async () => {
    const { options, rest } = parseArgs(process.argv.slice(2));
    const command = rest[0];

    if (!command || command === 'help' || command === '--help') {
        console.log(helpText.trim());
        return;
    }

    if (command === 'status') {
        const status = await requestJson('/api/status');
        renderStatus(status);
        return;
    }

    if (command === 'signals') {
        const limit = Number.isFinite(options.limit) ? options.limit : 10;
        const payload = await requestJson(`/api/signals?limit=${limit}`);
        renderSignals(payload.signals || []);
        return;
    }

    if (command === 'snapshot') {
        const market = rest[1];
        if (!market) {
            throw new Error('Snapshot requires a market name.');
        }
        const snapshot = await requestJson(`/api/snapshots/${market}`);
        renderSnapshot(snapshot);
        return;
    }

    if (command === 'run') {
        const result = await requestJson('/api/run', { method: 'POST' });
        console.log(`Run status: ${result.status}`);
        console.log(JSON.stringify(result.summary, null, 2));
        return;
    }

    console.log(helpText.trim());
};

main().catch((error) => {
    console.error('Clawd bot CLI error:', error.message);
    process.exitCode = 1;
});
