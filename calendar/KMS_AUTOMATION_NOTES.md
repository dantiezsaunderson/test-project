KMS Automation Notes (Zapier / Meta API)
========================================
Folder Structure:
/reels /static /carousels /captions /templates /calendar

File Naming (Required):
post-title-YYYY-MM-DD.ext
Example: founded-in-detroit-2026-02-03.mp4

Metadata Fields (Recommended JSON)
----------------------------------
{
  "post_id": "L-REEL-01",
  "title": "Founded in Detroit",
  "date": "2026-02-03",
  "format": "reel",
  "media_path": "/reels/founded-in-detroit-2026-02-03.mp4",
  "caption_path": "/captions/L-REEL-01.txt",
  "hashtags": ["#KMSRecords", "#DetroitTechno"],
  "credits": "Photo: TBD",
  "status": "draft"
}

Zapier / Make Flow (Concept)
----------------------------
1) New file in Google Drive or Dropbox with naming schema
2) Parse filename to date + title
3) Match caption file by post_id
4) Create scheduled post via Meta API
5) Log status back to Airtable/Sheet

Meta API Notes
--------------
- Reels require a cover image and media URL
- Carousels require child media upload first
- Keep captions under 2,200 chars
- Avoid last-minute edits that break scheduled timestamps

Automation Agent (Local)
------------------------
See /automation for a starter Node-based posting agent that:
- Reads /calendar/KMS_30_DAY_CALENDAR.csv
- Builds a posting queue JSON
- Prepares file paths for Meta API scheduling
