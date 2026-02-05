const fs = require('fs/promises');
const config = require('./config');

const defaultState = {
    lastRun: null,
    snapshots: {},
    signals: [],
    autoTrades: []
};

let stateCache = null;
let writeQueue = Promise.resolve();

const ensureStateShape = (state) => {
    if (!state.snapshots) {
        state.snapshots = {};
    }
    if (!Array.isArray(state.signals)) {
        state.signals = [];
    }
    if (!Array.isArray(state.autoTrades)) {
        state.autoTrades = [];
    }
    if (!state.lastRun) {
        state.lastRun = null;
    }
    return state;
};

const loadState = async () => {
    if (stateCache) {
        return stateCache;
    }

    try {
        const fileContents = await fs.readFile(config.storage.filePath, 'utf8');
        stateCache = ensureStateShape(JSON.parse(fileContents));
    } catch (error) {
        stateCache = ensureStateShape({ ...defaultState });
        await queueWrite(stateCache);
    }

    return stateCache;
};

const queueWrite = async (state) => {
    writeQueue = writeQueue.then(() =>
        fs.writeFile(config.storage.filePath, JSON.stringify(state, null, 2))
    );
    await writeQueue;
};

const trimArray = (items, max) => {
    if (!Array.isArray(items) || items.length <= max) {
        return items;
    }
    return items.slice(items.length - max);
};

const updateState = async (mutator) => {
    const state = await loadState();
    mutator(state);
    stateCache = state;
    await queueWrite(state);
    return state;
};

const addSnapshot = async (market, snapshot) =>
    updateState((state) => {
        if (!state.snapshots[market]) {
            state.snapshots[market] = [];
        }
        state.snapshots[market].push(snapshot);
        state.snapshots[market] = trimArray(
            state.snapshots[market],
            config.storage.maxSnapshots
        );
    });

const addSignals = async (signals) =>
    updateState((state) => {
        state.signals.push(...signals);
        state.signals = trimArray(state.signals, config.storage.maxSignals);
    });

const addAutoTrade = async (trade) =>
    updateState((state) => {
        state.autoTrades.push(trade);
        state.autoTrades = trimArray(
            state.autoTrades,
            config.storage.maxAutoTrades
        );
    });

const setLastRun = async (runSummary) =>
    updateState((state) => {
        state.lastRun = runSummary;
    });

const getLatestSnapshot = async (market) => {
    const state = await loadState();
    const snapshots = state.snapshots[market] || [];
    return snapshots[snapshots.length - 1] || null;
};

const getSignals = async (limit) => {
    const state = await loadState();
    if (!limit) {
        return state.signals;
    }
    return state.signals.slice(Math.max(state.signals.length - limit, 0));
};

const getAutoTrades = async (limit) => {
    const state = await loadState();
    if (!limit) {
        return state.autoTrades;
    }
    return state.autoTrades.slice(
        Math.max(state.autoTrades.length - limit, 0)
    );
};

const getLastAutoTradeForInstrument = async (instId) => {
    const state = await loadState();
    const reversed = [...state.autoTrades].reverse();
    return (
        reversed.find((trade) => trade && trade.instId === instId) || null
    );
};

const getStatus = async () => {
    const state = await loadState();
    const snapshotCounts = Object.keys(state.snapshots).reduce((acc, market) => {
        acc[market] = state.snapshots[market].length;
        return acc;
    }, {});

    return {
        lastRun: state.lastRun,
        signalCount: state.signals.length,
        autoTradeCount: state.autoTrades.length,
        snapshotCounts
    };
};

module.exports = {
    addSnapshot,
    addSignals,
    addAutoTrade,
    setLastRun,
    getLatestSnapshot,
    getSignals,
    getAutoTrades,
    getLastAutoTradeForInstrument,
    getStatus
};
