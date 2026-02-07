# Test Project for AI Agent Verification

This is a simple test project created to verify that the AI agent can successfully:
- Create a new project
- Push it to GitHub
- Deploy it to Render

## Project Structure
- index.html - Main HTML file
- styles.css - CSS styling
- script.js - JavaScript functionality

## Deployment Information
This project will be deployed to Render to verify the AI agent's deployment capabilities.

## MT5 Expert Advisor
This repository now includes an MT5 Expert Advisor that implements the
ICC (Indication, Correction, Continuation) strategy:

- `ICC_Trading_Strategy_EA.mq5` - Full ICC strategy EA for MetaTrader 5

### Usage
1. Copy `ICC_Trading_Strategy_EA.mq5` to your terminal's `MQL5/Experts` folder.
2. Open MetaEditor and compile the EA.
3. Attach the EA to the chart you want to trade.
4. Configure inputs for bias timeframe (H1/H4), entry timeframe (M15/M5),
   session windows, and risk settings.

### Notes
- The EA trades only during the configured London and New York sessions.
- It uses swing structure to detect trend, waits for indication and correction,
  then enters on lower timeframe continuation breaks.
- Stop loss is placed beyond the correction extreme; take profit targets the
  indication level (or a configurable risk-reward fallback).
