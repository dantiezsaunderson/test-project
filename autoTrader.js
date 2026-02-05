const config = require('./config');
const blofinClient = require('./blofinClient');
const dataStore = require('./dataStore');
const { notifyAutoTrades } = require('./notifier');

const toNumber = (value, fallback = 0) => {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
};

const buildTickerMap = (tickers) => {
    const map = new Map();
    tickers.forEach((ticker) => {
        if (ticker && ticker.instId) {
            map.set(ticker.instId, ticker);
        }
    });
    return map;
};

const findInstrument = (instruments, instId) =>
    instruments.find((instrument) => instrument.instId === instId);

const normalizeInstrument = (instrument) => {
    if (!instrument) {
        return null;
    }
    const contractValue = toNumber(
        instrument.contractValue ||
            instrument.ctVal ||
            instrument.contractVal ||
            1,
        1
    );
    const minSize = toNumber(
        instrument.minSize ||
            instrument.minSz ||
            instrument.minOrder ||
            instrument.minQty ||
            0,
        0
    );
    const lotSize = toNumber(
        instrument.lotSize ||
            instrument.lotSz ||
            instrument.stepSize ||
            instrument.step ||
            minSize ||
            1,
        1
    );
    return {
        instId: instrument.instId,
        contractValue,
        minSize,
        lotSize
    };
};

const floorToStep = (value, step) => {
    if (!Number.isFinite(step) || step <= 0) {
        return value;
    }
    const precision = step.toString().split('.')[1]?.length || 0;
    const floored = Math.floor(value / step) * step;
    return Number(floored.toFixed(precision));
};

const parseWindow = (entry) => {
    if (!entry || typeof entry !== 'string') {
        return null;
    }
    const [startRaw, endRaw] = entry.split('-').map((value) => value.trim());
    if (!startRaw || !endRaw) {
        return null;
    }
    const [startH, startM] = startRaw.split(':').map(Number);
    const [endH, endM] = endRaw.split(':').map(Number);
    if (
        !Number.isFinite(startH) ||
        !Number.isFinite(startM) ||
        !Number.isFinite(endH) ||
        !Number.isFinite(endM)
    ) {
        return null;
    }
    return {
        start: startH * 60 + startM,
        end: endH * 60 + endM
    };
};

const isWithinSessions = (sessions, now) => {
    if (!Array.isArray(sessions) || sessions.length === 0) {
        return true;
    }
    const currentMinutes = now.getUTCHours() * 60 + now.getUTCMinutes();
    return sessions
        .map(parseWindow)
        .filter(Boolean)
        .some((window) => {
            if (window.start === window.end) {
                return false;
            }
            if (window.start < window.end) {
                return (
                    currentMinutes >= window.start &&
                    currentMinutes < window.end
                );
            }
            return (
                currentMinutes >= window.start ||
                currentMinutes < window.end
            );
        });
};

const extractAvailableUsdt = (balance) => {
    const candidates = [];
    if (Array.isArray(balance)) {
        candidates.push(...balance);
    }
    if (balance && Array.isArray(balance.details)) {
        candidates.push(...balance.details);
    }
    if (balance && Array.isArray(balance.assets)) {
        candidates.push(...balance.assets);
    }
    if (balance && Array.isArray(balance.data)) {
        candidates.push(...balance.data);
    }
    if (balance && Array.isArray(balance.list)) {
        candidates.push(...balance.list);
    }
    for (const entry of candidates) {
        const currency = String(
            entry.currency || entry.ccy || entry.asset || entry.coin || ''
        ).toUpperCase();
        if (currency !== 'USDT') {
            continue;
        }
        const available = toNumber(
            entry.available ||
                entry.availEq ||
                entry.availableBalance ||
                entry.cashBal ||
                entry.balance ||
                entry.equity,
            null
        );
        if (Number.isFinite(available)) {
            return available;
        }
    }
    return null;
};

const getPositionSize = (position) =>
    toNumber(
        position.pos ||
            position.position ||
            position.positions ||
            position.sz ||
            position.size ||
            position.qty ||
            0,
        0
    );

const computeOrderSize = ({ notional, price, contractValue, minSize, lotSize }) => {
    if (!Number.isFinite(notional) || !Number.isFinite(price) || price <= 0) {
        return 0;
    }
    const sizeRaw = notional / (contractValue * price);
    const sized = floorToStep(sizeRaw, lotSize);
    if (sized <= 0) {
        return 0;
    }
    if (Number.isFinite(minSize) && sized < minSize) {
        return 0;
    }
    return sized;
};

const resolvePrice = async (instId, tickerMap) => {
    const ticker = tickerMap.get(instId);
    const price = toNumber(
        ticker?.last || ticker?.lastPrice || ticker?.markPx || ticker?.markPrice,
        0
    );
    if (price > 0) {
        return price;
    }
    const mark = await blofinClient.fetchMarkPrice(instId);
    return toNumber(mark?.markPx || mark?.markPrice || mark?.price || 0, 0);
};

const runBlofinAutoTrade = async ({ signals, snapshot, reason } = {}) => {
    const settings = config.markets.blofin;
    const now = new Date();
    const actions = [];
    const skipped = [];
    const maxActions = settings.dryRun
        ? Math.max(1, settings.autoDryMaxActions)
        : 1;

    if (!settings.autoTrade) {
        return { status: 'disabled', actions };
    }
    if (settings.autoTradeKillSwitch) {
        return { status: 'blocked', reason: 'kill_switch', actions };
    }
    if (!settings.allowTrading) {
        return { status: 'blocked', reason: 'trading_disabled', actions };
    }
    if (!isWithinSessions(settings.autoTradeSessions, now)) {
        return { status: 'blocked', reason: 'out_of_session', actions };
    }

    const sourceSignals =
        signals || snapshot?.data?.signals || snapshot?.signals || [];
    const actionable = sourceSignals.filter((entry) =>
        ['BUY', 'SELL'].includes(entry?.signal?.status)
    );
    if (!actionable.length) {
        return { status: 'no_signals', actions };
    }

    const [positions, instruments, tickers, balance] = await Promise.all([
        blofinClient.fetchPositions(),
        blofinClient.fetchInstruments(settings.instType),
        blofinClient.fetchTickers(),
        blofinClient.fetchAccountBalance()
    ]);
    const openPositions = positions.filter(
        (position) => Math.abs(getPositionSize(position)) > 0
    );
    const maxOpenPositionsAllowed = settings.dryRun
        ? settings.maxOpenPositionsDry
        : settings.maxOpenPositions;
    if (
        Number.isFinite(maxOpenPositionsAllowed) &&
        openPositions.length >= maxOpenPositionsAllowed
    ) {
        return { status: 'blocked', reason: 'max_open_positions', actions };
    }

    const tickerMap = buildTickerMap(tickers);
    const availableUsdt = extractAvailableUsdt(balance);
    const baseNotional = Math.min(
        settings.riskPerTradeUsdt,
        settings.maxOrderUsdt
    );
    const notional = Number.isFinite(availableUsdt)
        ? Math.min(baseNotional, availableUsdt)
        : baseNotional;

    if (!(notional > 0)) {
        return { status: 'blocked', reason: 'no_notional', actions };
    }
    if (settings.autoOrderType !== 'market') {
        return { status: 'blocked', reason: 'order_type_not_supported', actions };
    }

    for (const entry of actionable) {
        if (actions.length >= maxActions) {
            break;
        }
        const instId = entry.instId;
        if (!instId) {
            skipped.push('missing_inst_id');
            continue;
        }
        if (openPositions.some((position) => position.instId === instId)) {
            skipped.push(`${instId}:open_position`);
            continue;
        }

        const lastTrade = await dataStore.getLastAutoTradeForInstrument(instId);
        if (lastTrade && lastTrade.timestamp) {
            const lastTime = new Date(lastTrade.timestamp).getTime();
            const cooldownMs = settings.autoTradeCooldownMinutes * 60 * 1000;
            if (Number.isFinite(lastTime) && now.getTime() - lastTime < cooldownMs) {
                skipped.push(`${instId}:cooldown`);
                continue;
            }
        }

        const instrument = normalizeInstrument(findInstrument(instruments, instId));
        if (!instrument) {
            skipped.push(`${instId}:instrument_missing`);
            continue;
        }

        const price = await resolvePrice(instId, tickerMap);
        if (!(price > 0)) {
            skipped.push(`${instId}:price_missing`);
            continue;
        }

        const size = computeOrderSize({
            notional,
            price,
            contractValue: instrument.contractValue,
            minSize: instrument.minSize,
            lotSize: instrument.lotSize
        });
        if (!(size > 0)) {
            skipped.push(`${instId}:size_too_small`);
            continue;
        }

        const side = entry.signal.status === 'BUY' ? 'buy' : 'sell';
        const action = {
            timestamp: new Date().toISOString(),
            instId,
            side,
            size,
            price,
            notional,
            status: settings.dryRun ? 'dry-run' : 'submitted',
            reason: reason || 'auto-trade',
            signal: entry.signal
        };

        if (settings.dryRun) {
            await dataStore.addAutoTrade(action);
            actions.push(action);
            break;
        }

        if (settings.leverage) {
            await blofinClient.setLeverage({
                instId,
                leverage: settings.leverage,
                marginMode: settings.marginMode
            });
        }

        const result = await blofinClient.placeOrder({
            instId,
            side,
            orderType: settings.autoOrderType,
            size,
            marginMode: settings.marginMode,
            positionSide:
                settings.positionMode === 'long_short_mode'
                    ? side === 'buy'
                        ? 'long'
                        : 'short'
                    : undefined
        });

        action.orderId = result?.orderId || result?.ordId || null;
        await dataStore.addAutoTrade(action);
        actions.push(action);
        break;
    }

    if (!actions.length) {
        return { status: 'skipped', actions, skipped };
    }
    await notifyAutoTrades(actions);
    return { status: 'executed', actions, skipped };
};

module.exports = {
    runBlofinAutoTrade
};
