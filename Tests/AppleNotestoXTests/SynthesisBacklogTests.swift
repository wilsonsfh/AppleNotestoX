import XCTest
@testable import AppleNotestoX

final class SynthesisBacklogTests: XCTestCase {
    func testPendingIsRawMinusSourcesSortedDesc() {
        let raw = ["2026-06-30-a.md", "2026-06-12-b.md", "2026-06-26-c.md"]
        let sources: Set<String> = ["2026-06-12-b.md"]
        XCTAssertEqual(SynthesisBacklog.pending(rawJournal: raw, wikiSources: sources),
                       ["2026-06-30-a.md", "2026-06-26-c.md"])
    }

    func testPendingEmptyWhenAllSynthesized() {
        XCTAssertTrue(SynthesisBacklog.pending(rawJournal: ["x.md"], wikiSources: ["x.md"]).isEmpty)
    }

    func testScanBuildsItemsFromDisk() throws {
        let vault = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let j = vault.appendingPathComponent("raw/journal", isDirectory: true)
        let s = vault.appendingPathComponent("wiki/sources", isDirectory: true)
        try FileManager.default.createDirectory(at: j, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: s, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: j.appendingPathComponent("2026-06-30-mindset.md").path, contents: Data())
        FileManager.default.createFile(atPath: j.appendingPathComponent("2026-06-12-init.md").path, contents: Data())
        FileManager.default.createFile(atPath: s.appendingPathComponent("2026-06-12-init.md").path, contents: Data())

        let items = SynthesisBacklog.scan(vaultURL: vault)
        XCTAssertEqual(items.map(\.id), ["2026-06-30-mindset.md"])
        XCTAssertEqual(items.first?.date, "2026-06-30")
        XCTAssertEqual(items.first?.slug, "mindset")
    }

    func testPromptListsRelativePaths() {
        let item = BacklogItem(id: "2026-06-30-x.md", date: "2026-06-30", slug: "x",
                               url: URL(fileURLWithPath: "/v/raw/journal/2026-06-30-x.md"))
        let p = SynthesisBacklog.opencodePrompt([item])
        XCTAssertTrue(p.contains("raw/journal/2026-06-30-x.md"))
        XCTAssertTrue(p.lowercased().contains("agents.md"))
    }
}
