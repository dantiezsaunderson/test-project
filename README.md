# UltraFast XAUUSD Scalper Project

This repository now includes an MT5 Expert Advisor focused on fast XAUUSD scalp execution with live-account safety controls.

## Project Structure

- `mt5/UltraFastXAUUSDScalper.mq5` - main MT5 EA source code
- `mt5/README.md` - setup, tuning, and risk guidance for MT5
- `index.html`, `styles.css`, `script.js` - existing static site files

## EA Highlights

- EMA + breakout + RSI + volume-impulse signal logic
- spread/slippage/session/tick-rate filters
- ATR-based SL/TP sizing
- breakeven and trailing stop management
- max holding time exit
- daily loss and consecutive-loss guards

## Next Step

Open `mt5/README.md` for install instructions and baseline parameter ranges before backtesting or running on live accounts.
