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
    }

    private var header: some View {
        HStack(spacing: WorkspaceStyle.spacing8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Duplicate Exports")
                    .font(.title3.weight(.semibold))
                Text("Notes with more than one file in raw/journal/")
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
        } else if state.isScanningDuplicates && state.duplicateGroups.isEmpty {
            VStack(spacing: WorkspaceStyle.spacing8) {
                ProgressView()
                Text("Scanning raw/journal/…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if state.duplicateGroups.isEmpty {
            WorkspaceEmptyState(
                systemImage: "checkmark.circle",
                title: "No Duplicates Found",
                message: "Every exported note has exactly one file in raw/journal/."
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
            ForEach(state.duplicateGroups) { group in
                Section {
                    ForEach(group.entries, id: \.markdownPath) { entry in
                        DuplicateEntryRow(entry: entry, isNewest: entry.markdownPath == group.entries.first?.markdownPath)
                    }
                } header: {
                    Text(group.displayTitle)
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

    private var isSelected: Bool { state.selectedDuplicatePaths.contains(entry.markdownPath) }

    var body: some View {
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
    }
}
