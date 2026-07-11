# Multi-Modal Review Layer (P3) Implementation Plan

> REQUIRED SUB-SKILL: superpowers:executing-plans.

**Goal:** A dependency-free static web app + Node generator that turns the wiki into flashcards (SM-2), a concept map, and TTS audio/narrated-slide recaps.

**Stack:** vanilla HTML/CSS/JS (classic `<script>` globals, file://-friendly); Node ≥18 generator. No frameworks, no build.

## Global Constraints
- No bundler/deps; classic scripts (no ES modules in the app — `file://` safe). Generator may use Node ESM (`.mjs`).
- Data via `window.STUDY_DATA` (synthetic sample committed; vault-derived output generated + gitignored).
- SM-2 exact: EF'=max(1.3, EF+(0.1-(5-q)(0.08+(5-q)0.02))); n=1→1d, n=2→6d, else ceil(I·EF); q<3 resets n→0,I→1. Grades Again/Hard/Good/Easy=q 1/3/4/5.
- `frontend-design` tokens (Direction B), `prefers-reduced-motion`, AA contrast, visible focus, representative synthetic content.
- TTS: robust `voiceschanged`; start on user gesture.

## Tasks

### Task 1: Generator `review/generate.mjs`
- CLI `--vault <path> --out <file>`; walk `wiki/**/*.md`.
- Parse frontmatter (regex `^---\n...\n---`), strip ``` fences + inline code, extract title (frontmatter title or H1 or filename), first paragraph as summary, tags, `[[wikilinks]]` (split `|`,`#`).
- Flashcards: `Q::A`, `Q:::A` (two cards), multiline `?`/`??`; fallback: `{title}` → first sentence.
- Emit `window.STUDY_DATA = {generatedAt, concepts, cards, edges}` (edges filtered to existing concept ids; deterministic slug ids).
- Verify: run on `~/Projects/Personal_LLM_Wiki`; print counts; `node --check`.

### Task 2: `review/js/srs.js` (SM-2 + localStorage)
- `SRS.review(state,q)`, `SRS.gradeToQ`, `SRS.dueCards(cards, now)`, `SRS.load(id)/save(id,state)`, `SRS.nextIntervalPreview(state,q)`.
- Verify headless: node check of intervals/EF reset.

### Task 3: `review/js/tts.js`
- `TTS.available`, `TTS.loadVoices()` (voiceschanged), `TTS.speak(text,{onend})`, `pause/resume/cancel`, `TTS.reducedMotion`.

### Task 4: `review/js/data.js`
- Normalize `window.STUDY_DATA` (fallback to sample); index concepts by id; build adjacency.

### Task 5: `review/js/flashcards.js`, `graph.js`, `recap.js`
- flashcards: render due queue, flip (Space), grade (1–4 + buttons w/ interval preview), progress, session summary, persists via SRS.
- graph: force layout (repulsion/spring/gravity/damping/alpha), canvas draw, node hit-test + side panel, search; respects reduced-motion (skip animation, settle instantly).
- recap: build slides (concept title + key points), auto-advance with TTS narration, play/pause/next/prev, progress dots; per-concept "Listen".

### Task 6: `review/index.html` + `review/styles.css` + `review/js/app.js`
- Shell: top bar (brand, due chip, theme toggle), nav tabs, `<main>`; hash router (#/today,#/review,#/map,#/recap).
- Today dashboard: due count + Start review (primary), streak, recent concepts.
- styles.css: Direction B tokens (dark default + `[data-theme=light]`), components, states, focus, motion.
- Includes all js via classic `<script>` in order.

### Task 7: `review/study-data.sample.js`
- Small synthetic dataset about local-first knowledge pipelines, provenance, conversion, study/review, and safe agent workflows, with cards + edges so the app runs with zero setup.

### Task 8: Verify + commit + PROGRESS_REPORT + merge
- `node --check` all js; run generator against a configured test vault; gitignore `review/study-data.js`; commit atomically; update PROGRESS_REPORT; merge to main.
