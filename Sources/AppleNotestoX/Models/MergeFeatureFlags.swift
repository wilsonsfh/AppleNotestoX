import Foundation

/// Set by hand from the manual spike documented in
/// docs/superpowers/plans/2026-08-15-merge-to-note.md, Task 1. `osascript`
/// creating a note whose body contains `<img src="file://…">` was tested
/// against this machine's Notes/macOS version on 2026-08-15 and found to:
/// not render an image — Notes recognized the tag as an attachment slot
/// (`count of attachments` came back 1) but re-serialized the note's body
/// as `<img src="data:image/png;base64,(null)"/>`, i.e. it failed to read
/// and encode the file at the given `file://` path, leaving a broken image
/// rather than a real inline one.
enum MergeFeatureFlags {
    static let embedImagesSupported = false
}
