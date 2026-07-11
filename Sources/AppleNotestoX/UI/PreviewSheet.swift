import SwiftUI

struct PreviewSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var disposition: PostArchiveDisposition = .leave

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: WorkspaceStyle.spacing4) {
                        Text("Confirm Archive")
                            .font(.title2.weight(.semibold))
                        if let h = state.hierarchy {
                            let selected = state.selectedNoteIDs.compactMap { h.notes[$0] }
                            let destTitle = destinationTitle()
                            Text("\(selected.count) note\(selected.count == 1 ? "" : "s") \u{2192} \(destTitle)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, WorkspaceStyle.spacing16)
                    .padding(.top, WorkspaceStyle.spacing16)
                    .padding(.bottom, WorkspaceStyle.spacing12)

                    Divider()

                    if let h = state.hierarchy {
                        let selected = state.selectedNoteIDs.compactMap { h.notes[$0] }
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(selected, id: \.id) { note in
                                if let progress = progressFor(note.id) {
                                    ProgressRow(progress: progress)
                                        .padding(.horizontal, WorkspaceStyle.spacing16)
                                        .padding(.vertical, WorkspaceStyle.spacing8)
                                } else {
                                    HStack(spacing: WorkspaceStyle.spacing8) {
                                        Image(systemName: "doc.text")
                                            .foregroundStyle(.secondary)
                                            .accessibilityHidden(true)
                                        Text(note.name)
                                            .lineLimit(2)
                                            .help(note.name)
                                        Spacer()
                                    }
                                    .padding(.horizontal, WorkspaceStyle.spacing16)
                                    .padding(.vertical, WorkspaceStyle.spacing8)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(note.name)
                                }
                            }
                        }
                    } else {
                        Text("Apple Notes hierarchy not loaded.")
                            .foregroundStyle(.secondary)
                            .padding(WorkspaceStyle.spacing16)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: WorkspaceStyle.spacing8) {
                        Picker("After successful archive", selection: $disposition) {
                            ForEach(PostArchiveDisposition.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .pickerStyle(.radioGroup)
                    }
                    .padding(.horizontal, WorkspaceStyle.spacing16)
                    .padding(.top, WorkspaceStyle.spacing12)
                    .padding(.bottom, WorkspaceStyle.spacing12)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                    .disabled(state.isArchiving)
                if disposition == .delete {
                    Button(role: .destructive) {
                        Task {
                            await state.runArchive(disposition: disposition)
                        }
                    } label: {
                        Text(state.isArchiving ? "Archiving\u{2026}" : "Archive and Delete Original")
                    }
                    .keyboardShortcut(.return)
                    .disabled(state.isArchiving || state.selectedNoteIDs.isEmpty || state.selectedNotionPageID == nil)
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        Task {
                            await state.runArchive(disposition: disposition)
                        }
                    } label: {
                        Text(state.isArchiving ? "Archiving\u{2026}" : "Archive")
                    }
                    .keyboardShortcut(.return)
                    .disabled(state.isArchiving || state.selectedNoteIDs.isEmpty || state.selectedNotionPageID == nil)
                    .buttonStyle(.borderedProminent)
                }
            }
            .workspaceFooterSurface()
        }
        .frame(width: 520, height: 480)
    }

    private func destinationTitle() -> String {
        guard let id = state.selectedNotionPageID else { return "(none)" }
        if let root = state.notionRoots.first(where: { $0.id == id }) { return root.title }
        for kids in state.notionChildren.values {
            if let p = kids.first(where: { $0.id == id }) { return p.title }
        }
        return id.prefix(8) + "\u{2026}"
    }

    private func progressFor(_ noteID: String) -> NoteArchiveProgress? {
        state.archiveProgress.first(where: { $0.id == noteID })
    }
}

private struct ProgressRow: View {
    let progress: NoteArchiveProgress

    var body: some View {
        HStack(spacing: WorkspaceStyle.spacing8) {
            statusIcon
            Text(progress.title)
                .lineLimit(2)
                .help(progress.title)
            Spacer()
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(progress.title), \(statusText)")
    }

    private var statusIcon: some View {
        switch progress.status {
        case .pending:
            return Image(systemName: "circle.dotted").foregroundStyle(.secondary).asAny
        case .done:
            return Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).asAny
        case .failed:
            return Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).asAny
        default:
            return ProgressView().controlSize(.small).asAny
        }
    }

    private var statusText: String {
        switch progress.status {
        case .pending: return "queued"
        case .fetching: return "reading note\u{2026}"
        case .converting: return "converting\u{2026}"
        case .uploadingImages(let d, let t): return "uploading \(d)/\(t) images\u{2026}"
        case .writingBlocks: return "writing to Notion\u{2026}"
        case .dispositioning: return "tidying source\u{2026}"
        case .done: return "done"
        case .failed(let m): return "failed: \(m)"
        }
    }
}

private extension View {
    var asAny: AnyView { AnyView(self) }
}
