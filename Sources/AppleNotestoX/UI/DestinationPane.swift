import SwiftUI

struct DestinationPane: View {
    @Environment(AppState.self) private var state
    @State private var showCreatePage = false
    @State private var newPageTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Notion").font(.headline)
                if let ws = state.workspaceName {
                    Text("· \(ws)").foregroundStyle(.secondary).font(.caption)
                }
                Spacer()
                if state.loadingNotion {
                    ProgressView().controlSize(.small)
                }
                if state.selectedNotionPageID != nil {
                    Button {
                        showCreatePage = true
                        newPageTitle = ""
                    } label: {
                        Label("New page", systemImage: "plus.square")
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if state.token.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "key.horizontal").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Add your Notion integration token in Settings.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else if state.notionRoots.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Text("No pages shared with this integration yet.")
                        .foregroundStyle(.secondary)
                    Text("In Notion: open a page → Connect to integration → select your integration.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Spacer()
            } else {
                List {
                    ForEach(state.notionRoots) { root in
                        NotionPageRow(page: root)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .sheet(isPresented: $showCreatePage) {
            CreatePageSheet(
                title: $newPageTitle,
                onCancel: { showCreatePage = false },
                onConfirm: {
                    let parentID = state.selectedNotionPageID
                    let title = newPageTitle
                    showCreatePage = false
                    Task {
                        if let parent = parentID, !title.isEmpty {
                            _ = await state.createNotionSubPage(parentID: parent, title: title)
                        }
                    }
                }
            )
        }
    }
}

private struct NotionPageRow: View {
    @Environment(AppState.self) private var state
    let page: NotionPage

    var body: some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { state.expandedNotionIDs.contains(page.id) },
                set: { v in
                    Task {
                        if v && !state.expandedNotionIDs.contains(page.id) {
                            await state.toggleNotionExpansion(page.id)
                        } else if !v {
                            await state.toggleNotionExpansion(page.id)
                        }
                    }
                }
            )
        ) {
            if let kids = state.notionChildren[page.id] {
                ForEach(kids) { child in
                    NotionPageRow(page: child)
                }
                if kids.isEmpty {
                    Text("(no sub-pages)").font(.caption).foregroundStyle(.tertiary)
                }
            } else if state.loadingNotionPageID == page.id {
                HStack { ProgressView().controlSize(.small); Text("loading…").font(.caption).foregroundStyle(.tertiary) }
            }
        } label: {
            HStack {
                Image(systemName: "doc.text.fill").foregroundStyle(.secondary)
                Text(page.title)
                Spacer()
                if state.selectedNotionPageID == page.id {
                    Image(systemName: "scope").foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { state.selectedNotionPageID = page.id }
        }
    }
}

private struct CreatePageSheet: View {
    @Binding var title: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create new Notion sub-page").font(.headline)
            TextField("Page title", text: $title)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.escape)
                Button("Create", action: onConfirm)
                    .keyboardShortcut(.return)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
