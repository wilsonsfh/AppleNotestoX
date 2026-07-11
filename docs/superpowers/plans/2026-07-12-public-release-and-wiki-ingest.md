# Public Release and Personal Wiki Ingest Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish the completed AppleNotestoX project as the public `wilsonsfh/AppleNotestoX` repository with comprehensive release documentation, then ingest its results and transferable lessons into `Personal_LLM_Wiki` with provenance.

**Architecture:** Treat the existing private GitHub repository as the release target. Add a motivation-first root README, audit the full public surface, commit and fast-forward the default branch, change visibility through `gh`, verify anonymous access, then capture the shipped evidence in immutable wiki raw notes before updating source, project, concept, index, and log pages.

**Tech Stack:** Git, GitHub CLI, Markdown, Swift 6/SwiftUI project gates, Obsidian-style Personal_LLM_Wiki.

## Global Constraints

- Repository owner and commit identity: `wilsonsfh` with `74759808+wilsonsfh@users.noreply.github.com`.
- Existing remote is `https://github.com/wilsonsfh/AppleNotestoX.git`; do not create a duplicate repository.
- Default branch `main` must contain the release commit before visibility changes from private to public.
- Do not expose credentials, generated personal vault data, private raw wiki files, or real user-note screenshots.
- README must cover motivation, benefits, why to use it, how to use it, choices, trade-offs, learnings, specifications, architecture, tech stack, privacy, verification, status, and limitations.
- Preserve honest gates: XCTest requires Xcode; real Notes/Speech/Notion acceptance remains separately documented where not executed.
- Use exact repository paths and commands; do not modify git config.
- Personal wiki ingestion is provenance-first: new facts land under `raw/` before `wiki/` synthesis.
- Wiki files use YAML frontmatter, kebab-case names, wikilinks, index updates, and append-only log entries.
- No force-push, history rewrite, release binary, deployment, or license addition unless separately requested.

---

### Task 1: Public README and Release Surface

**Files:**
- Create: `README.md`
- Modify: `review/README.md` only if its demo-data wording overstates personal provenance.

- [ ] **Step 1: Write the root README**

Use this section order:

1. Product summary
2. Motivation
3. Why use it / benefits
4. What it does
5. End-to-end architecture
6. Key design choices and trade-offs
7. Tech stack
8. Requirements
9. Build and run
10. Apple Notes to Personal Wiki workflow
11. Notion and video workflows
12. Study/review workflow
13. Privacy and safety model
14. Verification and project status
15. Specifications and repository map
16. Learnings
17. Author

Use concrete commands and clearly distinguish required versus optional tools. Avoid claims that a manual runtime gate passed when it did not.

- [ ] **Step 2: Audit tracked public content**

Search tracked files and history for secret formats, personal raw data, absolute home paths, private work-vault paths, and sensitive note titles. Inspect `review/study-data.sample.js` directly. Require no credential matches and no generated `review/study-data.js` tracking.

- [ ] **Step 3: Review README accuracy**

Cross-check every feature/status claim against `Package.swift`, `PROGRESS_REPORT.md`, source code, specs, and verification reports. Run `git diff --check`.

---

### Task 2: Release Verification, Commit, and Public GitHub Publication

**Files:**
- Commit all intended project source, tests, specs/plans, and README changes.
- Exclude ignored build outputs, generated vault data, and `.superpowers/` scratch artifacts.

- [ ] **Step 1: Run final gates**

Run:

```bash
swift build
git diff --check
```

Run the current-source AppleNoteSearch executable, PersonalWikiActionState executable, and current-build AppState probe. Attempt the focused XCTest filter and record the expected missing-XCTest environment limitation.

- [ ] **Step 2: Inspect the exact release diff**

Run `git status`, `git diff --stat`, `git diff`, and recent log. Stage explicit intended paths only. Confirm no secret, generated, or personal-vault files are staged.

- [ ] **Step 3: Commit with verified authorship**

Create the release commit with environment-scoped identity:

```bash
GIT_AUTHOR_NAME=wilsonsfh \
GIT_AUTHOR_EMAIL=74759808+wilsonsfh@users.noreply.github.com \
GIT_COMMITTER_NAME=wilsonsfh \
GIT_COMMITTER_EMAIL=74759808+wilsonsfh@users.noreply.github.com \
git commit -m "feat: ship searchable editorial wiki workflow"
```

Verify `%an <%ae>` and `%cn <%ce>` on the new commit.

- [ ] **Step 4: Publish default main and make repository public**

Fast-forward remote main with `git push origin HEAD:main`. Then run:

```bash
gh repo edit wilsonsfh/AppleNotestoX \
  --visibility public \
  --accept-visibility-change-consequences
```

Set a concise public description and relevant topics. Verify `gh repo view`, anonymous HTTP access, default branch, visibility, README rendering, and final commit SHA.

- [ ] **Step 5: Record shipped progress**

After the first push, add a newest-first `PROGRESS_REPORT.md` entry with the public URL, branch, release SHA, verification evidence, and remaining external gates. Commit it with the same identity and push `HEAD:main` again.

---

### Task 3: Provenance-First Personal Wiki Ingest

**Files:**
- Create: `Personal_LLM_Wiki/raw/journal/2026-07-12-apple-notestox-publication-request.md`
- Create: `Personal_LLM_Wiki/raw/reference/2026-07-12-apple-notestox-engineering-retrospective.md`
- Create: `Personal_LLM_Wiki/wiki/sources/2026-07-12-apple-notestox-publication.md`
- Create: `Personal_LLM_Wiki/wiki/projects/apple-notestox.md`
- Create or update: `Personal_LLM_Wiki/wiki/concepts/local-first-knowledge-pipelines.md`
- Update: `Personal_LLM_Wiki/wiki/concepts/software-engineering-best-practices.md`
- Update: `Personal_LLM_Wiki/wiki/concepts/ui-design-taste-deslop.md`
- Update: `Personal_LLM_Wiki/wiki/index.md`
- Append: `Personal_LLM_Wiki/wiki/log.md`

- [ ] **Step 1: Capture immutable provenance**

Write one cleaned user-stated journal note preserving the publication/README/wiki-ingest request, and one agent-observed reference note with final public URL, release/progress SHAs, files, architecture, decisions, trade-offs, commands, passed gates, blocked gates, screenshots, and results.

- [ ] **Step 2: Synthesize the source and project pages**

Create a terse source page and a durable project page covering motivation, architecture, product value, implementation chronology, choices, trade-offs, outcomes, limitations, lessons, and relation to Wilson's engineering/design growth. Cite both raw notes.

- [ ] **Step 3: Synthesize transferable concepts**

Create `local-first-knowledge-pipelines` if absent. Update software-engineering and UI-design concepts only with generalized lessons: immutable raw versus derived synthesis, operation-state separation, synthetic visual fixtures, native accessibility semantics, evidence hierarchy, and public-release safety.

- [ ] **Step 4: Update navigation and activity log**

Add project/concept/source entries to `wiki/index.md` in schema order and append one chronological ingest entry to `wiki/log.md`.

---

### Task 4: Final Cross-Repository Verification

- [ ] **Step 1: Verify GitHub publication**

Confirm public visibility, anonymous page access, README presence, default branch, final SHA, clean/stable remote state, and author/committer identity.

- [ ] **Step 2: Verify wiki integrity**

Check all new frontmatter, source paths, wikilinks, index entries, log format, source counts, and absence of broken links. Do not edit immutable raw files after creation.

- [ ] **Step 3: Report residual risks**

Report Xcode/XCTest, real Notes/Speech/Notion runtime gates, TCC-blocked VoiceOver automation, public repository license status, and any local branch/worktree cleanup intentionally left undone.
