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

const normalizeSplits = (splits, count) => {
    if (!count) {
        return [];
    }
    if (!Array.isArray(splits) || splits.length !== count) {
        return Array(count).fill(1 / count);
    }
    const total = splits.reduce((acc, value) => acc + value, 0);
    if (!(total > 0)) {
        return Array(count).fill(1 / count);
    }
    return splits.map((value) => value / total);
};

const computeRiskBasedSize = ({
    riskUsd,
    price,
    stopLoss,
    contractValue,
    minSize,
    lotSize,
    maxNotional
}) => {
    const distance = Math.abs(price - stopLoss);
    if (!(riskUsd > 0) || !(distance > 0) || !(contractValue > 0)) {
        return { size: 0, reason: 'invalid_risk_distance' };
    }
    let sizeRaw = riskUsd / (distance * contractValue);
    let size = floorToStep(sizeRaw, lotSize);
    if (!(size > 0)) {
        return { size: 0, reason: 'size_too_small' };
    }
    if (Number.isFinite(minSize) && size < minSize) {
        return { size: 0, reason: 'below_min_size' };
    }

    let notional = size * price * contractValue;
    if (Number.isFinite(maxNotional) && maxNotional > 0 && notional > maxNotional) {
        const cappedSize = floorToStep(
            maxNotional / (price * contractValue),
            lotSize
        );
        if (!(cappedSize > 0)) {
            return { size: 0, reason: 'size_too_small' };
        }
        if (Number.isFinite(minSize) && cappedSize < minSize) {
            return { size: 0, reason: 'below_min_size' };
        }
        size = cappedSize;
        notional = size * price * contractValue;
    }

    const riskUsdActual = size * distance * contractValue;
    return { size, notional, riskUsdActual };
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

const updateLossOutcomes = async ({ openPositions, tickerMap }) => {
    const positionMap = new Map(
        openPositions.map((position) => [position.instId, getPositionSize(position)])
    );
    const trades = await dataStore.getAutoTrades();
    if (!trades.length) {
        return false;
    }
    const now = new Date().toISOString();
    let updated = false;

    const resolvedTrades = await Promise.all(
        trades.map(async (trade) => {
            if (
                !trade ||
                trade.outcome ||
                trade.status !== 'submitted' ||
                !trade.instId ||
                !trade.side ||
                !Number.isFinite(trade.stopLoss)
            ) {
                return trade;
            }
            const posSize = positionMap.get(trade.instId) || 0;
            if (Math.abs(posSize) === 0) {
                return trade;
            }
            const price = await resolvePrice(trade.instId, tickerMap);
            if (!(price > 0)) {
                return trade;
            }
            const isLoss =
                trade.side === 'buy'
                    ? price <= trade.stopLoss
                    : price >= trade.stopLoss;
            if (!isLoss) {
                return trade;
            }
            updated = true;
            return {
                ...trade,
                outcome: 'loss',
                exitReason: 'stop_crossed',
                exitPrice: price,
                exitTime: now
            };
        })
    );

    if (updated) {
        await dataStore.updateAutoTrades(() => resolvedTrades);
    }
    return updated;
};

const runAutoTradeWithSettings = async ({
    signals,
    snapshot,
    reason,
    overrides,
    strategyLabel
} = {}) => {
    const baseSettings = config.markets.blofin;
    const settings = {
        ...baseSettings,
        ...(overrides || {})
    };
    const now = new Date();
    const actions = [];
    const skipped = [];
    const maxActions = settings.dryRun
        ? settings.autoDryMaxActions > 0
            ? Math.max(1, settings.autoDryMaxActions)
            : Number.POSITIVE_INFINITY
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
    if (settings.autoPauseAfterTrade) {
        const priorTrades = await dataStore.getAutoTrades();
        const hasLiveTrade = priorTrades.some(
            (trade) => trade && trade.status && trade.status !== 'dry-run'
        );
        if (hasLiveTrade) {
            return { status: 'blocked', reason: 'paused_after_trade', actions };
        }
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
        ? settings.maxOpenPositionsDry > 0
            ? settings.maxOpenPositionsDry
            : Number.POSITIVE_INFINITY
        : settings.maxOpenPositions;
    if (
        Number.isFinite(maxOpenPositionsAllowed) &&
        openPositions.length >= maxOpenPositionsAllowed
    ) {
        return { status: 'blocked', reason: 'max_open_positions', actions };
    }

    const tickerMap = buildTickerMap(tickers);

    if (settings.autoPauseAfterLoss) {
        const lossDetected = await updateLossOutcomes({
            openPositions,
            tickerMap
        });
        const existingLoss = (await dataStore.getAutoTrades()).some(
            (trade) => trade && trade.outcome === 'loss'
        );
        if (lossDetected || existingLoss) {
            return { status: 'blocked', reason: 'paused_after_loss', actions };
        }
    }

    const availableUsdt = extractAvailableUsdt(balance);
    const maxNotional = Number.isFinite(settings.maxOrderUsdt)
        ? settings.maxOrderUsdt
        : null;
    const hasRiskPct =
        Number.isFinite(settings.riskPerTradePct) &&
        settings.riskPerTradePct > 0;
    let riskUsdTarget = null;
    if (hasRiskPct && Number.isFinite(availableUsdt)) {
        riskUsdTarget = availableUsdt * settings.riskPerTradePct;
    } else if (
        Number.isFinite(settings.riskPerTradeUsdt) &&
        settings.riskPerTradeUsdt > 0
    ) {
        riskUsdTarget = settings.riskPerTradeUsdt;
    }
    if (Number.isFinite(availableUsdt) && riskUsdTarget !== null) {
        riskUsdTarget = Math.min(riskUsdTarget, availableUsdt);
    }
    const baseNotional = Number.isFinite(maxNotional)
        ? Math.min(settings.riskPerTradeUsdt, maxNotional)
        : settings.riskPerTradeUsdt;
    const fallbackNotional = Number.isFinite(availableUsdt)
        ? Math.min(baseNotional, availableUsdt)
        : baseNotional;

    if (!(fallbackNotional > 0) && !riskUsdTarget) {
        return { status: 'blocked', reason: 'no_notional', actions };
    }
    if (settings.autoOrderType !== 'market') {
        return { status: 'blocked', reason: 'order_type_not_supported', actions };
    }

    const simulatedPositions = new Set(
        openPositions.map((position) => position.instId).filter(Boolean)
    );
    for (const entry of actionable) {
        if (actions.length >= maxActions) {
            break;
        }
        if (
            Number.isFinite(maxOpenPositionsAllowed) &&
            simulatedPositions.size >= maxOpenPositionsAllowed
        ) {
            skipped.push('max_open_positions');
            break;
        }
        const instId = entry.instId;
        if (!instId) {
            skipped.push('missing_inst_id');
            continue;
        }
        if (simulatedPositions.has(instId)) {
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

        const stopLoss = toNumber(entry.signal?.stopLoss, null);
        const takeProfit = toNumber(entry.signal?.takeProfit, null);
        let size = 0;
        let notional = 0;
        let sizingMode = 'notional';
        let riskUsdActual = null;
        if (riskUsdTarget && Number.isFinite(stopLoss)) {
            const riskSizing = computeRiskBasedSize({
                riskUsd: riskUsdTarget,
                price,
                stopLoss,
                contractValue: instrument.contractValue,
                minSize: instrument.minSize,
                lotSize: instrument.lotSize,
                maxNotional
            });
            if (riskSizing.size > 0) {
                size = riskSizing.size;
                notional = riskSizing.notional;
                riskUsdActual = riskSizing.riskUsdActual;
                sizingMode = 'risk_pct';
            } else {
                skipped.push(
                    `${instId}:${riskSizing.reason || 'risk_sizing_failed'}`
                );
                continue;
            }
        } else if (riskUsdTarget && !Number.isFinite(stopLoss)) {
            skipped.push(`${instId}:missing_stop_loss`);
            continue;
        } else {
            size = computeOrderSize({
                notional: fallbackNotional,
                price,
                contractValue: instrument.contractValue,
                minSize: instrument.minSize,
                lotSize: instrument.lotSize
            });
            if (!(size > 0)) {
                skipped.push(`${instId}:size_too_small`);
                continue;
            }
            notional = size * price * instrument.contractValue;
        }

        const side = entry.signal.status === 'BUY' ? 'buy' : 'sell';
        const actionTime = new Date().toISOString();
        const tradeId = `${actionTime}-${instId}-${side}`;
        const action = {
            timestamp: actionTime,
            tradeId,
            instId,
            side,
            size,
            price,
            notional,
            strategy: strategyLabel || entry.strategy || 'icc',
            stopLoss: Number.isFinite(stopLoss) ? stopLoss : undefined,
            takeProfit: Number.isFinite(takeProfit) ? takeProfit : undefined,
            takeProfitLevels: Array.isArray(entry.signal?.takeProfitLevels)
                ? entry.signal.takeProfitLevels
                : undefined,
            takeProfitSplits: Array.isArray(entry.signal?.takeProfitSplits)
                ? entry.signal.takeProfitSplits
                : undefined,
            liquidityTargets: Array.isArray(entry.signal?.liquidityTargets)
                ? entry.signal.liquidityTargets
                : undefined,
            sizingMode,
            riskUsdTarget: riskUsdTarget || undefined,
            riskUsdActual: riskUsdActual || undefined,
            status: settings.dryRun ? 'dry-run' : 'submitted',
            reason: reason || 'auto-trade',
            signal: entry.signal
        };

        if (settings.dryRun) {
            await dataStore.addAutoTrade(action);
            actions.push(action);
            simulatedPositions.add(instId);
            continue;
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

        if (settings.autoBrackets) {
            const closeSide = side === 'buy' ? 'sell' : 'buy';
            const positionSide =
                settings.positionMode === 'long_short_mode'
                    ? side === 'buy'
                        ? 'long'
                        : 'short'
                    : undefined;
            const stop = Number.isFinite(stopLoss) ? stopLoss : null;
            const rawTargets = Array.isArray(entry.signal?.takeProfitLevels)
                ? entry.signal.takeProfitLevels
                : Number.isFinite(takeProfit)
                    ? [takeProfit]
                    : [];
            const directionTargets = rawTargets
                .map((level) => Number(level))
                .filter((level) => Number.isFinite(level))
                .filter((level) =>
                    side === 'buy' ? level > price : level < price
                )
                .sort((a, b) => (side === 'buy' ? a - b : b - a));
            const splits = normalizeSplits(
                entry.signal?.takeProfitSplits,
                directionTargets.length
            );
            const minLot = instrument.minSize || instrument.lotSize || 0;
            const tpSizes = splits.map((split) =>
                floorToStep(size * split, instrument.lotSize)
            );
            const tpOrders = [];
            if (directionTargets.length && minLot > 0) {
                for (let i = 0; i < directionTargets.length; i += 1) {
                    if (tpSizes[i] < minLot) {
                        continue;
                    }
                    const tpOrder = await blofinClient.placeTpslOrder({
                        instId,
                        marginMode: settings.marginMode,
                        positionSide,
                        side: closeSide,
                        tpTriggerPrice: directionTargets[i],
                        tpOrderPrice: -1,
                        size: tpSizes[i],
                        reduceOnly: true
                    });
                    tpOrders.push(tpOrder);
                }
            }
            let slOrder = null;
            if (Number.isFinite(stop)) {
                slOrder = await blofinClient.placeTpslOrder({
                    instId,
                    marginMode: settings.marginMode,
                    positionSide,
                    side: closeSide,
                    slTriggerPrice: stop,
                    slOrderPrice: -1,
                    size: '-1',
                    reduceOnly: true
                });
            }
            action.brackets = {
                tpLevels: directionTargets,
                tpSizes,
                sl: stop,
                tpOrders,
                slOrder
            };
        }

        await dataStore.addAutoTrade(action);
        actions.push(action);
        simulatedPositions.add(instId);
        break;
    }

    if (!actions.length) {
        return { status: 'skipped', actions, skipped };
    }
    await notifyAutoTrades(actions);
    return { status: 'executed', actions, skipped };
};

const runBlofinAutoTrade = async ({ signals, snapshot, reason } = {}) =>
    runAutoTradeWithSettings({ signals, snapshot, reason });

module.exports = {
    runBlofinAutoTrade,
    runAutoTradeWithSettings
};
