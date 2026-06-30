# Wiki Studio — Pass 1: Study core + Synthesis backlog (design)

**Date:** 2026-06-30
**Status:** approved concept; spec under review
**Mockups:** `docs/mockups/2026-06-30-wiki-studio-before-after.html`, `docs/mockups/2026-06-30-wiki-studio-v2.html`

## Overview

Reframe AppleNotestoX from a *"move Apple Notes → Notion/Wiki"* exporter toward a
**study-first hub** centered on the `Personal_LLM_Wiki` vault. This spec covers the
**first build pass only**:

1. **Study core** — refresh the review app's study data and launch it from the GUI,
   with the wiki as the visual hero.
2. **Synthesis backlog** — surface what's sitting in `raw/` but not yet synthesized
   into `wiki/`.

The full hub reframe (Capture menu unification, in-app wiki Browse/page render) and
**X bookmarks** import are explicitly *later passes* (see Out of scope).

## Goals

- Make the vault feel like *the place you study*, not a write target.
- One click to **refresh study data** (no more stale `study-data.js` — yours was a day old).
- One click to **launch** the Wiki Review app.
- A visible **backlog** of `raw/` notes awaiting synthesis (12 today), with a hand-off to opencode.

## Non-goals (this pass)

- No full NavigationSplitView teardown; the existing Capture (export) flow stays intact.
- The app never writes `wiki/` — synthesis stays LLM-owned (per the vault's `AGENTS.md`).
- No in-app rendering of full wiki pages (that's the later **Browse** feature).
- No X integration yet.

## Scope

### Feature A — Study core

- **Refresh study data:** run `node <review>/generate.mjs --vault <vaultURL> --out <review>/study-data.js`
  via the (deadlock-safe) process runner; show a spinner; on success update counts and
  "last refreshed" time; on failure show a precise error.
- **Launch Wiki Review:** open `<review>/index.html` in the default browser (`open`).
- **Live counts:** `N concepts · M cards · K links`, parsed from the generator output and/or
  `study-data.js`.
- **"Jump back in" list:** top ~6 concept titles by connection count (edges), derived from
  `study-data.js`. Cheap, gives the hero substance, links nowhere in pass 1 (Launch is the action).
- **No "due today":** that count lives in the *browser's* localStorage (the review app's SRS
  state) and is not readable by the Swift app. The hero shows concepts + cards only.

### Feature B — Synthesis backlog

- Scan `vault/raw/journal/*.md`; flag each note **without** a same-named
  `vault/wiki/sources/<name>.md` as *pending*. (Naming convention from the vault `AGENTS.md`:
  source pages are `wiki/sources/YYYY-MM-DD-<slug>.md`, mirroring `raw/journal/YYYY-MM-DD-<slug>.md`.)
- Show the pending **count** + the most recent few + "+ N more".
- **Copy opencode prompt:** put a ready instruction on the clipboard, e.g.
  *"Synthesize these raw/ notes into the wiki per AGENTS.md (provenance, `[[wikilinks]]`, one
  `wiki/sources/` page each): `raw/journal/…`, …"*.
- **Reveal in Finder** for the `raw/journal/` folder.
- Empty state: *"All caught up — nothing waiting in raw/."*

## Architecture

New, small, independently-testable units. Existing export code is untouched.

| Unit | Responsibility | Depends on |
|---|---|---|
| `ProcessRunner` (extracted) | Run a child process, drain pipes concurrently, return stdout/stderr/status. | Foundation |
| `StudyDataService` | Run the generator; parse counts; read `study-data.js` → counts + top concepts. | `ProcessRunner`, `RepoPaths` |
| `SynthesisBacklog` | Pure: given raw/journal + wiki/sources file lists → `[BacklogItem]`. | Foundation (FileManager) |
| `RepoPaths` | Resolve `review/` (`generate.mjs`, `index.html`) + locate `node`. | `#filePath`, UserDefaults, FileManager |
| `StudyView` / `CaptureView` | SwiftUI surfaces for the two app modes. | `AppState` |

- **`ProcessRunner`**: extract the existing `AppleNotesService.runProcess` into a shared
  `enum ProcessRunner` (deadlock-safe concurrent drain we already shipped). `AppleNotesService`
  and `StudyDataService` both call it. Keeps one correct implementation.
- **`RepoPaths`**: repo root resolved from `#filePath` (compile-time absolute path of a source
  file → walk up to the package root), overridable via a **Settings** field ("Review folder").
  `node` resolved by probing `/opt/homebrew/bin/node`, `/usr/local/bin/node`, `/usr/bin/node`,
  then `/usr/bin/env node`. Clear error if none found.
- **`study-data.js` parsing**: strip the `window.STUDY_DATA = ` prefix and trailing `;`, then
  `JSONDecoder`. "Jump back in" = concepts ranked by edge degree (count of edges touching the id).

### Data flow

```
[Refresh] → StudyDataService.refresh()
          → ProcessRunner.run(node, generate.mjs, --vault, --out)
          → parse stdout counts  +  read study-data.js → topConcepts
          → AppState publishes {counts, lastGenerated, jumpBackIn}
[Launch]  → NSWorkspace.shared.open(index.html)            (native; no node/Process)
[Backlog] → SynthesisBacklog.scan(vaultURL) → AppState.backlogItems
[Copy]    → NSPasteboard ← prompt(backlogItems)
```

## UI / UX

- **App mode switch** (seed of the hub): for pass 1 this ships as a **segmented control**
  in the detail toolbar — **Study** (default) and **Capture** — i.e. the first two entries of
  the mock's left rail; the full left rail arrives with the Pass 2 shell. Study is a full-width
  pane; Capture preserves today's Source | Destination split (Apple Notes → Notion/Wiki, video)
  unchanged.
- **Study (hero):** big `55 concepts · 96 cards` figure (tabular numerals), **Launch Wiki
  Review** (single accent/primary button), **Refresh** (secondary), "last refreshed" time,
  and the "jump back in" concept list. Wiki is the dominant element.
- **Backlog (supporting):** quieter panel — pending badge, recent items, **Copy opencode
  prompt**, **Reveal in Finder**.
- Conform to the review app's **Direction-B tokens** (indigo accent on near-black; light theme
  via tokens). One focal point, one primary action; accent only for action/active/key metric.

### States

- No vault chosen → Study shows a "Choose your vault" prompt (reuses existing vault chooser/bookmark).
- `study-data.js` missing (never generated) → counts show "—" + a nudge to Refresh.
- Refreshing → spinner, Refresh disabled.
- `node`/`generate.mjs` not found → error naming the resolved paths + Settings hint.
- Backlog empty → "All caught up."

## Error handling

- All process calls return status + stderr; non-zero surfaces a user-facing message (reuse the
  existing `errorMessage` alert in `ContentView`).
- `RepoPaths` failures (no node, no review folder) are typed errors with remediation text.
- Generator partial/garbled output → counts fall back to reading `study-data.js`; if that also
  fails, show "couldn't read study data".

## Testing (TDD)

- `SynthesisBacklog`: temp-dir fixtures — pending detection, all-synthesized (empty), naming
  edge cases (no `.md`, mismatched dates). Pure, fast.
- `study-data.js` parsing: decode a sample `window.STUDY_DATA = {…};` → counts + jump-back-in
  ordering by edge degree; malformed input → nil/empty, no crash.
- `RepoPaths` node discovery: given a synthetic candidate list, picks the first existing.
- `ProcessRunner`: already covered by `ProcessRunnerTests` (>64 KB no-deadlock + stderr/status).
- Generator integration (optional): run `generate.mjs` against a tiny fixture vault → non-zero counts.

## Verification

- `swift build` exit 0.
- `swift test` green under Xcode/CI (this pass adds unit tests; CLT-only machines can't run XCTest).
- Manual: Refresh regenerates `study-data.js` and updates counts; Launch opens the review app;
  backlog shows the 12 pending notes; Copy prompt yields a usable opencode instruction.

## Out of scope / future passes

- **Pass 2 — Wiki Studio shell:** full hub layout, in-app **Browse** with rendered wiki pages.
- **Pass 3 — Capture menu:** unify Apple Notes / Video / Notion behind "＋ Capture"; demote Notion.
- **Pass 4 — X bookmarks:** start with the no-cost **paste-tweet-URL** MVP (save to `raw/`);
  full OAuth2 `GET /2/users/{id}/bookmarks` sync only if a paid X tier is available.

## Notes / accepted limitations

- Requires `node` on the machine (the generator is Node, no deps). Documented + error-handled.
- "Synthesized?" is a filename-match heuristic for v1 — may slightly over-report (better to
  over-remind than to miss). Upgrade path: grep `wiki/` for references / a frontmatter flag.
