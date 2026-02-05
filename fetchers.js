const axios = require('axios');
const config = require('./config');
const polymarketClient = require('./polymarketClient');
const blofinScanner = require('./blofinScanner');

const http = axios.create({
    timeout: 10000
});

const buildPriceSnapshot = (raw, currency) =>
    Object.entries(raw || {}).reduce((acc, [id, values]) => {
        const price = values[currency];
        const change = values[`${currency}_24h_change`];
        acc[id] = {
            price,
            change24h: Number.isFinite(change) ? change : null
        };
        return acc;
    }, {});

const fetchCoinGecko = async (ids, currency) => {
    if (!ids.length) {
        return {};
    }
    const { data } = await http.get(
        'https://api.coingecko.com/api/v3/simple/price',
        {
            params: {
                ids: ids.join(','),
                vs_currencies: currency,
                include_24hr_change: true
            }
        }
    );
    return buildPriceSnapshot(data, currency);
};

const fetchCrypto = async () => {
    const { ids, vsCurrency } = config.markets.crypto;
    const prices = await fetchCoinGecko(ids, vsCurrency);
    return {
        source: 'coingecko',
        vsCurrency,
        prices
    };
};

const fetchMeme = async () => {
    const { ids, vsCurrency } = config.markets.meme;
    const prices = await fetchCoinGecko(ids, vsCurrency);
    return {
        source: 'coingecko',
        vsCurrency,
        prices
    };
};

const fetchForex = async () => {
    const { base, symbols } = config.markets.forex;
    try {
        const { data } = await http.get(`https://open.er-api.com/v6/latest/${base}`);
        const rates = data && data.rates ? data.rates : {};
        const filtered = symbols.reduce((acc, symbol) => {
            if (Number.isFinite(rates[symbol])) {
                acc[symbol] = rates[symbol];
            }
            return acc;
        }, {});

        return {
            source: 'open.er-api.com',
            base,
            rates: filtered
        };
    } catch (error) {
        const { data } = await http.get('https://api.exchangerate.host/latest', {
            params: {
                base,
                symbols: symbols.join(',')
            }
        });

        return {
            source: 'exchangerate.host',
            base,
            rates: data && data.rates ? data.rates : {}
        };
    }
};

const fetchCollectibles = async () => {
    const headers = {};
    if (config.apiKeys.pokemonTcg) {
        headers['X-Api-Key'] = config.apiKeys.pokemonTcg;
    }

    const { data } = await http.get('https://api.pokemontcg.io/v2/sets', {
        params: {
            pageSize: config.markets.collectibles.setsPageSize,
            orderBy: '-releaseDate'
        },
        headers
    });

    const sets = (data && data.data ? data.data : []).map((set) => ({
        id: set.id,
        name: set.name,
        releaseDate: set.releaseDate,
        total: set.total
    }));

    return {
        source: 'pokemontcg',
        sets
    };
};

const fetchPolymarket = async () => {
    const settings = config.markets.polymarket;
    const discovery = await polymarketClient.discoverBestMarket({
        source: settings.source,
        webUrl: settings.webUrl,
        webMaxMarkets: settings.webMaxMarkets,
        gammaHost: settings.gammaHost,
        clobHost: settings.clobHost,
        chainId: settings.chainId,
        minLiquidity: settings.minLiquidity,
        minVolume: settings.minVolume,
        candidates: settings.candidates,
        spreadCheckTop: settings.spreadCheckTop,
        pickSide: settings.pickSide,
        spreadAlert: settings.spreadAlert,
        priceMoveAlert: settings.priceMoveAlert
    });

    const topSignals = (discovery.evaluated || []).slice(0, settings.signalTop);

    return {
        source: discovery.source || 'polymarket',
        generatedAt: new Date().toISOString(),
        pickSide: discovery.pickSide,
        totals: discovery.totals,
        best: discovery.best,
        topCandidates: topSignals
    };
};

const fetchBlofinPerps = async () => {
    const scan = await blofinScanner.fetchSignals();
    return {
        source: 'blofin',
        generatedAt: scan.generatedAt,
        timeframe: scan.timeframe,
        instType: scan.instType,
        total: scan.total,
        signals: scan.signals,
        errors: scan.errors
    };
};

module.exports = {
    fetchCrypto,
    fetchMeme,
    fetchForex,
    fetchCollectibles,
    fetchPolymarket,
    fetchBlofinPerps
};
