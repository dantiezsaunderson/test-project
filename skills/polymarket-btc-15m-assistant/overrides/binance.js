import { CONFIG } from "../config.js";

function toNumber(x) {
  const n = Number(x);
  return Number.isFinite(n) ? n : null;
}

function toInstId(symbol) {
  if (!symbol) return "BTC-USDT";
  if (symbol.includes("-")) return symbol;
  if (symbol.endsWith("USDT")) return `${symbol.slice(0, -4)}-USDT`;
  if (symbol.endsWith("USDC")) return `${symbol.slice(0, -4)}-USDC`;
  if (symbol.endsWith("USD")) return `${symbol.slice(0, -3)}-USD`;
  return symbol;
}

const SOURCE = String(process.env.BTC15M_PRICE_SOURCE || "blofin").toLowerCase();
const BLOFIN_BASE_URL = process.env.BLOFIN_BASE_URL || "https://openapi.blofin.com";
const BLOFIN_INST_ID = process.env.BLOFIN_INST_ID || toInstId(CONFIG.symbol);

async function fetchBinanceKlines({ interval, limit }) {
  const url = new URL("/api/v3/klines", CONFIG.binanceBaseUrl);
  url.searchParams.set("symbol", CONFIG.symbol);
  url.searchParams.set("interval", interval);
  url.searchParams.set("limit", String(limit));

  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`Binance klines error: ${res.status} ${await res.text()}`);
  }
  const data = await res.json();

  return data.map((k) => ({
    openTime: Number(k[0]),
    open: toNumber(k[1]),
    high: toNumber(k[2]),
    low: toNumber(k[3]),
    close: toNumber(k[4]),
    volume: toNumber(k[5]),
    closeTime: Number(k[6])
  }));
}

async function fetchBinanceLastPrice() {
  const url = new URL("/api/v3/ticker/price", CONFIG.binanceBaseUrl);
  url.searchParams.set("symbol", CONFIG.symbol);
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`Binance last price error: ${res.status} ${await res.text()}`);
  }
  const data = await res.json();
  return toNumber(data.price);
}

async function fetchBlofinKlines({ interval, limit }) {
  const url = new URL("/api/v1/market/candles", BLOFIN_BASE_URL);
  url.searchParams.set("instId", BLOFIN_INST_ID);
  url.searchParams.set("bar", interval);
  url.searchParams.set("limit", String(limit));
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`Blofin candles error: ${res.status} ${await res.text()}`);
  }
  const payload = await res.json();
  if (payload.code !== "0") {
    throw new Error(`Blofin candles error: ${payload.msg || "unknown"}`);
  }
  const data = Array.isArray(payload.data) ? payload.data : [];
  const mapped = data
    .map((k) => ({
      openTime: Number(k[0]),
      open: toNumber(k[1]),
      high: toNumber(k[2]),
      low: toNumber(k[3]),
      close: toNumber(k[4]),
      volume: toNumber(k[5]),
      closeTime: Number(k[0])
    }))
    .filter((k) => Number.isFinite(k.openTime));
  return mapped.sort((a, b) => a.openTime - b.openTime);
}

async function fetchBlofinLastPrice() {
  const url = new URL("/api/v1/market/tickers", BLOFIN_BASE_URL);
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`Blofin tickers error: ${res.status} ${await res.text()}`);
  }
  const payload = await res.json();
  if (payload.code !== "0") {
    throw new Error(`Blofin tickers error: ${payload.msg || "unknown"}`);
  }
  const list = Array.isArray(payload.data) ? payload.data : [];
  const match = list.find((item) => item.instId === BLOFIN_INST_ID);
  if (!match) {
    throw new Error(`Blofin tickers missing ${BLOFIN_INST_ID}`);
  }
  return toNumber(match.last);
}

export async function fetchKlines({ interval, limit }) {
  if (SOURCE === "binance") {
    return fetchBinanceKlines({ interval, limit });
  }
  try {
    return await fetchBlofinKlines({ interval, limit });
  } catch (error) {
    if (SOURCE === "blofin") {
      throw error;
    }
    return fetchBinanceKlines({ interval, limit });
  }
}

export async function fetchLastPrice() {
  if (SOURCE === "binance") {
    return fetchBinanceLastPrice();
  }
  try {
    return await fetchBlofinLastPrice();
  } catch (error) {
    if (SOURCE === "blofin") {
      throw error;
    }
    return fetchBinanceLastPrice();
  }
}
