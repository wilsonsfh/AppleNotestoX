# Editorial Workspace Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the complete native macOS app as a quiet editorial workspace while preserving all verified Study, Capture, search, export, Notion, settings, and permission behavior.

**Architecture:** Add one presentation-only SwiftUI style file, then migrate each existing surface onto those shared metrics and treatments. Keep observable state, service calls, keyboard commands, and export guards unchanged; each UI pass must compile and receive a focused diff review before the next pass.

**Tech Stack:** Swift 6, SwiftUI, Observation, AppKit, macOS 14+, XCTest files retained for Xcode/CI.

## Global Constraints

- Swift tools 6.0 and `.macOS(.v14)`; add no dependencies or custom fonts.
- Preserve the existing product model, navigation, data flow, service calls, and verified behavior.
- Use native system colors, materials, controls, focus rings, light/dark appearance, and the user's accent color.
- Use an 8-point spacing rhythm, comfortable density, restrained corner radii, hairline borders, and no decorative gradients or heavy shadows.
- Use system serif only for Study's heading and key empty-state headings; keep metrics and controls in semantic San Francisco styles.
- Keep one obvious primary action per surface; status must not rely on color alone.
- Preserve Command-F, Escape, destination-specific Command-Return, full-row note selection, VoiceOver labels, and the 900x600 minimum window.
- Do not run a real export or mutate Apple Notes/wiki data during verification.
- Local XCTest is unavailable because Command Line Tools lacks XCTest; `swift build`, standalone behavior harnesses, `git diff --check`, launch, visual inspection, and code review are mandatory local gates.
- Do not commit, merge, push, or publish unless the user separately requests it.

## File Map

- Create `Sources/AppleNotestoX/UI/WorkspaceStyle.swift`: presentation tokens and small reusable treatments only.
- Modify `Sources/AppleNotestoX/UI/StudyView.swift`: editorial study hero and synthesis rail.
- Modify `Sources/AppleNotestoX/UI/SourcePane.swift`: capture header, rows, empty state, and action footer.
- Modify `Sources/AppleNotestoX/UI/DestinationPane.swift`: destination hierarchy and setup sections.
- Modify `Sources/AppleNotestoX/UI/ContentView.swift`: toolbar hierarchy and split widths.
- Modify `Sources/AppleNotestoX/UI/SettingsView.swift`: grouped settings and permission presentation.
- Modify `Sources/AppleNotestoX/UI/PreviewSheet.swift`: archive confirmation hierarchy and progress rows.
- Do not modify models, services, coordinators, or existing behavior tests.

---

### Task 1: Shared Editorial Presentation Foundation

**Files:**
- Create: `Sources/AppleNotestoX/UI/WorkspaceStyle.swift`

**Interfaces:**
- Produces: `WorkspaceStyle` spacing/radius constants.
- Produces: `WorkspaceSectionLabel`, `WorkspaceBadge`, `WorkspaceEmptyState`.
- Produces: `workspaceInsetSurface()` and `workspaceFooterSurface()` view modifiers.

- [ ] **Step 1: Establish the baseline gate**

Run:

```bash
swift build
git diff --check
```

Expected: build succeeds and diff check has no output before the presentation changes.

- [ ] **Step 2: Add the presentation-only style file**

Create `WorkspaceStyle.swift` with this bounded API:

```swift
import SwiftUI

enum WorkspaceStyle {
    static let spacing4: CGFloat = 4
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing24: CGFloat = 24
    static let cornerRadius: CGFloat = 10
}

struct WorkspaceSectionLabel: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

struct WorkspaceBadge: View {
    let text: String
    var tint: Color = .accentColor

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, WorkspaceStyle.spacing8)
            .padding(.vertical, WorkspaceStyle.spacing4)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct WorkspaceEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: WorkspaceStyle.spacing8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(.title3, design: .serif, weight: .semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(WorkspaceStyle.spacing24)
    }
}

private struct WorkspaceInsetSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(WorkspaceStyle.spacing16)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: WorkspaceStyle.cornerRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: WorkspaceStyle.cornerRadius)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
            }
    }
}

private struct WorkspaceFooterSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(WorkspaceStyle.spacing12)
            .background(.regularMaterial)
    }
}

extension View {
    func workspaceInsetSurface() -> some View { modifier(WorkspaceInsetSurface()) }
    func workspaceFooterSurface() -> some View { modifier(WorkspaceFooterSurface()) }
}
```

- [ ] **Step 3: Compile and inspect the foundation**

Run `swift build` and `git diff --check`. Expected: both pass; no observable state or action appears in `WorkspaceStyle.swift`.

---

### Task 2: Editorial Study Surface

**Files:**
- Modify: `Sources/AppleNotestoX/UI/StudyView.swift`

**Interfaces:**
- Consumes: all Task 1 presentation helpers.
- Preserves: `loadStudyOnAppear`, `refreshStudyData`, `launchWikiReview`, vault setup, backlog prompt copy, and folder reveal.

- [ ] **Step 1: Rebuild the page hierarchy without changing actions**

Keep the two-column layout but use a flexible hero and a 320-point supporting rail:

```swift
HStack(alignment: .top, spacing: 0) {
    hero
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(WorkspaceStyle.spacing24)
    Divider()
    backlog
        .frame(width: 320)
        .padding(WorkspaceStyle.spacing16)
        .background(Color(nsColor: .underPageBackgroundColor))
}
.background(Color(nsColor: .windowBackgroundColor))
.task { state.loadStudyOnAppear() }
```

- [ ] **Step 2: Apply the editorial metric and action hierarchy**

Use a serif `Study your wiki` heading, then an SF concept count with tabular figures, supporting card/link counts, and this action order:

```swift
Text("Study your wiki")
    .font(.system(.largeTitle, design: .serif, weight: .semibold))

Text("\(state.studyData?.conceptCount ?? 0)")
    .font(.system(size: 60, weight: .semibold))
    .monospacedDigit()
    .minimumScaleFactor(0.75)

Button {
    state.launchWikiReview()
} label: {
    Label("Launch Wiki Review", systemImage: "book.pages")
}
.buttonStyle(.borderedProminent)
.disabled(state.studyData == nil)

Button {
    Task { await state.refreshStudyData() }
} label: {
    if state.isRefreshingStudy { ProgressView().controlSize(.small) }
    else { Label("Refresh", systemImage: "arrow.clockwise") }
}
.disabled(state.isRefreshingStudy)
```

Keep recent-concept chips flat, using a subtle control-background fill and no border/shadow stack.

- [ ] **Step 3: Restyle the synthesis rail and empty states**

Use `WorkspaceBadge` for backlog count, comfortable 8-point row spacing, and `WorkspaceEmptyState` for missing vault. Keep the populated backlog actions and bottom explanatory text unchanged.

- [ ] **Step 4: Verify Study independently**

Run `swift build` and `git diff --check`. Launch the app into Study without refreshing or opening external files; inspect the minimum-width layout and confirm every existing Study action is still present in the diff.

---

### Task 3: Capture Source Pane

**Files:**
- Modify: `Sources/AppleNotestoX/UI/SourcePane.swift`

**Interfaces:**
- Consumes: `WorkspaceStyle`, `WorkspaceBadge`, `WorkspaceEmptyState`, and `workspaceFooterSurface()`.
- Preserves: search bindings/focus, hierarchy/search modes, selection toggling, accessibility descriptions, vault picker, export state resolution, and Command-Return ownership.

- [ ] **Step 1: Strengthen the source header and search hierarchy**

Replace the selected-count prose with a conditional badge while preserving the progress indicator:

```swift
HStack(spacing: WorkspaceStyle.spacing8) {
    VStack(alignment: .leading, spacing: 2) {
        Text("Apple Notes").font(.title3.weight(.semibold))
        Text("Choose what belongs in your knowledge base")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    Spacer()
    if state.loadingApple { ProgressView().controlSize(.small) }
    if !state.selectedNoteIDs.isEmpty {
        WorkspaceBadge(text: "\(state.selectedNoteIDs.count) selected")
    }
}
.padding(.horizontal, WorkspaceStyle.spacing16)
.padding(.vertical, WorkspaceStyle.spacing12)
```

Keep the existing `TextField` binding, focus listener, disabled condition, accessibility label, and Escape behavior. Change only spacing and use `.controlSize(.large)` for a clearer search target.

- [ ] **Step 2: Restyle rows without changing row data or actions**

Keep the checkbox, document icon, title, optional folder path, archive seal, relative date, `contentShape`, tap action, and accessibility description. Add only:

```swift
.padding(.vertical, WorkspaceStyle.spacing4)
```

Use `Color.accentColor` only for selected checkbox state and keep status colors semantic.

- [ ] **Step 3: Unify loading and empty states**

Use `WorkspaceEmptyState` for no data and no search results. The search-empty action remains a separate `Clear Search` button directly beneath the helper so it can preserve focus and clear `noteSearchQuery`.

- [ ] **Step 4: Make the footer action unmistakable**

Keep the exact `PersonalWikiActionState.resolve` call and switch cases. Apply `workspaceFooterSurface()` to the footer and use full-width button labels:

```swift
Button {
    state.exportDestination = .wiki
    Task { await state.runWikiExport() }
} label: {
    Label(
        "Export \(noteCount) \(noteCount == 1 ? "note" : "notes")",
        systemImage: "arrow.up.doc"
    )
    .frame(maxWidth: .infinity)
}
.buttonStyle(.borderedProminent)
```

Retain its existing conditional keyboard shortcut, disabled condition, accessibility label, and all configure/running/completed branches.

- [ ] **Step 5: Verify Capture source independently**

Run `swift build`, the existing search/AppState standalone harnesses, and `git diff --check`. Statically compare every source-pane action and accessibility label before/after. Launch Capture without selecting a vault or exporting; verify search and row selection at the minimum width.

---

### Task 4: Destination Pane and Window Toolbar

**Files:**
- Modify: `Sources/AppleNotestoX/UI/DestinationPane.swift`
- Modify: `Sources/AppleNotestoX/UI/ContentView.swift`

**Interfaces:**
- Consumes: Task 1 presentation helpers.
- Preserves: destination binding, vault picker, Notion loading/selection/create page, video picker/import, refresh/settings actions, progress summaries, and Notion Archive shortcut.

- [ ] **Step 1: Give the destination switch a named hierarchy**

Replace the unlabeled top picker wrapper with:

```swift
VStack(alignment: .leading, spacing: WorkspaceStyle.spacing8) {
    WorkspaceSectionLabel("Send to")
    Picker("Destination", selection: $state.exportDestination) {
        Label("Personal Wiki", systemImage: "books.vertical")
            .tag(AppState.ExportDestination.wiki)
        Label("Notion", systemImage: "square.grid.2x2")
            .tag(AppState.ExportDestination.notion)
    }
    .pickerStyle(.segmented)
    .labelsHidden()
}
.padding(.horizontal, WorkspaceStyle.spacing16)
.padding(.vertical, WorkspaceStyle.spacing12)
```

Keep the same enum tags and switch branches.

- [ ] **Step 2: Restructure Wiki setup into two quiet sections**

Use one inset surface for `Personal Wiki` containing the current vault path, change/choose action, and concise raw-path explanation. Use a second inset surface for `Transcription` containing the existing video-attachment toggle, import action, and on-device explanation. Do not change picker calls, bindings, disabled conditions, or `Task` creation.

Use exact destination copy:

```text
Notes land in raw/journal; screenshots and media land in raw/assets.
```

- [ ] **Step 3: Restyle Notion states and rows**

Keep the connected workspace, new-page action, root list, recursive children, selection indicator, and loading spinner. Replace only the disconnected/no-pages visual wrappers with `WorkspaceEmptyState`; keep the existing instructional copy. Add comfortable vertical padding to Notion rows without changing their tap action.

- [ ] **Step 4: Clarify toolbar controls without changing commands**

Keep the mode picker, principal progress, reload, settings, and destination-gated Archive button. Add `.help("Settings")` to the gear button and keep `.help("Reload both panes")`. Give the mode picker a stable width near 170 points. Keep the existing keyboard shortcut and disabled expressions byte-for-byte.

Set Capture split widths to source `min: 300, ideal: 390` and destination `min: 340, ideal: 440`; keep `NavigationSplitView` and window size constraints.

- [ ] **Step 5: Verify destination and toolbar independently**

Run `swift build` and `git diff --check`. Confirm the diff contains no changes to picker handlers, service calls, selection IDs, keyboard commands, or progress calculations. Launch Capture and switch Wiki/Notion without creating pages, choosing files, or exporting.

---

### Task 5: Settings and Confirmation Sheets

**Files:**
- Modify: `Sources/AppleNotestoX/UI/SettingsView.swift`
- Modify: `Sources/AppleNotestoX/UI/PreviewSheet.swift`

**Interfaces:**
- Consumes: Task 1 presentation helpers.
- Preserves: token draft/save/clear, workspace status, permission deep link, review-folder override, archive disposition, archive progress, dismiss behavior, and all keyboard shortcuts.

- [ ] **Step 1: Convert Settings to a native grouped form**

Keep `draft`, `reviewDraft`, all bindings, and every action. Place the three existing concerns into labeled `Form` sections:

```swift
Form {
    Section("Notion") {
        Text("Create an integration at notion.so/profile/integrations. The secret stays in macOS Keychain.")
            .font(.caption)
            .foregroundStyle(.secondary)
        SecureField("secret_...", text: $draft)
            .onAppear { draft = state.token }
        if let workspaceName = state.workspaceName {
            Label("Connected to \(workspaceName)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
    Section("Apple Notes") {
        Text("macOS controls permission to read Notes through Automation settings.")
            .font(.caption)
            .foregroundStyle(.secondary)
        Button("Open Privacy & Security") {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    Section("Review") {
        Text("Leave the advanced folder blank to use the bundled review app.")
            .font(.caption)
            .foregroundStyle(.secondary)
        HStack {
            TextField("~/Projects/AppleNotestoX/review", text: $reviewDraft)
                .onChange(of: reviewDraft) { _, value in
                    UserDefaults.standard.set(
                        value.trimmingCharacters(in: .whitespacesAndNewlines),
                        forKey: RepoPaths.reviewFolderOverrideKey
                    )
                }
            Button("Choose...") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                if panel.runModal() == .OK, let url = panel.url { reviewDraft = url.path }
            }
        }
    }
}
.formStyle(.grouped)
```

Use `.safeAreaInset(edge: .bottom)` for the existing Clear/Cancel/Save action row on a regular material background. Keep the destructive role, Escape/Return shortcuts, save trimming, and disabled expression unchanged. Increase the sheet to approximately 520x440 so help copy does not crowd controls.

- [ ] **Step 2: Restyle the permission sheet**

Use the same empty-state hierarchy with the lock-shield icon, a concise title, the existing explanatory text, and the existing Open System Settings/Retry actions. Keep Retry as the default Return action and do not change the permission state mutation or async reload.

- [ ] **Step 3: Restyle archive confirmation**

Keep the selected-note list, destination title, three disposition choices, cancel/archive actions, progress lookup, status icons, and archive `Task` unchanged. Improve hierarchy with:

- a title plus destination summary header;
- comfortable note-row spacing;
- an inset `After successful archive` section; and
- a material-backed footer action row.

Do not replace the current radio-style disposition semantics or destructive wording.

- [ ] **Step 4: Verify settings and sheets independently**

Run `swift build` and `git diff --check`. Open Settings and close it without saving. Open archive confirmation only if a destination and disposable test selection already exist; otherwise use static inspection and do not alter user data.

---

### Task 6: Whole-App Visual and Behavioral Verification

**Files:**
- Verify all files from Tasks 1-5.
- Update no production file unless a verification finding requires a focused fix.

**Interfaces:**
- Consumes: the completed editorial workspace presentation.
- Produces: verification evidence and a final review verdict.

- [ ] **Step 1: Run fresh compilation and behavior gates**

Run:

```bash
swift build
swiftc "Sources/AppleNotestoX/Models/AppleNotesModels.swift" \
  "Sources/AppleNotestoX/Services/AppleNoteSearch.swift" \
  "/var/folders/7p/dmlnmy3554z494fwhnbjyk340000gn/T/opencode/AppleNoteSearchHarness.swift" \
  -o "/var/folders/7p/dmlnmy3554z494fwhnbjyk340000gn/T/opencode/apple-note-search-harness-redesign" && \
  "/var/folders/7p/dmlnmy3554z494fwhnbjyk340000gn/T/opencode/apple-note-search-harness-redesign"
swiftc "Sources/AppleNotestoX/Models/WikiExport.swift" \
  "Sources/AppleNotestoX/Models/PersonalWikiActionState.swift" \
  "/var/folders/7p/dmlnmy3554z494fwhnbjyk340000gn/T/opencode/personal_wiki_action_state_harness.swift" \
  -o "/var/folders/7p/dmlnmy3554z494fwhnbjyk340000gn/T/opencode/personal-wiki-action-state-redesign" && \
  "/var/folders/7p/dmlnmy3554z494fwhnbjyk340000gn/T/opencode/personal-wiki-action-state-redesign"
git diff --check
```

Expected: build and both harnesses exit 0; diff check has no output.

- [ ] **Step 2: Record the XCTest environment limitation**

Run each focused suite:

```bash
swift test --filter AppleNoteSearchTests
swift test --filter PersonalWikiActionStateTests
swift test --filter AppStateSearchTests
```

Expected locally: compilation stops at `no such module 'XCTest'`. Preserve all tests for Xcode/CI; do not weaken or remove them.

- [ ] **Step 3: Inspect default and minimum window layouts**

Launch `swift run AppleNotestoX` without exporting, refreshing Study, importing video, or mutating Notes. Inspect Study and Capture at:

- default 1100x700;
- minimum 900x600; and
- a wider window to verify split growth.

Capture local screenshots for design inspection without publishing personal note content. Verify hierarchy, clipping, long paths/titles, empty space, one-primary-action emphasis, native focus rings, and light/dark adaptation where available.

- [ ] **Step 4: Run safe interactive acceptance**

Verify:

1. Command-F enters Capture and focuses search.
2. Escape clears a query, then releases focus.
3. Selecting and deselecting a note updates the badge/footer without exporting.
4. Switching Wiki/Notion changes the destination surface and Command-Return owner.
5. Cancelling the vault picker performs no export.
6. Settings opens, preserves existing values, and closes without saving.
7. Pane resizing remains legible at minimum width.

- [ ] **Step 5: Request final code and design review**

Provide the approved spec, this plan, full working diff, build/harness evidence, screenshot observations, and known XCTest limitation to a fresh reviewer. Fix all Critical and Important findings, re-run the covering gates, and require a final `READY` verdict.

- [ ] **Step 6: Update the durable ledger**

Append the redesign task status, verification commands/results, residual risks, and current uncommitted branch state to `.superpowers/sdd/progress.md`. Do not commit, merge, or push without explicit user instruction.
