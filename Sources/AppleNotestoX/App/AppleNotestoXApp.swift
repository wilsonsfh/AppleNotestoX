import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct AppleNotestoXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup("AppleNotestoX") {
            ContentView()
                .environment(state)
                .frame(minWidth: 900, minHeight: 600)
                .task { await state.bootstrap() }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(after: .textEditing) {
                Button("Find Notes") { state.requestNoteSearch() }
                    .keyboardShortcut("f", modifiers: .command)
            }
        }
    }
}
