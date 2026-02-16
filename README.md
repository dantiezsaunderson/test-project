# UltraFast XAUUSD Scalper Project

This repository now includes an MT5 Expert Advisor focused on fast XAUUSD scalp execution with live-account safety controls.

## Project Structure

- `mt5/UltraFastXAUUSDScalper.mq5` - main MT5 EA source code
- `mt5/README.md` - setup, tuning, and risk guidance for MT5
- `index.html`, `styles.css`, `script.js` - existing static site files

## EA Highlights

- EMA + breakout + RSI + volume-impulse signal logic
- symbol auto-detection for broker variants (`XAUUSDm`, `XAUUSD.pro`, etc.)
- spread/slippage/session/tick-rate/regime filters
- STANDARD and ECN low-spread execution modes
- ATR-based SL/TP sizing with adaptive time-stop
- breakeven, adaptive trailing, and optional partial take-profit
- max holding time exit
- daily loss and consecutive-loss guards
- built-in diagnostics counters for blocked trade reasons

## Next Step

Open `mt5/README.md` for install instructions and baseline parameter ranges before backtesting or running on live accounts.
