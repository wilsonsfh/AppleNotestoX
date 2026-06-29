import SwiftUI

struct PreviewSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var disposition: PostArchiveDisposition = .leave

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Confirm archive")
                .font(.title2).bold()
                .padding(.top, 16)
                .padding(.horizontal, 20)

            if let h = state.hierarchy {
                let selected = state.selectedNoteIDs.compactMap { h.notes[$0] }
                let destTitle = destinationTitle()
                Group {
                    Text("\(selected.count) note(s) → \(destTitle)")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)

                Divider().padding(.vertical, 8)

                List {
                    ForEach(selected, id: \.id) { note in
                        if let progress = progressFor(note.id) {
                            ProgressRow(progress: progress)
                        } else {
                            HStack {
                                Image(systemName: "doc.text").foregroundStyle(.secondary)
                                Text(note.name)
                                Spacer()
                            }
                        }
                    }
                }
                .frame(minHeight: 200, maxHeight: 320)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("After successful archive").font(.subheadline).bold()
                    ForEach(PostArchiveDisposition.allCases) { option in
                        HStack {
                            Image(systemName: disposition == option ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(disposition == option ? .blue : .secondary)
                            Text(option.label)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { disposition = option }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            } else {
                Text("Apple Notes hierarchy not loaded.").padding()
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                    .disabled(state.isArchiving)
                Button(state.isArchiving ? "Archiving…" : "Archive") {
                    Task {
                        await state.runArchive(disposition: disposition)
                    }
                }
                .keyboardShortcut(.return)
                .disabled(state.isArchiving || state.selectedNoteIDs.isEmpty || state.selectedNotionPageID == nil)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 520)
    }

    private func destinationTitle() -> String {
        guard let id = state.selectedNotionPageID else { return "(none)" }
        if let root = state.notionRoots.first(where: { $0.id == id }) { return root.title }
        for kids in state.notionChildren.values {
            if let p = kids.first(where: { $0.id == id }) { return p.title }
        }
        return id.prefix(8) + "…"
    }

    private func progressFor(_ noteID: String) -> NoteArchiveProgress? {
        state.archiveProgress.first(where: { $0.id == noteID })
    }
}

private struct ProgressRow: View {
    let progress: NoteArchiveProgress

    var body: some View {
        HStack {
            statusIcon
            Text(progress.title)
            Spacer()
            Text(statusText).font(.caption).foregroundStyle(.secondary)
        }
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
        case .fetching: return "reading note…"
        case .converting: return "converting…"
        case .uploadingImages(let d, let t): return "uploading \(d)/\(t) images…"
        case .writingBlocks: return "writing to Notion…"
        case .dispositioning: return "tidying source…"
        case .done: return "done"
        case .failed(let m): return "failed: \(m)"
        }
    }
}

private extension View {
    var asAny: AnyView { AnyView(self) }
}
