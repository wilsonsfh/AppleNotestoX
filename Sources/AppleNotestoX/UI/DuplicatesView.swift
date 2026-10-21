import SwiftUI

struct DuplicatesView: View {
    @Environment(AppState.self) private var state
    @State private var showDeleteConfirmation = false

    var body: some View {
        @Bindable var state = state

        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .task { if state.vaultURL != nil, state.duplicateGroups.isEmpty { await state.scanForDuplicates() } }
        .sheet(item: diffSheetBinding) { entries in
            DuplicateDiffSheet(old: entries.old, new: entries.new, onClose: { state.closeDiff() })
        }
    }

    /// Adapts `AppState.duplicateDiffEntries` (a plain tuple, so it can't
    /// conform to `Identifiable` itself) into a `.sheet(item:)` binding.
    private var diffSheetBinding: Binding<DiffEntries?> {
        Binding(
            get: { state.duplicateDiffEntries.map { DiffEntries(old: $0.old, new: $0.new) } },
            set: { if $0 == nil { state.closeDiff() } }
        )
    }

    private var header: some View {
        HStack(spacing: WorkspaceStyle.spacing8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Duplicate Exports")
                    .font(.title3.weight(.semibold))
                Text("Notes with more than one file in raw/apple-notes/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: WorkspaceStyle.spacing8)
            if state.isScanningDuplicates {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await state.scanForDuplicates() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Rescan for duplicates")
                .disabled(state.vaultURL == nil)
            }
        }
        .padding(.horizontal, WorkspaceStyle.spacing16)
        .padding(.vertical, WorkspaceStyle.spacing12)
    }

    @ViewBuilder private var content: some View {
        if state.vaultURL == nil {
            chooseVaultState
        } else if let error = state.duplicateScanError {
            WorkspaceEmptyState(
                systemImage: "exclamationmark.triangle",
                title: "Scan Failed",
                message: error
            )
        } else if state.isScanningDuplicates && state.duplicateGroups.isEmpty && state.possibleDuplicatePairs.isEmpty {
            VStack(spacing: WorkspaceStyle.spacing8) {
                ProgressView()
                Text("Scanning raw/apple-notes/…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if state.duplicateGroups.isEmpty && state.possibleDuplicatePairs.isEmpty {
            WorkspaceEmptyState(
                systemImage: "checkmark.circle",
                title: "No Duplicates Found",
                message: "Every exported note has exactly one file in raw/apple-notes/, and no notes' content closely overlaps."
            )
        } else {
            duplicateList
        }
    }

    private var chooseVaultState: some View {
        VStack(spacing: WorkspaceStyle.spacing8) {
            WorkspaceEmptyState(
                systemImage: "folder.badge.questionmark",
                title: "No Personal Wiki Chosen",
                message: "Choose your Personal Wiki folder to scan it for duplicate exports."
            )
            Button {
                if let url = pickVaultDirectory() {
                    state.chooseVault(url)
                    Task { await state.scanForDuplicates() }
                }
            } label: {
                Label("Choose Personal Wiki…", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var duplicateList: some View {
        List {
            if !state.duplicateGroups.isEmpty {
                Section {
                    ForEach(state.duplicateGroups) { group in
                        Section {
                            ForEach(group.entries, id: \.markdownPath) { entry in
                                DuplicateEntryRow(
                                    entry: entry,
                                    isNewest: entry.markdownPath == group.entries.first?.markdownPath,
                                    compareTarget: entry.markdownPath == group.entries.first?.markdownPath
                                        ? nil : group.entries.first
                                )
                            }
                        } header: {
                            Text(group.displayTitle)
                        }
                    }
                } header: {
                    Text("Same Note, Multiple Files")
                }
            }
            if !state.possibleDuplicatePairs.isEmpty {
                Section {
                    ForEach(state.possibleDuplicatePairs) { pair in
                        PossibleDuplicatePairRow(pair: pair)
                    }
                } header: {
                    Text("Possibly Duplicate Content")
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var selectedCount: Int { state.selectedDuplicatePaths.count }

    @ViewBuilder private var footer: some View {
        HStack {
            if !state.duplicateGroups.isEmpty {
                Text("\(selectedCount) file\(selectedCount == 1 ? "" : "s") selected for removal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showDeleteConfirmation = true
            } label: {
                Text(state.isDeletingDuplicates ? "Deleting…" : "Delete Selected")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedCount == 0 || state.isDeletingDuplicates)
        }
        .workspaceFooterSurface()
        .confirmationDialog(
            "Delete \(selectedCount) duplicate file\(selectedCount == 1 ? "" : "s")?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                Task { await state.deleteSelectedDuplicates() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The selected files (and any images only they reference) move to the Trash, not permanently deleted.")
        }
    }
}

private struct DuplicateEntryRow: View {
    @Environment(AppState.self) private var state
    let entry: WikiVaultIndex.Entry
    let isNewest: Bool
    /// The entry to diff this one against, when there's something worth
    /// comparing (i.e. this isn't the group's kept/newest file).
    var compareTarget: WikiVaultIndex.Entry?

    private var isSelected: Bool { state.selectedDuplicatePaths.contains(entry.markdownPath) }

    var body: some View {
        HStack(spacing: WorkspaceStyle.spacing8) {
            Button {
                state.toggleDuplicateSelection(entry.markdownPath)
            } label: {
                HStack(spacing: WorkspaceStyle.spacing8) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.markdownPath.lastPathComponent)
                            .lineLimit(1)
                        Text("Modified \(entry.noteModifiedDay)" + (entry.exportedDay.map { " · Exported \($0)" } ?? ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isNewest {
                        WorkspaceBadge(text: "Newest", tint: .green)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(entry.markdownPath.lastPathComponent), \(isSelected ? "selected for removal" : "not selected")\(isNewest ? ", newest export" : "")")

            if let compareTarget {
                Button {
                    state.showDiff(old: entry, new: compareTarget)
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .buttonStyle(.borderless)
                .help("Compare with \(compareTarget.markdownPath.lastPathComponent)")
            }
        }
    }
}

private struct PossibleDuplicatePairRow: View {
    @Environment(AppState.self) private var state
    let pair: WikiDuplicateFinder.PossibleDuplicatePair

    private var percent: Int { Int((pair.similarity * 100).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: WorkspaceStyle.spacing8) {
            HStack {
                WorkspaceBadge(text: "\(percent)% match", tint: .orange)
                Spacer()
                Button {
                    state.showDiff(old: pair.entryA, new: pair.entryB)
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .buttonStyle(.borderless)
                .help("Compare the two notes")
            }
            DuplicateEntryRow(entry: pair.entryA, isNewest: false)
            DuplicateEntryRow(entry: pair.entryB, isNewest: false)
        }
        .padding(.vertical, 2)
    }
}

private struct DiffEntries: Identifiable {
    let old: WikiVaultIndex.Entry
    let new: WikiVaultIndex.Entry
    var id: String { old.markdownPath.path + "|" + new.markdownPath.path }
}

private struct DuplicateDiffSheet: View {
    let old: WikiVaultIndex.Entry
    let new: WikiVaultIndex.Entry
    let onClose: () -> Void

    private var lines: [TextDiff.Line] { TextDiff.diff(old: old.content, new: new.content) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Compare Versions")
                        .font(.title3.weight(.semibold))
                    Text("\(old.markdownPath.lastPathComponent) → \(new.markdownPath.lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close", action: onClose)
            }
            .padding(WorkspaceStyle.spacing16)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        DiffLineRow(line: line)
                    }
                }
                .padding(WorkspaceStyle.spacing12)
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}

private struct DiffLineRow: View {
    let line: TextDiff.Line

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(marker)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .background(background)
    }

    private var marker: String {
        switch line {
        case .unchanged: return " "
        case .added: return "+"
        case .removed: return "-"
        }
    }

    private var text: String {
        switch line {
        case .unchanged(let text), .added(let text), .removed(let text): return text
        }
    }

    private var background: Color {
        switch line {
        case .unchanged: return .clear
        case .added: return Color.green.opacity(0.15)
        case .removed: return Color.red.opacity(0.15)
        }
    }
}
