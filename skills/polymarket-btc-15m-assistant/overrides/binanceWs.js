import WebSocket from "ws";
import { CONFIG } from "../config.js";
import { wsAgentForUrl } from "../net/proxy.js";

const SOURCE = String(process.env.BTC15M_PRICE_SOURCE || "blofin").toLowerCase();
const BLOFIN_BASE_URL = process.env.BLOFIN_BASE_URL || "https://openapi.blofin.com";
const BLOFIN_INST_ID = process.env.BLOFIN_INST_ID || "BTC-USDT";

function toNumber(x) {
  const n = Number(x);
  return Number.isFinite(n) ? n : null;
}

function buildWsUrl(symbol) {
  const s = String(symbol || "").toLowerCase();
  return `wss://stream.binance.com:9443/ws/${s}@trade`;
}

async function fetchBlofinLastPrice() {
  const res = await fetch(`${BLOFIN_BASE_URL}/api/v1/market/tickers`);
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

export function startBinanceTradeStream({ symbol = CONFIG.symbol, onUpdate } = {}) {
  let ws = null;
  let closed = false;
  let reconnectMs = 500;
  let lastPrice = null;
  let lastTs = null;
  let pollTimer = null;

  const setPrice = (price) => {
    if (price === null) return;
    lastPrice = price;
    lastTs = Date.now();
    if (typeof onUpdate === "function") onUpdate({ price: lastPrice, ts: lastTs });
  };

  const connectBinance = () => {
    if (closed) return;

    const url = buildWsUrl(symbol);
    ws = new WebSocket(url, { agent: wsAgentForUrl(url) });

    ws.on("open", () => {
      reconnectMs = 500;
    });

    ws.on("message", (buf) => {
      try {
        const msg = JSON.parse(buf.toString());
        const p = toNumber(msg.p);
        if (p === null) return;
        setPrice(p);
      } catch {
        return;
      }
    });

    const scheduleReconnect = () => {
      if (closed) return;
      try {
        ws?.terminate();
      } catch {
        // ignore
      }
      ws = null;
      const wait = reconnectMs;
      reconnectMs = Math.min(10_000, Math.floor(reconnectMs * 1.5));
      setTimeout(connectBinance, wait);
    };

    ws.on("close", scheduleReconnect);
    ws.on("error", scheduleReconnect);
  };

  const startBlofinPolling = () => {
    if (closed) return;
    const poll = async () => {
      try {
        const price = await fetchBlofinLastPrice();
        setPrice(price);
      } catch {
        // ignore polling errors
      }
    };
    poll();
    pollTimer = setInterval(poll, 1500);
  };

  if (SOURCE === "binance") {
    connectBinance();
  } else {
    startBlofinPolling();
  }

  return {
    getLast() {
      return { price: lastPrice, ts: lastTs };
    },
    close() {
      closed = true;
      if (pollTimer) {
        clearInterval(pollTimer);
        pollTimer = null;
      }
      try {
        ws?.close();
      } catch {
        // ignore
      }
      ws = null;
    }
  };
}
