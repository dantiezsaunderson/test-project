#!/usr/bin/env node

const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../../.env') });

const config = require('../../config');
const polymarketClient = require('../../polymarketClient');
const fs = require('fs');

const helpText = `
Polymarket CLI

Usage:
  polymarket.js status
  polymarket.js discover
  polymarket.js signals --limit 5
  polymarket.js balance
  polymarket.js derive --write-env
  polymarket.js trade --confirm

Options:
  --side YES|NO
  --min-liquidity <number>
  --min-volume <number>
  --candidates <number>
  --spread-top <number>
  --limit <number>
  --asset collateral|conditional
  --price <number>
  --size <number>
  --token <id>
  --buy|--sell
  --confirm
`;

const parseArgs = (args) => {
    const options = { flags: new Set() };
    const rest = [];
    for (let i = 0; i < args.length; i += 1) {
        const arg = args[i];
        if (arg.startsWith('--')) {
            const key = arg.replace(/^--/, '');
            if (['buy', 'sell', 'confirm', 'write-env'].includes(key)) {
                options.flags.add(key);
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

const buildDiscoveryOptions = (overrides = {}) => {
    const settings = config.markets.polymarket;
    return {
        gammaHost: settings.gammaHost,
        clobHost: settings.clobHost,
        chainId: settings.chainId,
        minLiquidity: Number(overrides['min-liquidity'] || settings.minLiquidity),
        minVolume: Number(overrides['min-volume'] || settings.minVolume),
        candidates: Number(overrides.candidates || settings.candidates),
        spreadCheckTop: Number(overrides['spread-top'] || settings.spreadCheckTop),
        pickSide: overrides.side || settings.pickSide
    };
};

const formatCandidate = (candidate) => ({
    id: candidate.id,
    question: candidate.question,
    pickSide: candidate.pickSide,
    tokenId: candidate.tokenId,
    spread: candidate.spread,
    liquidity: candidate.liquidity,
    volume: candidate.volume
});

const showStatus = async (options) => {
    const discovery = await polymarketClient.discoverBestMarket(
        buildDiscoveryOptions(options)
    );
    if (!discovery.best) {
        console.log('No suitable market found with current filters.');
        return;
    }
    console.log('Best execution candidate:');
    console.log(JSON.stringify(formatCandidate(discovery.best), null, 2));
};

const showDiscover = async (options) => {
    const discovery = await polymarketClient.discoverBestMarket(
        buildDiscoveryOptions(options)
    );
    const limit = Number(options.limit || config.markets.polymarket.signalTop);
    const list = discovery.evaluated.slice(0, limit).map(formatCandidate);
    console.log(JSON.stringify(list, null, 2));
};

const showSignals = async (options) => {
    const discovery = await polymarketClient.discoverBestMarket(
        buildDiscoveryOptions(options)
    );
    const limit = Number(options.limit || config.markets.polymarket.signalTop);
    const list = discovery.evaluated.slice(0, limit);
    if (!list.length) {
        console.log('No candidates returned.');
        return;
    }
    list.forEach((candidate) => {
        console.log(
            `[${candidate.pickSide}] ${candidate.question} | spread=${candidate.spread ?? 'n/a'} | liq=${candidate.liquidity} | vol=${candidate.volume}`
        );
    });
};

const deriveCredentials = async (options) => {
    const privateKey = process.env.POLYMARKET_PRIVATE_KEY || process.env.PRIVATE_KEY;
    const expectedAddress =
        process.env.POLYMARKET_EXPECTED_ADDRESS || process.env.EXPECTED_ADDRESS;

    if (!privateKey || !privateKey.startsWith('0x')) {
        throw new Error('Missing POLYMARKET_PRIVATE_KEY (0x...)');
    }
    if (!expectedAddress || !expectedAddress.startsWith('0x')) {
        throw new Error('Missing POLYMARKET_EXPECTED_ADDRESS (0x...)');
    }

    const creds = await polymarketClient.deriveApiCredentials({
        privateKey,
        expectedAddress,
        clobHost: config.markets.polymarket.clobHost,
        chainId: config.markets.polymarket.chainId
    });

    console.log('Derived Polymarket L2 credentials:');
    console.log(creds);

    if (options.flags.has('write-env')) {
        const envPath = path.resolve(__dirname, '../../.env');
        if (!fs.existsSync(envPath)) {
            throw new Error('Missing .env file at repo root.');
        }
        let env = fs.readFileSync(envPath, 'utf8');
        env = env.replace(/^POLYMARKET_API_KEY=.*$/m, `POLYMARKET_API_KEY=${creds.apiKey}`);
        env = env.replace(
            /^POLYMARKET_API_SECRET=.*$/m,
            `POLYMARKET_API_SECRET=${creds.secret}`
        );
        env = env.replace(
            /^POLYMARKET_API_PASSPHRASE=.*$/m,
            `POLYMARKET_API_PASSPHRASE=${creds.passphrase}`
        );
        fs.writeFileSync(envPath, env, 'utf8');
        console.log('Updated .env with new Polymarket credentials.');
    }
};

const showBalance = async (options) => {
    const apiKey = process.env.POLYMARKET_API_KEY;
    const apiSecret = process.env.POLYMARKET_API_SECRET;
    const apiPassphrase = process.env.POLYMARKET_API_PASSPHRASE;

    if (!apiKey || !apiSecret || !apiPassphrase) {
        throw new Error('Missing Polymarket API credentials.');
    }

    const asset = String(options.asset || 'collateral').toUpperCase();
    const assetType = asset === 'CONDITIONAL' ? 'CONDITIONAL' : 'COLLATERAL';
    const tokenId = options.token || process.env.TOKEN_ID;

    if (assetType === 'CONDITIONAL' && !tokenId) {
        throw new Error('CONDITIONAL balance requires --token or TOKEN_ID.');
    }

    const result = await polymarketClient.getBalanceAllowance({
        clobHost: config.markets.polymarket.clobHost,
        chainId: config.markets.polymarket.chainId,
        apiKey,
        apiSecret,
        apiPassphrase,
        assetType,
        tokenId
    });

    console.log(
        JSON.stringify(
            {
                assetType,
                tokenId: tokenId || null,
                balance: result.balance,
                allowance: result.allowance
            },
            null,
            2
        )
    );
};

const executeTrade = async (options) => {
    const allowTrading = config.markets.polymarket.allowTrading;
    const dryRun = config.markets.polymarket.dryRun;

    if (!allowTrading) {
        throw new Error('Trading disabled. Set POLYMARKET_ALLOW_TRADING=true.');
    }
    if (dryRun) {
        console.log('DRY_RUN=true. Set POLYMARKET_DRY_RUN=false to execute.');
        return;
    }
    if (!options.flags.has('confirm')) {
        throw new Error('Trade requires --confirm flag.');
    }

    const apiKey = process.env.POLYMARKET_API_KEY;
    const apiSecret = process.env.POLYMARKET_API_SECRET;
    const apiPassphrase = process.env.POLYMARKET_API_PASSPHRASE;

    if (!apiKey || !apiSecret || !apiPassphrase) {
        throw new Error('Missing Polymarket API credentials.');
    }

    const tokenId = options.token || process.env.TOKEN_ID;
    const side = options.flags.has('sell')
        ? 'SELL'
        : (options.side || process.env.SIDE || 'BUY').toUpperCase();
    const price = Number(options.price || process.env.PRICE || 0);
    const size = Number(options.size || process.env.SIZE_USDC || 0);
    const maxOrder = config.markets.polymarket.maxOrderUsdc;

    if (!tokenId) {
        throw new Error('Missing TOKEN_ID.');
    }
    if (!['BUY', 'SELL'].includes(side)) {
        throw new Error('SIDE must be BUY or SELL.');
    }
    if (!(price > 0 && price < 1)) {
        throw new Error('PRICE must be between 0 and 1.');
    }
    if (!(size > 0)) {
        throw new Error('SIZE_USDC must be > 0.');
    }
    if (size > maxOrder) {
        throw new Error(`SIZE_USDC exceeds MAX_ORDER_USDC (${maxOrder}).`);
    }

    const result = await polymarketClient.createOrder({
        clobHost: config.markets.polymarket.clobHost,
        chainId: config.markets.polymarket.chainId,
        apiKey,
        apiSecret,
        apiPassphrase,
        tokenId,
        side,
        price,
        size
    });

    console.log('Order result:');
    console.log(JSON.stringify(result, null, 2));
};

const main = async () => {
    const { options, rest } = parseArgs(process.argv.slice(2));
    const command = rest[0];

    if (!command || command === 'help' || command === '--help') {
        console.log(helpText.trim());
        return;
    }

    if (command === 'status') {
        await showStatus(options);
        return;
    }

    if (command === 'discover') {
        await showDiscover(options);
        return;
    }

    if (command === 'signals') {
        await showSignals(options);
        return;
    }

    if (command === 'balance') {
        await showBalance(options);
        return;
    }

    if (command === 'derive') {
        await deriveCredentials(options);
        return;
    }

    if (command === 'trade') {
        await executeTrade(options);
        return;
    }

    console.log(helpText.trim());
};

main().catch((error) => {
    console.error('Polymarket CLI error:', error.message);
    process.exitCode = 1;
});
