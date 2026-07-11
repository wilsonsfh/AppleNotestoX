# Multi-Modal Review / Study Layer (P3) — Design

- **Date:** 2026-06-29
- **Status:** Approved (owner-delegated; comparison mockup at `review/mockups/compare.html`, Direction B chosen)
- **Project:** `review/` (static web app) + a Node generator, inside the `AppleNotestoX` repo.

## 1. Problem & scope

The wiki gives great *storage + synthesis*; what's missing is an **active, multi-modal
way to study it** so learning isn't "minimal and chunking." P3 turns the synthesized
`wiki/` into a review experience: **flashcards with spaced repetition**, a **concept map**,
and **audio + narrated-slide recaps** (the "video-like" modality).

**In scope:** a dependency-free static web app (opens from `file://`, also runs under any
static server) + a Node generator that reads a vault's `wiki/` and emits `study-data.js`.

**Out of scope (later):** server sync, multi-device SR history, real video file export
(narrated slides are the recap), authoring flashcards inside the app.

## 2. Decisions (recommended)

1. **Form factor:** static, **no-build, dependency-free** web app (vanilla HTML/CSS/JS,
   classic `<script>` globals). Portable + testable on any machine; not tied to Xcode.
2. **Data loading from `file://`:** generator emits `study-data.js` setting
   `window.STUDY_DATA` (a `fetch('*.json')` would be CORS-blocked on `file://`). A committed
   `study-data.sample.js` lets the app run immediately without a vault.
3. **Spaced repetition:** faithful **SM-2** (EF start 2.5, intervals 1d/6d/`ceil(I·EF)`,
   reset on q<3), state in **localStorage**. Grades Again/Hard/Good/Easy → q 1/3/4/5.
4. **Flashcards source:** extract Obsidian-style cards from `wiki/` — `Q::A`, `Q:::A`
   (reversed), and multi-line `?`/`??`; plus a heuristic fallback (page title → first
   sentence / bolded term definitions) so even un-annotated wikis are reviewable.
5. **Concept map:** dependency-free **force-directed** canvas graph from `[[wikilinks]]`.
6. **Audio/"video":** **Web Speech API** (`speechSynthesis`) for audio recaps and
   auto-advancing **narrated slides** — zero deps, offline via OS voices, robust
   `voiceschanged` voice loading, started from a user gesture (Safari requirement).
7. **Design:** Direction B tokens (dark default + light theme), `frontend-design`
   non-negotiables, `prefers-reduced-motion` respected.

## 3. Architecture

```
review/
  index.html            # shell: top bar, nav (Today/Review/Map/Recap), <script> includes
  styles.css            # design tokens + components (dark default, [data-theme=light])
  js/
    data.js             # reads window.STUDY_DATA (or sample); normalizes
    srs.js              # SM-2 + localStorage (pure, unit-checkable via node)
    flashcards.js       # review view (flip, grade, keyboard, progress)
    graph.js            # force-directed concept map (canvas) + side panel
    tts.js              # speechSynthesis wrapper (robust voices, reduced-motion)
    recap.js            # narrated auto-advancing slides + audio recap
    app.js              # tiny hash router + Today dashboard + view mounting
  study-data.sample.js  # committed demo dataset (window.STUDY_DATA)
  study-data.js         # GENERATED (gitignored) from the selected vault
  generate.mjs          # Node: vault wiki/ -> study-data.js
  mockups/compare.html  # design comparison (A vs B)
```

**Generator (`generate.mjs`, Node ≥18):** `node review/generate.mjs --vault <path> [--out review/study-data.js]`.
- Walk `<vault>/wiki/**/*.md`. For each: parse frontmatter (regex), strip code fences,
  extract `[[wikilinks]]` (handle `|alias`, `#heading`), title, first paragraph, tags.
- Extract flashcards (`::`, `:::`, `?`, `??`) from a `## Review` section or anywhere.
- Heuristic fallback cards when a page has none (definition from first sentence).
- Emit `window.STUDY_DATA = { generatedAt, concepts:[{id,title,type,summary,tags,links}], cards:[{id,deck,front,back,source}], edges:[{source,target}] }`.
- Deterministic ids (slug of title) so SR localStorage history survives regeneration.

**SRS (`srs.js`):** pure functions `review(state,q)` (SM-2), `dueCards(cards,now)`,
`load()/save()` (localStorage namespaced by card id). Unit-checkable headless via node.

## 4. Views (one focal point each)

- **Today (dashboard):** big "Start review" with due count; streak; small "recent concepts"
  list; quick links to Map/Recap. The single primary action is Start review.
- **Review:** one card; Space/click to flip; 1–4 (or buttons) to grade, each showing the
  *next interval*; progress bar; ends with a session summary.
- **Map:** force-directed graph; node click → side panel (summary, tags, links, "Review
  this deck", "Listen"). Search box filters/zooms.
- **Recap:** pick a topic (or "all due") → auto-advancing narrated slides (title + key
  points), TTS narration with play/pause/next, progress dots. Also a one-click "Listen"
  audio recap of a concept.

## 5. Error / empty / a11y states (frontend-design)

- **Empty:** no data / no due cards → friendly state with a clear next action (generate, or
  "you're done for today"). Sample data ensures first-run is never blank.
- **TTS unavailable / no voices:** hide audio controls gracefully + a one-line note.
- **Reduced motion:** `prefers-reduced-motion` disables card-flip/graph-settle animation.
- **Keyboard + focus:** full keyboard review loop; visible `:focus-visible` rings; hit
  targets ≥ 40px; AA contrast in both themes.
- **Representative synthetic content, no lorem;** long answers/titles wrap; zero-link concepts render fine.

## 6. Verification

- **Generator:** run against the configured default `~/Projects/Personal_LLM_Wiki` with Node; assert it
  emits well-formed `study-data.js` (concepts > 0, valid edges referencing concept ids,
  cards present). Sanity-print counts.
- **SRS:** headless `node` check of SM-2 (q=5 path 1→6→ceil; q<3 resets; EF floor 1.3).
- **Static analysis:** `node --check` each JS file; HTML opens (manual on test machine).
- **Runtime gates (test machine):** open `review/index.html`, run a review session, view
  the graph, play a recap (TTS needs a user gesture, esp. Safari).
