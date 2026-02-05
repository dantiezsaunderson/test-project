const axios = require('axios');

const http = axios.create({
    timeout: 15000
});

const normalizeNumber = (value) => {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
};

const normalizeSide = (value) => {
    const side = String(value || 'YES').toUpperCase();
    return side === 'NO' ? 'NO' : 'YES';
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

const discoverBestMarket = async (options) => {
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
