const axios = require('axios');

const http = axios.create({
    timeout: 15000
});

const normalizeNumber = (value) => {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
};

const toNumber = (value) => {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
};

const normalizeSide = (value) => {
    const side = String(value || 'YES').toUpperCase();
    return side === 'NO' ? 'NO' : 'YES';
};

const extractNextData = (html) => {
    const marker = 'id="__NEXT_DATA__"';
    const idx = html.indexOf(marker);
    if (idx === -1) {
        throw new Error('Polymarket page payload not found.');
    }
    const start = html.indexOf('>', idx);
    const end = html.indexOf('</script>', start);
    if (start === -1 || end === -1) {
        throw new Error('Polymarket page payload incomplete.');
    }
    const json = html.slice(start + 1, end);
    return JSON.parse(json);
};

const collectWebResults = (nextData) => {
    const queries = nextData?.props?.pageProps?.dehydratedState?.queries || [];
    const results = [];
    queries.forEach((query) => {
        const pages = query?.state?.data?.pages;
        if (!Array.isArray(pages)) {
            return;
        }
        pages.forEach((page) => {
            if (Array.isArray(page.results)) {
                results.push(...page.results);
            }
        });
    });
    return results;
};

const normalizeOutcomeMap = (outcomes, outcomePrices) => {
    const map = {};
    outcomes.forEach((outcome, index) => {
        const price = toNumber(outcomePrices[index]);
        if (outcome && price !== null) {
            map[String(outcome).toUpperCase()] = price;
        }
    });
    return map;
};

const buildMarketUrl = (slug) =>
    slug ? `https://polymarket.com/market/${slug}` : null;

const sanitizeWebMarket = (market, event) => {
    const outcomes = Array.isArray(market.outcomes) ? market.outcomes : [];
    const outcomePrices = Array.isArray(market.outcomePrices)
        ? market.outcomePrices
        : [];
    const outcomeMap = normalizeOutcomeMap(outcomes, outcomePrices);

    const liquidity = normalizeNumber(market.liquidityNum ?? market.liquidity);
    const volume24hr = normalizeNumber(
        market.volume24hr ?? market.volume24hrClob ?? 0
    );
    const volume = normalizeNumber(market.volumeNum ?? market.volume);
    const volume1wk = normalizeNumber(market.volume1wk ?? market.volume1wkClob ?? 0);
    const activityVolume = volume24hr || volume;
    const bestBid = toNumber(market.bestBid);
    const bestAsk = toNumber(market.bestAsk);
    const spread =
        toNumber(market.spread) ??
        (bestBid !== null && bestAsk !== null
            ? Math.max(bestAsk - bestBid, 0)
            : null);

    return {
        id: market.id || market.conditionId || market.questionID || market.slug,
        slug: market.slug || market.ticker || null,
        question:
            market.question || market.title || event?.title || event?.question || '',
        eventTitle: event?.title || event?.question || null,
        eventSlug: event?.slug || null,
        url: buildMarketUrl(market.slug || market.ticker || null),
        liquidity,
        volume,
        volume24hr,
        volume1wk,
        activityVolume,
        spread,
        bestBid,
        bestAsk,
        lastTradePrice: toNumber(market.lastTradePrice),
        oneHourPriceChange: toNumber(market.oneHourPriceChange),
        oneDayPriceChange: toNumber(market.oneDayPriceChange),
        endDate: market.endDate || market.end_date || event?.endDate || null,
        outcomes,
        outcomePrices: outcomePrices.map((price) => normalizeNumber(price)),
        outcomeMap
    };
};

const collectWebMarkets = (results, maxMarkets) => {
    const map = new Map();
    results.forEach((event) => {
        const markets = Array.isArray(event.markets) ? event.markets : [event];
        markets.forEach((market) => {
            const id = market.id || market.conditionId || market.questionID || market.slug;
            if (!id || map.has(id)) {
                return;
            }
            map.set(id, sanitizeWebMarket(market, event));
        });
    });
    const list = Array.from(map.values());
    if (Number.isFinite(maxMarkets) && list.length > maxMarkets) {
        return list.slice(0, maxMarkets);
    }
    return list;
};

const scoreWebMarket = (market) => {
    const liquidityScore = Math.log10(1 + market.liquidity);
    const volumeScore = Math.log10(1 + market.activityVolume);
    const spreadPenalty = Number.isFinite(market.spread) ? market.spread : 0.05;
    const momentum =
        Math.abs(market.oneDayPriceChange ?? 0) +
        Math.abs(market.oneHourPriceChange ?? 0);
    return liquidityScore * 2 + volumeScore * 1.5 - spreadPenalty * 50 + momentum * 5;
};

const tagWebMarket = (market, thresholds) => {
    const tags = [];
    if (
        Number.isFinite(market.spread) &&
        market.spread <= thresholds.spreadAlert
    ) {
        tags.push('tight-spread');
    }
    if (market.activityVolume >= thresholds.minVolume * 2) {
        tags.push('high-volume');
    }
    if (market.liquidity >= thresholds.minLiquidity * 2) {
        tags.push('deep-liquidity');
    }
    const dayMove = Math.abs(market.oneDayPriceChange ?? 0);
    if (dayMove >= thresholds.priceMoveAlert) {
        tags.push('momentum');
    }
    return tags;
};

const marketScore = (market) =>
    normalizeNumber(market.liquidity) * 2 + normalizeNumber(market.volume);

const sanitizeMarket = (market) => {
    const tokens = Array.isArray(market.clobTokenIds) ? market.clobTokenIds : [];
    return {
        id: market.id,
        slug: market.slug,
        question: market.question,
        liquidity: normalizeNumber(market.liquidity),
        volume: normalizeNumber(market.volume),
        endDate: market.endDate,
        tokens: {
            yes: tokens[0] ? String(tokens[0]) : null,
            no: tokens[1] ? String(tokens[1]) : null
        }
    };
};

const fetchGammaMarkets = async (gammaHost, limit) => {
    const url = new URL('/markets', gammaHost);
    url.searchParams.set('active', 'true');
    url.searchParams.set('closed', 'false');
    url.searchParams.set('limit', String(limit));
    const { data } = await http.get(url.toString());
    if (Array.isArray(data)) {
        return data;
    }
    if (data && Array.isArray(data.data)) {
        return data.data;
    }
    return [];
};

const selectCandidates = (markets, options) => {
    const minLiquidity = normalizeNumber(options.minLiquidity);
    const minVolume = normalizeNumber(options.minVolume);
    const pickSide = normalizeSide(options.pickSide);

    return markets
        .map((market) => sanitizeMarket(market))
        .filter(
            (market) =>
                market.tokens.yes &&
                market.tokens.no &&
                market.liquidity >= minLiquidity &&
                market.volume >= minVolume
        )
        .map((market) => ({
            ...market,
            pickSide,
            tokenId: pickSide === 'YES' ? market.tokens.yes : market.tokens.no,
            activityVolume: market.volume,
            score: marketScore(market)
        }))
        .sort((a, b) => b.score - a.score);
};

const resolveSpread = (spreadPayload) => {
    if (Number.isFinite(spreadPayload)) {
        return spreadPayload;
    }
    if (spreadPayload && typeof spreadPayload === 'object') {
        if (Number.isFinite(spreadPayload.spread)) {
            return spreadPayload.spread;
        }
        if (Number.isFinite(spreadPayload.spreadBps)) {
            return spreadPayload.spreadBps / 10000;
        }
        if (Number.isFinite(spreadPayload.bps)) {
            return spreadPayload.bps / 10000;
        }
    }
    return null;
};

const getClobClient = async (clobHost, chainId, credentials) => {
    const { ClobClient } = await import('@polymarket/clob-client');
    return new ClobClient(clobHost, chainId, credentials);
};

const evaluateSpreads = async (candidates, options) => {
    if (!candidates.length) {
        return [];
    }
    const client = await getClobClient(options.clobHost, options.chainId);
    const evaluated = [];

    for (const candidate of candidates) {
        try {
            const spreadPayload = await client.getSpread(candidate.tokenId);
            const spread = resolveSpread(spreadPayload);
            evaluated.push({
                ...candidate,
                spread,
                spreadError: spread === null ? 'Unknown spread format' : null
            });
        } catch (error) {
            evaluated.push({
                ...candidate,
                spread: null,
                spreadError: error.message || 'Spread fetch failed'
            });
        }
    }

    return evaluated;
};

const selectBestCandidate = (candidates) => {
    return candidates.reduce((best, candidate) => {
        if (!Number.isFinite(candidate.spread)) {
            return best;
        }
        if (!best) {
            return candidate;
        }
        if (candidate.spread < best.spread) {
            return candidate;
        }
        if (candidate.spread === best.spread && candidate.score > best.score) {
            return candidate;
        }
        return best;
    }, null);
};

const selectWebCandidates = (results, options) => {
    const minLiquidity = normalizeNumber(options.minLiquidity);
    const minVolume = normalizeNumber(options.minVolume);
    const pickSide = normalizeSide(options.pickSide);
    const spreadAlert = normalizeNumber(options.spreadAlert);
    const priceMoveAlert = normalizeNumber(options.priceMoveAlert);
    const maxMarkets = Number(options.webMaxMarkets || 0);
    const webMarkets = collectWebMarkets(results, maxMarkets);

    return webMarkets
        .map((market) => {
            const pickSidePrice =
                market.outcomeMap[pickSide] ?? market.outcomeMap[pickSide.toUpperCase()];
            return {
                ...market,
                pickSide,
                pickSidePrice: Number.isFinite(pickSidePrice) ? pickSidePrice : null,
                score: scoreWebMarket(market),
                tags: tagWebMarket(market, {
                    minLiquidity,
                    minVolume,
                    spreadAlert,
                    priceMoveAlert
                })
            };
        })
        .filter(
            (market) =>
                market.liquidity >= minLiquidity &&
                market.activityVolume >= minVolume
        )
        .sort((a, b) => b.score - a.score);
};

const discoverBestMarketFromWeb = async (options) => {
    const webUrl = options.webUrl || 'https://polymarket.com/markets';
    const response = await http.get(webUrl);
    const nextData = extractNextData(response.data);
    const results = collectWebResults(nextData);
    const evaluated = selectWebCandidates(results, options);
    const best = evaluated[0] || null;

    return {
        source: 'web',
        pickSide: normalizeSide(options.pickSide),
        webUrl,
        totals: {
            results: results.length,
            evaluated: evaluated.length
        },
        evaluated,
        best
    };
};

const discoverBestMarketFromApi = async (options) => {
    const gammaHost = options.gammaHost;
    const clobHost = options.clobHost;
    const chainId = Number(options.chainId);
    const pickSide = normalizeSide(options.pickSide);
    const limit = Number(options.candidates);

    const markets = await fetchGammaMarkets(gammaHost, limit);
    const filtered = selectCandidates(markets, options);
    const spreadCheckTop = Math.min(
        Number(options.spreadCheckTop) || 0,
        filtered.length
    );
    const candidatesToCheck = filtered.slice(0, spreadCheckTop);
    const evaluated = await evaluateSpreads(candidatesToCheck, {
        clobHost,
        chainId
    });
    const best = selectBestCandidate(evaluated);

    return {
        source: 'api',
        pickSide,
        gammaHost,
        clobHost,
        chainId,
        totals: {
            markets: markets.length,
            filtered: filtered.length,
            evaluated: evaluated.length
        },
        evaluated,
        best
    };
};

const discoverBestMarket = async (options) => {
    const source = String(options.source || 'api').toLowerCase();
    if (source === 'web') {
        return discoverBestMarketFromWeb(options);
    }
    return discoverBestMarketFromApi(options);
};

const createOrder = async (options) => {
    const client = await getClobClient(options.clobHost, options.chainId, {
        apiKey: options.apiKey,
        secret: options.apiSecret,
        passphrase: options.apiPassphrase
    });

    return client.createOrder({
        tokenId: options.tokenId,
        side: options.side,
        price: options.price,
        size: options.size
    });
};

const getBalanceAllowance = async (options) => {
    const client = await getClobClient(options.clobHost, options.chainId, {
        apiKey: options.apiKey,
        secret: options.apiSecret,
        passphrase: options.apiPassphrase
    });

    return client.getBalanceAllowance({
        asset_type: options.assetType,
        token_id: options.tokenId
    });
};

const deriveApiCredentials = async (options) => {
    const { Wallet } = await import('ethers');
    const wallet = new Wallet(options.privateKey);
    const actual = wallet.address.toLowerCase();
    const expected = String(options.expectedAddress || '').trim().toLowerCase();
    if (!expected || expected !== actual) {
        throw new Error(`Address mismatch: ${wallet.address} != ${options.expectedAddress}`);
    }

    const client = await getClobClient(options.clobHost, options.chainId, wallet);
    return client.createOrDeriveApiKey();
};

module.exports = {
    discoverBestMarket,
    createOrder,
    getBalanceAllowance,
    deriveApiCredentials,
    normalizeSide
};
