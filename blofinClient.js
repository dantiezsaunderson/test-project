const axios = require('axios');
const crypto = require('crypto');
const config = require('./config');

const http = axios.create({
    timeout: 15000
});

const buildQuery = (params = {}) => {
    const entries = Object.entries(params).filter(
        ([, value]) => value !== undefined && value !== null && value !== ''
    );
    if (!entries.length) {
        return '';
    }
    return entries
        .map(
            ([key, value]) =>
                `${encodeURIComponent(key)}=${encodeURIComponent(value)}`
        )
        .join('&');
};

const getBaseUrl = () =>
    config.markets.blofin.useDemo
        ? config.markets.blofin.demoBaseUrl
        : config.markets.blofin.baseUrl;

const signRequest = ({ method, requestPath, query, body, apiKey, apiSecret, passphrase }) => {
    const timestamp = Date.now().toString();
    const nonce = timestamp;
    const requestWithQuery = query ? `${requestPath}?${query}` : requestPath;
    const signBody = body || '';
    const payload = `${requestWithQuery}${method}${timestamp}${nonce}${signBody}`;
    const signature = crypto
        .createHmac('sha256', apiSecret)
        .update(payload)
        .digest('base64');

    return {
        headers: {
            'ACCESS-KEY': apiKey,
            'ACCESS-PASSPHRASE': passphrase,
            'ACCESS-TIMESTAMP': timestamp,
            'ACCESS-NONCE': nonce,
            'ACCESS-SIGN': signature
        }
    };
};

const request = async ({ method, path, params, auth }) => {
    const baseUrl = getBaseUrl();
    const requestPath = `/api/v1/${path}`;
    const query = method === 'GET' ? buildQuery(params) : '';
    const body = method === 'GET' ? undefined : params && Object.keys(params).length ? JSON.stringify(params) : '';
    const url = query ? `${baseUrl}${requestPath}?${query}` : `${baseUrl}${requestPath}`;

    const headers = {};
    if (auth) {
        const apiKey = config.markets.blofin.apiKey;
        const apiSecret = config.markets.blofin.apiSecret;
        const passphrase = config.markets.blofin.apiPassphrase;
        if (!apiKey || !apiSecret || !passphrase) {
            throw new Error('Missing Blofin API credentials.');
        }
        const signed = signRequest({
            method,
            requestPath,
            query,
            body,
            apiKey,
            apiSecret,
            passphrase
        });
        Object.assign(headers, signed.headers);
    }
    if (body) {
        headers['Content-Type'] = 'application/json';
    }

    const response = await http.request({
        url,
        method,
        headers,
        data: body
    });

    const payload = response.data;
    if (payload && payload.code && payload.code !== '0') {
        const message = payload.msg || 'Blofin error';
        throw new Error(`${message} (${payload.code})`);
    }
    return payload;
};

const publicGet = (path, params = {}) =>
    request({ method: 'GET', path, params, auth: false });

const privateGet = (path, params = {}) =>
    request({ method: 'GET', path, params, auth: true });

const privatePost = (path, params = {}) =>
    request({ method: 'POST', path, params, auth: true });

const fetchInstruments = async (instType = 'SWAP') => {
    const payload = await publicGet('market/instruments', { instType });
    return Array.isArray(payload.data) ? payload.data : [];
};

const fetchTickers = async () => {
    const payload = await publicGet('market/tickers');
    return Array.isArray(payload.data) ? payload.data : [];
};

const fetchCandles = async ({ instId, bar, limit }) => {
    const payload = await publicGet('market/candles', {
        instId,
        bar,
        limit
    });
    const data = Array.isArray(payload.data) ? payload.data : [];
    return data.map((row) => ({
        ts: Number(row[0]),
        open: Number(row[1]),
        high: Number(row[2]),
        low: Number(row[3]),
        close: Number(row[4]),
        volume: Number(row[5]),
        volumeCcy: Number(row[6])
    }));
};

const fetchMarkPrice = async (instId) => {
    const payload = await publicGet('market/mark-price', { instId });
    return payload.data || {};
};

const fetchAccountBalance = async () => {
    const payload = await privateGet('account/balance');
    return payload.data || {};
};

const fetchPositions = async (instId) => {
    const params = instId ? { instId } : {};
    const payload = await privateGet('account/positions', params);
    return Array.isArray(payload.data) ? payload.data : [];
};

const setLeverage = async ({ instId, leverage, marginMode }) => {
    const payload = await privatePost('account/set-leverage', {
        instId,
        leverage,
        marginMode
    });
    return payload.data || payload;
};

const placeOrder = async ({
    instId,
    side,
    orderType,
    size,
    price,
    marginMode,
    positionSide
}) => {
    const requestBody = {
        instId,
        side,
        orderType,
        size,
        marginMode
    };
    if (price !== undefined && price !== null) {
        requestBody.price = price;
    }
    if (positionSide) {
        requestBody.positionSide = positionSide;
    }
    const payload = await privatePost('trade/order', requestBody);
    return payload.data || payload;
};

module.exports = {
    fetchInstruments,
    fetchTickers,
    fetchCandles,
    fetchMarkPrice,
    fetchAccountBalance,
    fetchPositions,
    setLeverage,
    placeOrder
};
