KMS Posting Agent (Starter)
===========================
This is a local, automation-ready scaffold. It reads the KMS calendar CSV and
generates a structured queue for scheduling posts via the Meta API.

What it does
------------
- Reads /calendar/KMS_30_DAY_CALENDAR.csv
- Builds /calendar/posting_queue.json
- Resolves default asset paths (reels, static, carousels)

Usage
-----
1) Ensure assets are named exactly as in the CSV file.
2) Run:
   node automation/posting_agent.js
3) Review /calendar/posting_queue.json

Notes
-----
- This does not post to Instagram yet. It prepares the queue.
- You can wire this output into a Meta API scheduler or Zapier flow.
- Update /automation/config.example.json with real credentials and rename to
  config.json if needed.
