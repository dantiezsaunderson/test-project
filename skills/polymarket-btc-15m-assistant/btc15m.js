#!/usr/bin/env node

const { execSync, spawn } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const repoUrl = 'https://github.com/FrondEnt/PolymarketBTC15mAssistant.git';
const vendorDir = path.resolve(__dirname, 'vendor');
const installDir = path.resolve(vendorDir, 'PolymarketBTC15mAssistant');

const helpText = `
Polymarket BTC 15m Assistant (wrapper)

Usage:
  btc15m.js status
  btc15m.js install
  btc15m.js start

Notes:
  - "start" runs a long-lived console app (Ctrl+C to stop).
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

const install = () => {
    ensureDir(vendorDir);
    if (!isInstalled()) {
        run('git', ['clone', repoUrl, installDir]);
    } else {
        run('git', ['-C', installDir, 'pull', '--ff-only']);
    }
    run('npm', ['install'], { cwd: installDir });
    console.log('✅ Polymarket BTC 15m Assistant installed.');
};

const start = () => {
    if (!isInstalled()) {
        console.log('Not installed yet. Run: node btc15m.js install');
        return;
    }
    const child = spawn('npm', ['start'], {
        cwd: installDir,
        stdio: 'inherit'
    });
    child.on('exit', (code) => {
        process.exitCode = code ?? 0;
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

    console.log(helpText);
};

main();
