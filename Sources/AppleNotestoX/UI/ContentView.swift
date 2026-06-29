import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var showSettings = false
    @State private var showPreview = false

    var body: some View {
        @Bindable var state = state

        NavigationSplitView {
            SourcePane()
                .navigationSplitViewColumnWidth(min: 280, ideal: 360)
        } detail: {
            DestinationPane()
                .navigationSplitViewColumnWidth(min: 320, ideal: 420)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                if state.isArchiving {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(progressLabel)
                    }
                } else if !state.archiveProgress.isEmpty {
                    Text(summaryLabel).foregroundStyle(.secondary)
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await state.loadAppleHierarchy(); await state.verifyAndLoadNotion() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload both panes")

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gear")
                }

                Button("Archive…") { showPreview = true }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(state.selectedNoteIDs.isEmpty || state.selectedNotionPageID == nil || state.isArchiving)
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showPreview) { PreviewSheet() }
        .sheet(isPresented: $state.permissionDeniedSheet) { PermissionDeniedSheet() }
        .alert("Error", isPresented: .constant(state.errorMessage != nil)) {
            Button("OK") { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }

    private var progressLabel: String {
        let total = state.archiveProgress.count
        let done = state.archiveProgress.filter {
            if case .done = $0.status { return true } else { return false }
        }.count
        return "Archiving \(done + 1)/\(total)"
    }

    private var summaryLabel: String {
        let total = state.archiveProgress.count
        let done = state.archiveProgress.filter {
            if case .done = $0.status { return true } else { return false }
        }.count
        let failed = state.archiveProgress.filter {
            if case .failed = $0.status { return true } else { return false }
        }.count
        if failed == 0 { return "✓ Archived \(done)/\(total)" }
        return "Archived \(done)/\(total) — \(failed) failed"
    }
}
