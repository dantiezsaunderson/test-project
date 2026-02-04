const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const CSV_PATH = path.join(ROOT, "calendar", "KMS_30_DAY_CALENDAR.csv");
const OUTPUT_PATH = path.join(ROOT, "calendar", "posting_queue.json");

const parseCSV = (input) => {
  const rows = [];
  let row = [];
  let current = "";
  let inQuotes = false;

  for (let i = 0; i < input.length; i += 1) {
    const char = input[i];
    const next = input[i + 1];

    if (char === '"' && inQuotes && next === '"') {
      current += '"';
      i += 1;
      continue;
    }

    if (char === '"') {
      inQuotes = !inQuotes;
      continue;
    }

    if (char === "," && !inQuotes) {
      row.push(current);
      current = "";
      continue;
    }

    if ((char === "\n" || char === "\r") && !inQuotes) {
      if (current.length > 0 || row.length > 0) {
        row.push(current);
        rows.push(row);
      }
      row = [];
      current = "";
      continue;
    }

    current += char;
  }

  if (current.length > 0 || row.length > 0) {
    row.push(current);
    rows.push(row);
  }

  return rows;
};

const toObject = (headers, row) => {
  const out = {};
  headers.forEach((header, index) => {
    out[header] = row[index] || "";
  });
  return out;
};

const resolveGridPath = (id, filename) => {
  if (!id || !filename) {
    return "";
  }
  if (id.includes("CAR")) {
    return path.join("carousels", filename);
  }
  return path.join("static", filename);
};

const buildQueue = () => {
  const raw = fs.readFileSync(CSV_PATH, "utf8").trim();
  const rows = parseCSV(raw);
  const headers = rows.shift();

  const items = rows
    .filter((row) => row.length && row.some((cell) => cell.trim() !== ""))
    .map((row) => {
      const data = toObject(headers, row);
      return {
        date: data.date,
        day: data.day,
        reel: {
          id: data.reel_id,
          filename: data.reel_filename,
          path: data.reel_filename ? path.join("reels", data.reel_filename) : ""
        },
        grid: {
          id: data.grid_id || "",
          filename: data.grid_filename || "",
          path: resolveGridPath(data.grid_id, data.grid_filename)
        },
        story_stack: data.story_stack
      };
    });

  return {
    generated_at: new Date().toISOString(),
    timezone: "America/Detroit",
    items
  };
};

const queue = buildQueue();
fs.writeFileSync(OUTPUT_PATH, JSON.stringify(queue, null, 2));
console.log(`Posting queue written to ${OUTPUT_PATH}`);
