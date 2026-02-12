require('dotenv').config();

const express = require('express');
const path = require('path');
const config = require('./config');
const dataStore = require('./dataStore');
const { runBot } = require('./bot');

const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname)));

const requireApiKey = (req, res, next) => {
    if (!config.server.apiKey) {
        return next();
    }
    const apiKey = req.headers['x-api-key'];
    if (apiKey && apiKey === config.server.apiKey) {
        return next();
    }
    return res.status(401).json({ error: 'Unauthorized' });
};

app.get('/health', (req, res) => {
    res.json({ status: 'ok' });
});

app.get('/api/status', async (req, res) => {
    const status = await dataStore.getStatus();
    res.json({
        ...status,
        scheduler: {
            intervalMinutes: config.scheduler.intervalMinutes,
            disabled: config.scheduler.disabled
        },
        markets: {
            crypto: config.markets.crypto.enabled,
            forex: config.markets.forex.enabled,
            collectibles: config.markets.collectibles.enabled,
            meme: config.markets.meme.enabled,
            polymarket: config.markets.polymarket.enabled,
            blofin: config.markets.blofin.enabled
        }
    });
});

app.get('/api/signals', async (req, res) => {
    const limit = Number(req.query.limit || 20);
    const signals = await dataStore.getSignals(limit);
    res.json({ signals });
});

app.get('/api/snapshots/:market', async (req, res) => {
    const snapshot = await dataStore.getLatestSnapshot(req.params.market);
    if (!snapshot) {
        return res.status(404).json({ error: 'No snapshot found.' });
    }
    return res.json(snapshot);
});

app.post('/api/run', requireApiKey, async (req, res) => {
    const result = await runBot({ reason: 'manual' });
    res.json(result);
});

const startScheduler = () => {
    if (config.scheduler.disabled) {
        return;
    }
    const intervalMs = config.scheduler.intervalMinutes * 60 * 1000;
    if (!Number.isFinite(intervalMs) || intervalMs <= 0) {
        return;
    }
    setInterval(() => {
        runBot({ reason: 'scheduled' });
    }, intervalMs);
};

const runOnce = process.argv.includes('--run-once');
if (runOnce) {
    runBot({ reason: 'run-once' })
        .then(() => process.exit(0))
        .catch(() => process.exit(1));
} else {
    app.listen(config.server.port, () => {
        console.log(`Clawd bot server running on ${config.server.port}.`);
    });
    startScheduler();
    runBot({ reason: 'startup' });
}
