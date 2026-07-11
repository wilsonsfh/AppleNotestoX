# Editorial Workspace Redesign

**Date:** 2026-07-12
**Status:** Approved for implementation

## Design Read

AppleNotestoX is a native macOS capture and study utility for one personal knowledge worker. It should feel calm, focused, and unmistakably actionable. The redesign must preserve the existing SwiftUI split-view foundation, verified search and export behavior, macOS 14 support, accessibility, Notion compatibility, and data-safety gates.

## Direction

Use an **Editorial Split Desk** direction: quiet system-adaptive surfaces, comfortable information density, restrained use of the macOS accent color, and limited serif display typography. The interface should feel like one coherent knowledge workspace rather than a collection of default SwiftUI panes.

Rejected alternatives:

- **Immersive Studio Canvas:** too visually heavy for repeated capture work.
- **Compact Pro Utility:** efficient, but inconsistent with the approved calm editorial character.

## Goals

- Create one visual system across Study, Capture, settings, and sheets.
- Make the primary action obvious without hiding secondary workflows.
- Improve hierarchy, spacing, typography, and state presentation.
- Keep the interface native, keyboard-first, and comfortable at 900x600.
- Preserve every verified search, selection, export, study, Notion, and permission behavior.

## Non-Goals

- Changing the product model, navigation model, or data flow.
- Adding new capture sources or study features.
- Adding custom animation, gestures, dependencies, or custom fonts.
- Replacing native controls with a bespoke component framework.
- Running a real export or mutating Apple Notes or wiki data during verification.

## Visual Foundation

### Typography

- Use San Francisco and semantic system text styles for controls, lists, labels, and body copy.
- Reserve the system serif design for Study's heading and key empty-state headings; keep metrics in San Francisco with tabular figures.
- Replace repeated all-caps labels with small semibold section labels where possible.
- Use monospaced digits only for counts, dates, and progress.

### Color and Materials

- Use system-adaptive window, under-page, control, and separator colors.
- Use the user's macOS accent color for selection and the single primary action.
- Reserve green, orange, and red for success, warning, and error states.
- Prefer a hairline border or material separation over shadows.
- Support light and dark appearance without separate hard-coded palettes.

### Spacing and Shape

- Use an 8-point spacing rhythm.
- Default to 12-point row spacing, 16-point section spacing, and 24-point page insets.
- Use one restrained corner-radius scale for inset supporting surfaces.
- Avoid nested cards, decorative gradients, and oversized empty padding.

## Shared UI Building Blocks

Add `WorkspaceStyle.swift` to hold reusable metrics and small view treatments:

- spacing and corner-radius constants;
- adaptive inset and footer surfaces;
- section-label treatment;
- compact count/status badge treatment; and
- consistent empty-state layout.

These are presentation-only helpers. They must not own business state or actions.

## Study Surface

- Keep Study as the default mode and retain the current hero-plus-backlog structure.
- Give Study one serif heading, then present the concept count in San Francisco with cards and links as a compact supporting line.
- Rank `Launch Wiki Review` as the primary action and `Refresh` as secondary.
- Present recent concepts as quiet, wrapping topic chips without making each chip a card.
- Treat the synthesis backlog as a subdued supporting rail with a count badge, readable rows, and explicit empty state.
- Preserve vault setup, refresh, launch, folder reveal, and copy-prompt behavior.

## Capture Surface

### Source Pane

- Keep the title, selected count, search, folder hierarchy, flat search results, and persistent Personal Wiki footer.
- Use a compact selected-count badge instead of low-emphasis trailing prose.
- Give search a clear inset position beneath the header.
- Increase row breathing room while preserving the visible note count.
- Keep note title, optional folder path, modified date, archive status, full-row hit target, and checkbox semantics.
- Put the footer on a subtle material-backed surface and make its one available next action span the usable width.

### Destination Pane

- Label the destination control as `Send to` and keep the Wiki/Notion segmented switch.
- Show current vault or Notion connection as the first configuration section.
- Keep note export explanation concise and specific to `raw/journal` and `raw/assets`.
- Group transcription options together and keep video import visually secondary.
- Preserve create-page, destination selection, token-empty, no-pages, vault picker, video import, and all disabled states.

## Toolbar and Window

- Preserve the Study/Capture mode switch, refresh, settings, progress summary, and Notion Archive action.
- Keep destination-specific Command-Return ownership and Command-F behavior unchanged.
- Use concise help text for icon-only toolbar controls.
- Keep the 900x600 minimum and 1100x700 default window sizes.
- Adjust split-view ideal widths only when required for the comfortable density target.

## Settings and Sheets

- Restyle Settings as a native sectioned form with aligned labels, concise help, and a clear footer action row.
- Preserve token storage, clear/save behavior, permission deep link, and review-folder override.
- Apply the same typography, spacing, and status treatments to archive confirmation and permission sheets.
- Preserve all keyboard shortcuts, destructive roles, disabled states, and progress rows.

## States and Copy

Provide consistent visual treatment for:

- Apple Notes loading, unavailable, and search-empty states;
- empty or disconnected Notion states;
- missing vault and missing study-data states;
- note export selection, vault setup, ready, running, success, and partial failure;
- synthesis backlog empty and populated states; and
- permission and global error states.

Status must always use text plus icon where an icon is present. Color alone is insufficient.

## Accessibility and Interaction

- Preserve native focus rings and semantic controls.
- Preserve Command-F, Escape, Command-Return, full-row selection, and destination-specific shortcut behavior.
- Keep VoiceOver labels for note title, folder context, archive state, selection state, and export progress.
- Keep primary and secondary actions distinguishable without relying only on color.
- Do not add custom motion. Native control transitions are sufficient and respect system preferences.

## Architecture and Change Locality

The redesign is surface-only. Expected files:

- Create `Sources/AppleNotestoX/UI/WorkspaceStyle.swift`.
- Modify `ContentView.swift`, `StudyView.swift`, `SourcePane.swift`, `DestinationPane.swift`, `SettingsView.swift`, and `PreviewSheet.swift`.
- Modify the permission sheet in `SettingsView.swift`.

Do not modify search filtering, selection reducers, export coordination, persistence, services, or data models unless compilation exposes a concrete presentation dependency.

## Verification

### Automated and Static

- Run `swift build` and require exit 0.
- Run all existing standalone search, footer-state, and AppState harnesses.
- Run `git diff --check`.
- Attempt the three focused XCTest suites; document the known missing-XCTest limitation locally and run under Xcode/CI when available.
- Request a final code review for behavior regressions, accessibility, and scope.

### Visual and Interactive

- Launch the native app without performing a real export.
- Capture and inspect Study and Capture at 900x600 and 1100x700 in light appearance; inspect dark appearance when the environment permits.
- Verify Command-F focus, Escape clearing, destination-specific Command-Return, picker cancellation, pane resizing, and full-row note selection.
- Verify loading, empty, ready, running, completion, and error presentations using safe state inspection or previews where available.

## Success Criteria

- Study and Capture read as one calm editorial workspace.
- Each screen has one obvious primary action and clearly quieter secondary actions.
- The interface remains comfortable and legible at the minimum window size.
- Search, selection, export, Notion, study, settings, and permission behavior remain unchanged.
- Build, harnesses, diff review, code review, and available interactive checks pass.
