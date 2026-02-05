#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { spawn, spawnSync } = require('child_process');

require('dotenv').config({ path: path.resolve(__dirname, '../../.env') });

const repoRoot = path.resolve(__dirname, '../..');
const serverPath = path.resolve(repoRoot, 'server.js');
const pidPath = path.resolve(repoRoot, '.forward-test.pid');
const logPath = path.resolve(repoRoot, '.forward-test.log');

const helpText = `
Forward Test Runner

Usage:
  forward-test.js start
  forward-test.js stop
  forward-test.js status
  forward-test.js report --days 7
`.trim();

const readPid = () => {
    if (!fs.existsSync(pidPath)) {
        return null;
    }
    const raw = fs.readFileSync(pidPath, 'utf8').trim();
    const pid = Number(raw);
    return Number.isFinite(pid) ? pid : null;
};

const isAlive = (pid) => {
    if (!pid) {
        return false;
    }
    try {
        process.kill(pid, 0);
        return true;
    } catch {
        return false;
    }
};

const start = () => {
    const existing = readPid();
    if (existing && isAlive(existing)) {
        console.log(`Forward test already running (pid ${existing}).`);
        return;
    }

    const out = fs.openSync(logPath, 'a');
    const err = fs.openSync(logPath, 'a');
    const child = spawn(process.execPath, [serverPath], {
        cwd: repoRoot,
        detached: true,
        stdio: ['ignore', out, err]
    });
    child.unref();
    fs.writeFileSync(pidPath, String(child.pid));
    console.log(`Forward test started (pid ${child.pid}).`);
    console.log(`Logs: ${logPath}`);
};

const stop = () => {
    const pid = readPid();
    if (!pid) {
        console.log('Forward test is not running.');
        return;
    }
    if (isAlive(pid)) {
        process.kill(pid);
        console.log(`Stopped forward test (pid ${pid}).`);
    } else {
        console.log(`Forward test pid ${pid} not running.`);
    }
    fs.unlinkSync(pidPath);
};

const status = () => {
    const pid = readPid();
    if (pid && isAlive(pid)) {
        console.log(`Forward test running (pid ${pid}).`);
        console.log(`Logs: ${logPath}`);
        return;
    }
    console.log('Forward test not running.');
};

const report = (days) => {
    const safeDays = Number.isFinite(days) ? days : 7;
    const args = [
        path.resolve(repoRoot, 'skills/blofin-perps/blofin.js'),
        'report',
        '--days',
        String(safeDays),
        '--perf'
    ];
    const result = spawnSync(process.execPath, args, {
        cwd: repoRoot,
        stdio: 'inherit'
    });
    if (result.error) {
        console.error('Report error:', result.error.message);
    }
};

const main = () => {
    const [command, ...rest] = process.argv.slice(2);
    if (!command || command === 'help' || command === '--help') {
        console.log(helpText);
        return;
    }
    if (command === 'start') {
        start();
        return;
    }
    if (command === 'stop') {
        stop();
        return;
    }
    if (command === 'status') {
        status();
        return;
    }
    if (command === 'report') {
        const daysIndex = rest.indexOf('--days');
        const daysValue =
            daysIndex >= 0 ? Number(rest[daysIndex + 1]) : Number(rest[0]);
        report(daysValue);
        return;
    }
    console.log(helpText);
};

main();
