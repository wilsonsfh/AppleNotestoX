# Wiki Review (P3)

A dependency-free, no-build study app over your LLM-wiki: **flashcards with spaced
repetition (SM-2)**, a **concept map**, and **narrated recaps** (TTS). Pairs with the
Apple Notes → wiki pipeline (P1/P2).

## Run it

**Demo (zero setup):** open `review/index.html` in a browser — it loads the committed
`study-data.sample.js` (real concepts from the notes).

**From your real vault:**

```bash
node review/generate.mjs --vault ~/Projects/Personal_LLM_Wiki
# writes review/study-data.js (gitignored); then reload review/index.html
```

Tip: some browsers restrict features on `file://`. If anything misbehaves, serve the
folder: `python3 -m http.server -d review 8080` → open `http://localhost:8080`.

## What's where

- `generate.mjs` — reads `<vault>/wiki/**/*.md` (frontmatter, `[[wikilinks]]`, `Q::A`
  cards, heuristic fallback) → `window.STUDY_DATA`.
- `js/srs.js` — SM-2 + localStorage (review history + streak).
- `js/flashcards.js`, `js/graph.js`, `js/recap.js` — the three views.
- `js/tts.js` — Web Speech narration (on-device voices; needs a click to start in Safari).
- `js/app.js`, `index.html`, `styles.css` — shell, hash router, Today dashboard, theme.
- `study-data.sample.js` — committed demo data; `study-data.js` — generated (gitignored).
- `mockups/compare.html` — the design-direction comparison (A vs B; B shipped).

## Notes

- Flashcards: Space flips, 1–4 grade (Again/Hard/Good/Easy → SM-2 q 1/3/4/5). "Again"
  re-queues within the session and schedules +1 day.
- Review history lives in `localStorage` keyed by card id; regenerating keeps history
  because ids are deterministic slugs.
- Authoring richer cards: add a `Q::A` line (or `## Review` section) to any wiki page;
  the generator picks them up, otherwise it makes one definition card per concept.
