---
name: forward_test
description: Start/stop the forward-test scheduler and run reports.
metadata: { "openclaw": { "requires": { "bins": ["node"] } } }
---

# Forward Test Runner

This skill starts the bot scheduler in a detached process for forward testing
and provides simple status/stop/report commands.

## Commands (via exec)

- Start the forward test:
  - `node {baseDir}/forward-test.js start`
- Check status:
  - `node {baseDir}/forward-test.js status`
- Stop the forward test:
  - `node {baseDir}/forward-test.js stop`
- Performance report (last 7 days):
  - `node {baseDir}/forward-test.js report --days 7`

## Notes
- Writes logs to `.forward-test.log` at repo root.
- Writes PID to `.forward-test.pid` at repo root.
