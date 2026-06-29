import SwiftUI

struct SourcePane: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Apple Notes").font(.headline)
                Spacer()
                if state.loadingApple {
                    ProgressView().controlSize(.small)
                }
                Text("\(state.selectedNoteIDs.count) selected")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if let h = state.hierarchy {
                List {
                    ForEach(h.rootFolderIDs.compactMap { h.folders[$0] }, id: \.id) { folder in
                        AppleFolderRow(folder: folder, hierarchy: h, depth: 0)
                    }
                }
                .listStyle(.sidebar)
            } else if state.loadingApple {
                Spacer()
                ProgressView("Reading Apple Notes…")
                Spacer()
            } else {
                Spacer()
                Text("No Apple Notes data.").foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}

private struct AppleFolderRow: View {
    @Environment(AppState.self) private var state
    let folder: AppleFolder
    let hierarchy: AppleNotesHierarchy
    let depth: Int

    var body: some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { state.expandedFolderIDs.contains(folder.id) },
                set: { v in
                    if v { state.expandedFolderIDs.insert(folder.id) }
                    else { state.expandedFolderIDs.remove(folder.id) }
                }
            )
        ) {
            ForEach(folder.childFolderIDs.compactMap { hierarchy.folders[$0] }, id: \.id) { child in
                AppleFolderRow(folder: child, hierarchy: hierarchy, depth: depth + 1)
            }
            ForEach(folder.noteIDs.compactMap { hierarchy.notes[$0] }, id: \.id) { note in
                AppleNoteRow(note: note)
            }
        } label: {
            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(folder.name)
                Spacer()
                let count = folder.noteIDs.count
                if count > 0 {
                    Text("\(count)").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

private struct AppleNoteRow: View {
    @Environment(AppState.self) private var state
    let note: AppleNote

    private var isSelected: Bool { state.selectedNoteIDs.contains(note.id) }
    private var isArchived: Bool { state.archivedNoteIDs.contains(note.id) }

    var body: some View {
        HStack {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .foregroundStyle(isSelected ? .blue : .secondary)
            Image(systemName: "doc.text").foregroundStyle(.secondary)
            Text(note.name)
                .lineLimit(1)
            if isArchived {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .help("Already archived previously")
            }
            Spacer()
            Text(relativeDate(note.modifiedAt))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected { state.selectedNoteIDs.remove(note.id) }
            else { state.selectedNoteIDs.insert(note.id) }
        }
    }

    private func relativeDate(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }
}
