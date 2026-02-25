# AGENTS.md

## Cursor Cloud specific instructions

This is a simple static website (HTML/CSS/vanilla JS) with no build system, no package manager, and no dependencies.

### Running the dev server

Serve the project root with any static file server:

```
python3 -m http.server 8000
```

Then open `http://localhost:8000` in a browser.

### Testing

There are no automated tests or linters configured for this project. Verification is done by opening the site in a browser and confirming:
- The page renders with the green header, project info card, and footer.
- The JavaScript-generated timestamp appears on the page.

### Notes

- No `npm install`, `pip install`, or other dependency steps are needed.
- The `script.js` file runs a brief CSS animation on the header after page load (1 second delay) — this is expected behavior, not a bug.
