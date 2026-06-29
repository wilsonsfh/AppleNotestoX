import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings").font(.title2).bold()

            VStack(alignment: .leading, spacing: 6) {
                Text("Notion integration token").font(.subheadline).bold()
                Text("Create at notion.so/profile/integrations → copy the secret. The token is stored in the macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("secret_…", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onAppear { draft = state.token }
                if let ws = state.workspaceName {
                    Text("Connected: \(ws)").font(.caption).foregroundStyle(.green)
                }
            }

            Divider().padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("Apple Notes permission").font(.subheadline).bold()
                Text("On first archive, macOS will prompt you to grant Notes automation permission.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open System Settings → Privacy & Security") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }

            Spacer()

            HStack {
                Button("Clear token", role: .destructive) {
                    Task {
                        await state.clearToken()
                        draft = ""
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Button("Save") {
                    Task {
                        await state.saveToken(draft.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                }
                .keyboardShortcut(.return)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460, height: 360)
    }
}

struct PermissionDeniedSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield").font(.largeTitle).foregroundStyle(.orange)
            Text("Apple Notes permission required").font(.headline)
            Text("AppleNotestoX needs permission to read your Apple Notes via AppleScript. Grant it in System Settings → Privacy & Security → Automation, then retry.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Retry") {
                    Task {
                        state.permissionDeniedSheet = false
                        await state.loadAppleHierarchy()
                    }
                }
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
