---
name: market_edge_lab
description: Form and test market edge hypotheses for crypto, FX, and prediction markets.
metadata: { "openclaw": {} }
---

# Market Edge Lab

Use this skill to generate **edge hypotheses** and a plan to validate them.
No trading execution should be performed unless explicitly requested.

## Workflow

1. Identify market + timeframe (crypto, FX, Polymarket).
2. Propose 5 edge hypotheses, such as:
   - Liquidity vacuum after event risk
   - Spread compression signals
   - Lead/lag between correlated assets
   - Volume spikes before volatility expansion
3. For each hypothesis, provide:
   - Data needed (public sources or existing signals)
   - Validation steps
   - Risks and failure cases
4. Output a short "Edge Memo":
   - Hypothesis
   - Evidence
   - Go/no-go criteria

## Output format

- Summary table of hypotheses
- 1-2 recommended tests to run next
