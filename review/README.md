# Wiki Review (P3)

A dependency-free, no-build study app over your LLM-wiki: **flashcards with spaced
repetition (SM-2)**, a **concept map**, and **narrated recaps** (TTS). Pairs with the
Apple Notes → wiki pipeline (P1/P2).

## Run it

**Demo (zero setup):** open `review/index.html` in a browser — it loads the committed
`study-data.sample.js`, a hand-curated fixture containing only synthetic demo content.

**From a vault:**

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
- `js/tts.js` — Web Speech narration (prefers a local English voice, then falls back to
  another English or browser-default voice; the browser/platform may use a network voice;
  needs a click to start in Safari).
- `js/app.js`, `index.html`, `styles.css` — shell, hash router, Today dashboard, theme.
- `study-data.sample.js` — committed demo data; `study-data.js` — generated (gitignored).
- `mockups/compare.html` — the design-direction comparison (A vs B; B shipped).

## Notes

- Flashcards: Space flips, 1–4 grade (Again/Hard/Good/Easy → SM-2 q 1/3/4/5). "Again"
  re-queues within the session and schedules +1 day.
- Review history lives in `localStorage` keyed by card id. Definition-card ids remain
  stable while the source filename remains stable. Explicit-card ids include their
  position within the page, so inserting or reordering explicit cards can change ids and
  disconnect those cards from earlier history.
- Authoring richer cards: add a single-line `Q::A` or `Q:::A` card, or a multiline card
  separated by `?` or `??`, anywhere in a wiki page. A `## Review` heading has no special
  parser behavior; cards beneath it are found only when they use one of those formats.
  Without an explicit card, the generator makes one definition card per concept.
