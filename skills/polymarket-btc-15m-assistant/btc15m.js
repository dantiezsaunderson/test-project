#!/usr/bin/env node

const { execSync, spawn } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const repoUrl = 'https://github.com/FrondEnt/PolymarketBTC15mAssistant.git';
const vendorDir = path.resolve(__dirname, 'vendor');
const installDir = path.resolve(vendorDir, 'PolymarketBTC15mAssistant');
const overrideDir = path.resolve(__dirname, 'overrides');
const binanceOverride = path.resolve(overrideDir, 'binance.js');
const binanceTarget = path.resolve(installDir, 'src', 'data', 'binance.js');
const binanceWsOverride = path.resolve(overrideDir, 'binanceWs.js');
const binanceWsTarget = path.resolve(installDir, 'src', 'data', 'binanceWs.js');

const helpText = `
Polymarket BTC 15m Assistant (wrapper)

Usage:
  btc15m.js status
  btc15m.js install
  btc15m.js start
  btc15m.js snapshot --seconds 8

Notes:
  - "start" runs a long-lived console app (Ctrl+C to stop).
  - "snapshot" runs briefly and prints the last screen.
  - Install will clone/update the upstream repo and run npm install.
`.trim();

const run = (command, args, options = {}) =>
    execSync([command, ...args].join(' '), {
        stdio: 'inherit',
        ...options
    });

const isInstalled = () =>
    fs.existsSync(installDir) && fs.existsSync(path.join(installDir, 'package.json'));

const ensureDir = (dir) => {
    fs.mkdirSync(dir, { recursive: true });
};

const applyOverrides = () => {
    if (!fs.existsSync(binanceOverride)) {
        return;
    }
    if (!fs.existsSync(binanceTarget)) {
        return;
    }
    fs.copyFileSync(binanceOverride, binanceTarget);
    if (fs.existsSync(binanceWsOverride) && fs.existsSync(binanceWsTarget)) {
        fs.copyFileSync(binanceWsOverride, binanceWsTarget);
    }
};

const install = () => {
    ensureDir(vendorDir);
    if (!isInstalled()) {
        run('git', ['clone', repoUrl, installDir]);
    } else {
        run('git', ['-C', installDir, 'pull', '--ff-only']);
    }
    run('npm', ['install'], { cwd: installDir });
    applyOverrides();
    console.log('✅ Polymarket BTC 15m Assistant installed.');
};

const start = () => {
    if (!isInstalled()) {
        console.log('Not installed yet. Run: node btc15m.js install');
        return;
    }
    applyOverrides();
    const child = spawn('npm', ['start'], {
        cwd: installDir,
        stdio: 'inherit'
    });
    child.on('exit', (code) => {
        process.exitCode = code ?? 0;
    });
};

const stripAnsi = (value) => String(value).replace(/\x1b\[[0-9;]*m/g, '');

const extractSnapshot = (output) => {
    const lines = stripAnsi(output)
        .split(/\r?\n/)
        .map((line) => line.replace(/\s+$/g, ''));
    if (!lines.length) {
        return 'No output captured.';
    }
    const lastMarketIndex = [...lines].reverse().findIndex((line) =>
        /Market:/.test(line)
    );
    const marketIndex =
        lastMarketIndex === -1 ? -1 : lines.length - 1 - lastMarketIndex;
    let start = marketIndex > -1 ? Math.max(0, marketIndex - 1) : Math.max(0, lines.length - 30);
    let end = lines.length;
    for (let i = marketIndex; i < lines.length; i += 1) {
        if (lines[i] && lines[i].toLowerCase().includes('created by')) {
            end = i + 1;
            break;
        }
    }
    const snapshot = lines.slice(start, end).filter((line) => line.trim() !== '');
    return snapshot.length ? snapshot.join('\n') : 'No snapshot lines found.';
};

const snapshot = (seconds = 8) => {
    if (!isInstalled()) {
        console.log('Not installed yet. Run: node btc15m.js install');
        return;
    }
    applyOverrides();
    const durationMs = Math.max(2, Number(seconds) || 8) * 1000;
    const child = spawn('node', ['src/index.js'], {
        cwd: installDir,
        stdio: ['ignore', 'pipe', 'pipe']
    });
    let output = '';
    child.stdout.on('data', (chunk) => {
        output += chunk.toString();
    });
    child.stderr.on('data', (chunk) => {
        output += chunk.toString();
    });
    const timer = setTimeout(() => {
        child.kill('SIGINT');
    }, durationMs);
    child.on('close', () => {
        clearTimeout(timer);
        console.log('--- Snapshot ---');
        console.log(extractSnapshot(output));
    });
};

const status = () => {
    if (!isInstalled()) {
        console.log('Status: not installed');
        console.log(`Install with: node ${path.basename(__filename)} install`);
        return;
    }
    console.log('Status: installed');
    console.log(`Location: ${installDir}`);
};

const main = () => {
    const command = process.argv[2];
    if (!command || command === '--help' || command === 'help') {
        console.log(helpText);
        return;
    }

    if (command === 'install') {
        install();
        return;
    }
    if (command === 'start') {
        start();
        return;
    }
    if (command === 'status') {
        status();
        return;
    }
    if (command === 'snapshot') {
        const argIndex = process.argv.indexOf('--seconds');
        const seconds =
            argIndex > -1 ? Number(process.argv[argIndex + 1]) : undefined;
        snapshot(seconds);
        return;
    }

    console.log(helpText);
};

main();
