# Apple Notes → LLM-Wiki Bridge (P1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a GUI "Export to wiki" destination to `AppleNotestoX` that writes a selected Apple Note (text + screenshots, positions preserved) into the `Personal_LLM_Wiki` vault as a provenance-stamped markdown file plus original image assets.

**Architecture:** Approach A — reuse `AppleNotesService` (read) and `NoteConverter` (HTML → ordered `[NotionBlock]` with image placeholders) unchanged; add a pure `MarkdownRenderer` (`[NotionBlock] → markdown`), a testable `WikiExportAssembler` (copies assets + renders + writes the file), a `WikiExportCoordinator` actor (streams progress, mirrors `ArchiveCoordinator`), and additive GUI wiring (destination switch + vault chooser).

**Tech Stack:** Swift 6, SwiftUI/AppKit (macOS 14+), SwiftSoup (already a dep, used by `NoteConverter`), `swift test` (XCTest).

## Global Constraints

- Swift tools 6.0; platform macOS 14+ (`Package.swift`).
- Do **not** modify the Notion path (`NotionService`, `ArchiveCoordinator`, `NotionModels`) or `NoteConverter`/`AppleNotesService` behavior. All additions are additive.
- Destination folder in vault: `raw/journal/`; assets: `raw/assets/`.
- Filename: `YYYY-MM-DD-<slug>.md`, date from the note's `modifiedAt`.
- Images: copy **originals** (no re-encode) into `raw/assets/`, named `<slug>-NN.<ext>` (NN zero-padded, 2 digits) in document order.
- Image references: Obsidian embeds `![[<slug>-NN.ext]]`; non-image attachments → `[name](raw/assets/name)` links.
- Source Apple Note left untouched.
- Tests live under `Tests/AppleNotestoXTests/`, mirroring existing test style.
- Commit after every green step with explicit pathspecs (no `git add -A`).

---

## File Structure

- Create `Sources/AppleNotestoX/Models/WikiExport.swift` — config, job, result, progress/status value types.
- Create `Sources/AppleNotestoX/Services/WikiNaming.swift` — pure slug/filename/frontmatter/collision helpers.
- Create `Sources/AppleNotestoX/Services/MarkdownRenderer.swift` — pure `[NotionBlock] → markdown`.
- Create `Sources/AppleNotestoX/Services/WikiExportAssembler.swift` — copies assets + renders + writes file (testable with a temp dir).
- Create `Sources/AppleNotestoX/Services/WikiExportCoordinator.swift` — actor; streams `[WikiExportProgress]`.
- Modify `Sources/AppleNotestoX/App/AppState.swift` — destination enum, persisted vault bookmark, `runWikiExport()`.
- Modify `Sources/AppleNotestoX/UI/DestinationPane.swift` — Notion/Wiki switch + vault chooser.
- Modify `Sources/AppleNotestoX/UI/ContentView.swift` — toolbar action label/gating in Wiki mode.
- Create tests: `WikiNamingTests.swift`, `MarkdownRendererTests.swift`, `WikiExportAssemblerTests.swift` (+ Glints fixture).

---

## Task 0: Establish baseline green

- [ ] **Step 1: Build**

Run: `swift build`
Expected: builds (deps resolve from `Package.resolved`).

- [ ] **Step 2: Run existing tests**

Run: `swift test`
Expected: existing `NoteConverterTests`, `NotionServiceTests`, `ImagePipelineTests` PASS. Record the baseline.

---

## Task 1: Naming + frontmatter helpers (`WikiNaming`)

**Files:**
- Create: `Sources/AppleNotestoX/Services/WikiNaming.swift`
- Test: `Tests/AppleNotestoXTests/WikiNamingTests.swift`

**Interfaces — Produces:**
```swift
enum WikiNaming {
    static func slug(from title: String) -> String
    static func isoDay(_ date: Date) -> String                       // "YYYY-MM-DD" (UTC-stable)
    static func markdownFilename(date: Date, slug: String) -> String // "YYYY-MM-DD-slug.md"
    static func assetFilename(slug: String, index: Int, ext: String) -> String // "slug-01.png"
    static func uniqueName(_ name: String, existing: Set<String>) -> String     // "x.md"→"x-2.md"
    static func frontmatter(noteID: String, title: String, modified: Date, exported: Date) -> String
}
```

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import AppleNotestoX

final class WikiNamingTests: XCTestCase {
    func testSlugKebabsAndStrips() {
        XCTAssertEqual(WikiNaming.slug(from: "Glints Journal — 2026!"), "glints-journal-2026")
        XCTAssertEqual(WikiNaming.slug(from: "  Multiple   spaces "), "multiple-spaces")
        XCTAssertEqual(WikiNaming.slug(from: ""), "note")
    }
    func testIsoDay() {
        let d = DateComponents(calendar: .init(identifier: .gregorian), timeZone: TimeZone(identifier: "UTC"),
                               year: 2026, month: 3, day: 24, hour: 17).date!
        XCTAssertEqual(WikiNaming.isoDay(d), "2026-03-24")
    }
    func testMarkdownAndAssetFilenames() {
        let d = WikiNaming.isoDay(Date(timeIntervalSince1970: 0))
        XCTAssertEqual(WikiNaming.markdownFilename(date: Date(timeIntervalSince1970: 0), slug: "x"), "\(d)-x.md")
        XCTAssertEqual(WikiNaming.assetFilename(slug: "glints", index: 1, ext: "png"), "glints-01.png")
        XCTAssertEqual(WikiNaming.assetFilename(slug: "glints", index: 12, ext: "JPG"), "glints-12.jpg")
    }
    func testUniqueName() {
        XCTAssertEqual(WikiNaming.uniqueName("a.md", existing: []), "a.md")
        XCTAssertEqual(WikiNaming.uniqueName("a.md", existing: ["a.md"]), "a-2.md")
        XCTAssertEqual(WikiNaming.uniqueName("a.md", existing: ["a.md","a-2.md"]), "a-3.md")
    }
    func testFrontmatterContainsKeys() {
        let fm = WikiNaming.frontmatter(noteID: "x-123", title: "Glints", 
                                        modified: Date(timeIntervalSince1970: 0), exported: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(fm.hasPrefix("---\n"))
        XCTAssertTrue(fm.contains("origin: user-stated"))
        XCTAssertTrue(fm.contains("source_app: apple-notes"))
        XCTAssertTrue(fm.contains("apple_note_id: x-123"))
        XCTAssertTrue(fm.contains("title: Glints"))
        XCTAssertTrue(fm.contains("Provenance:"))
    }
}
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `swift test --filter WikiNamingTests`
Expected: FAIL ("cannot find 'WikiNaming'").

- [ ] **Step 3: Implement**

```swift
import Foundation

enum WikiNaming {
    static func slug(from title: String) -> String {
        let lower = title.lowercased()
        let mapped = lower.unicodeScalars.map { s -> Character in
            (CharacterSet.alphanumerics.contains(s)) ? Character(s) : " "
        }
        let collapsed = String(mapped).split(whereSeparator: { $0 == " " }).joined(separator: "-")
        return collapsed.isEmpty ? "note" : collapsed
    }
    static func isoDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    static func markdownFilename(date: Date, slug: String) -> String { "\(isoDay(date))-\(slug).md" }
    static func assetFilename(slug: String, index: Int, ext: String) -> String {
        let nn = String(format: "%02d", index)
        let e = ext.lowercased().isEmpty ? "dat" : ext.lowercased()
        return "\(slug)-\(nn).\(e)"
    }
    static func uniqueName(_ name: String, existing: Set<String>) -> String {
        guard existing.contains(name) else { return name }
        let url = URL(fileURLWithPath: name)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var i = 2
        while true {
            let candidate = ext.isEmpty ? "\(base)-\(i)" : "\(base)-\(i).\(ext)"
            if !existing.contains(candidate) { return candidate }
            i += 1
        }
    }
    static func frontmatter(noteID: String, title: String, modified: Date, exported: Date) -> String {
        """
        ---
        origin: user-stated
        source_type: journal
        source_app: apple-notes
        apple_note_id: \(noteID)
        title: \(title)
        note_modified: \(isoDay(modified))
        exported: \(isoDay(exported))
        ---
        > Provenance: exported verbatim from Apple Notes. Immutable — synthesize into
        > wiki/, don't edit here.

        """
    }
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `swift test --filter WikiNamingTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppleNotestoX/Services/WikiNaming.swift Tests/AppleNotestoXTests/WikiNamingTests.swift
git commit -m "feat(wiki): naming + provenance frontmatter helpers"
```

---

## Task 2: MarkdownRenderer

**Files:**
- Create: `Sources/AppleNotestoX/Services/MarkdownRenderer.swift`
- Test: `Tests/AppleNotestoXTests/MarkdownRendererTests.swift`

**Interfaces — Consumes:** `NotionBlock`, `NotionRichText` (from `Models/NotionModels.swift`).
**Produces:**
```swift
enum MarkdownRenderer {
    struct Output: Equatable { var markdown: String; var warnings: [String] }
    /// `inlineAsset(id)` returns the full inline markdown for an image placeholder
    /// (e.g. "![[glints-01.png]]" or "[doc.pdf](raw/assets/doc.pdf)"), or nil → missing-image warning.
    static func render(_ blocks: [NotionBlock], inlineAsset: (UUID) -> String?) -> Output
}
```

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import AppleNotestoX

final class MarkdownRendererTests: XCTestCase {
    private func rt(_ s: String, bold: Bool = false, italic: Bool = false,
                    code: Bool = false, link: URL? = nil) -> NotionRichText {
        NotionRichText(content: s, bold: bold, italic: italic, strikethrough: false,
                       underline: false, code: code, link: link)
    }
    func testHeadingsAndParagraph() {
        let out = MarkdownRenderer.render([
            .heading1([rt("Title")]), .paragraph([rt("Hello "), rt("world", bold: true)])
        ], inlineAsset: { _ in nil })
        XCTAssertEqual(out.markdown, "# Title\n\nHello **world**\n")
    }
    func testListsTodosQuoteCodeDivider() {
        let out = MarkdownRenderer.render([
            .bulletedListItem([rt("a")]), .numberedListItem([rt("b")]),
            .toDo([rt("c")], checked: false), .toDo([rt("d")], checked: true),
            .quote([rt("q")]), .code([rt("x=1")], language: "swift"), .divider
        ], inlineAsset: { _ in nil })
        XCTAssertEqual(out.markdown,
            "- a\n1. b\n- [ ] c\n- [x] d\n> q\n```swift\nx=1\n```\n\n---\n")
    }
    func testRichTextStylesAndLink() {
        let out = MarkdownRenderer.render([
            .paragraph([rt("i", italic: true), rt(" "), rt("c", code: true), rt(" "),
                        rt("link", link: URL(string: "https://x.test")!)])
        ], inlineAsset: { _ in nil })
        XCTAssertEqual(out.markdown, "*i* `c` [link](https://x.test)\n")
    }
    func testImagePlaceholderEmbedAndMissing() {
        let id = UUID()
        let ok = MarkdownRenderer.render([.imagePlaceholder(id: id, localPath: URL(fileURLWithPath: "/tmp/x"))],
                                         inlineAsset: { $0 == id ? "![[glints-01.png]]" : nil })
        XCTAssertEqual(ok.markdown, "![[glints-01.png]]\n")
        XCTAssertTrue(ok.warnings.isEmpty)

        let missing = MarkdownRenderer.render([.imagePlaceholder(id: UUID(), localPath: URL(fileURLWithPath: "/tmp/x"))],
                                              inlineAsset: { _ in nil })
        XCTAssertTrue(missing.markdown.contains("> [!warning]"))
        XCTAssertEqual(missing.warnings.count, 1)
    }
    func testImageFailedBlockWarns() {
        let out = MarkdownRenderer.render([.imageFailed(message: "no matching attachment")], inlineAsset: { _ in nil })
        XCTAssertTrue(out.markdown.contains("> [!warning]"))
        XCTAssertEqual(out.warnings.count, 1)
    }
}
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `swift test --filter MarkdownRendererTests`
Expected: FAIL ("cannot find 'MarkdownRenderer'").

- [ ] **Step 3: Implement**

```swift
import Foundation

enum MarkdownRenderer {
    struct Output: Equatable { var markdown: String = ""; var warnings: [String] = [] }

    static func render(_ blocks: [NotionBlock], inlineAsset: (UUID) -> String?) -> Output {
        var out = Output()
        var lines: [String] = []
        var missingIndex = 0
        for block in blocks {
            switch block {
            case .heading1(let r): lines.append("# " + inline(r))
            case .heading2(let r): lines.append("## " + inline(r))
            case .heading3(let r): lines.append("### " + inline(r))
            case .paragraph(let r): lines.append(inline(r))
            case .bulletedListItem(let r): lines.append("- " + inline(r))
            case .numberedListItem(let r): lines.append("1. " + inline(r))
            case .toDo(let r, let checked): lines.append((checked ? "- [x] " : "- [ ] ") + inline(r))
            case .quote(let r): lines.append("> " + inline(r))
            case .code(let r, let lang): lines.append("```\(lang)\n\(plain(r))\n```\n")
            case .divider: lines.append("---")
            case .imagePlaceholder(let id, _):
                if let snippet = inlineAsset(id) { lines.append(snippet) }
                else {
                    missingIndex += 1
                    lines.append("> [!warning] missing image #\(missingIndex)")
                    out.warnings.append("missing asset for placeholder #\(missingIndex)")
                }
            case .imageUploaded:
                lines.append("> [!warning] unexpected uploaded-image block (Notion-only)")
                out.warnings.append("unexpected imageUploaded block")
            case .imageFailed(let msg):
                lines.append("> [!warning] image failed: \(msg)")
                out.warnings.append("image failed: \(msg)")
            }
        }
        out.markdown = lines.joined(separator: "\n")
        if !out.markdown.isEmpty && !out.markdown.hasSuffix("\n") { out.markdown += "\n" }
        return out
    }

    private static func plain(_ rts: [NotionRichText]) -> String { rts.map(\.content).joined() }

    private static func inline(_ rts: [NotionRichText]) -> String {
        rts.map { rt -> String in
            var s = rt.content
            if s.isEmpty { return s }
            if rt.code { s = "`\(s)`" }
            if rt.bold { s = "**\(s)**" }
            if rt.italic { s = "*\(s)*" }
            if rt.strikethrough { s = "~~\(s)~~" }
            if let link = rt.link { s = "[\(s)](\(link.absoluteString))" }
            return s
        }.joined()
    }
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `swift test --filter MarkdownRendererTests`
Expected: PASS. (If a golden string differs by whitespace, align the test to the documented output — do not loosen the renderer arbitrarily.)

- [ ] **Step 5: Commit**

```bash
git add Sources/AppleNotestoX/Services/MarkdownRenderer.swift Tests/AppleNotestoXTests/MarkdownRendererTests.swift
git commit -m "feat(wiki): [NotionBlock] → markdown renderer"
```

---

## Task 3: WikiExport models

**Files:**
- Create: `Sources/AppleNotestoX/Models/WikiExport.swift`

**Interfaces — Produces:** `WikiVaultConfig`, `WikiExportJob`, `WikiExportResult`, `WikiExportStatus`, `WikiExportProgress` (signatures as in spec §5). No dedicated test (pure data; exercised by Tasks 4–5).

- [ ] **Step 1: Implement**

```swift
import Foundation

struct WikiVaultConfig: Sendable, Equatable {
    var vaultURL: URL
    var journalSubpath: String = "raw/journal"
    var assetsSubpath: String = "raw/assets"
    var journalDir: URL { vaultURL.appendingPathComponent(journalSubpath, isDirectory: true) }
    var assetsDir: URL { vaultURL.appendingPathComponent(assetsSubpath, isDirectory: true) }
}

struct WikiExportJob: Sendable {
    let noteIDs: [String]
    let config: WikiVaultConfig
}

struct WikiExportResult: Sendable, Equatable {
    let markdownPath: URL
    let assetPaths: [URL]
    let imageCount: Int
    let warnings: [String]
}

enum WikiExportStatus: Sendable, Equatable {
    case pending, fetching, converting
    case savingAssets(done: Int, total: Int)
    case writing
    case done(result: WikiExportResult)
    case failed(message: String)
}

struct WikiExportProgress: Identifiable, Sendable, Equatable {
    let id: String           // Apple note id
    var title: String
    var status: WikiExportStatus
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: compiles.

- [ ] **Step 3: Commit**

```bash
git add Sources/AppleNotestoX/Models/WikiExport.swift
git commit -m "feat(wiki): export model types"
```

---

## Task 4: WikiExportAssembler (core, testable)

**Files:**
- Create: `Sources/AppleNotestoX/Services/WikiExportAssembler.swift`
- Test: `Tests/AppleNotestoXTests/WikiExportAssemblerTests.swift`

**Interfaces — Consumes:** `AppleNoteContent`, `AppleNoteAttachment` (Models), `NoteConverter`, `MarkdownRenderer`, `WikiNaming`, `WikiVaultConfig`, `WikiExportResult`.
**Produces:**
```swift
struct WikiExportAssembler {
    let fileManager: FileManager
    init(fileManager: FileManager = .default)
    /// Copies assets into config.assetsDir, renders markdown (frontmatter + body + unplaced),
    /// writes config.journalDir/<unique md name>. Creates dirs as needed. Returns the result.
    func assemble(noteID: String, title: String, modified: Date,
                  content: AppleNoteContent, config: WikiVaultConfig,
                  exported: Date) throws -> WikiExportResult
}
```

**Asset/markdown rules (lock these):**
- `imageExts = ["png","jpg","jpeg","gif","heic","heif","webp","tiff","bmp"]`.
- For each `imagePlaceholder(id, localPath)` in block order: find the attachment whose `localURL == localPath`. Copy its bytes to `assetsDir/assetFilename(slug,index,ext)` (index increments per placed asset; ext from `localURL.pathExtension`), collision-safe across names chosen this run. Build `id → "![[name]]"` (image ext) or `id → "[name](raw/assets/name)"` (non-image).
- Attachments never referenced by any placeholder → copied too and appended under `## Unplaced attachments` as `- [name](raw/assets/name)`, plus a warning.
- Markdown file = `frontmatter` + `renderer.markdown` + (unplaced section if any).
- File written with `uniqueName` against existing `journalDir` contents.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import AppleNotestoX

final class WikiExportAssemblerTests: XCTestCase {
    private var tmp: URL!
    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func makeAttachment(_ name: String, bytes: Data = Data([0,1,2])) throws -> AppleNoteAttachment {
        let dir = tmp.appendingPathComponent("att-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try bytes.write(to: url)
        return AppleNoteAttachment(id: UUID().uuidString, filename: name, localURL: url)
    }

    func testInterleavedTextAndImagesPreservesOrder() throws {
        let a1 = try makeAttachment("shot1.png")
        let a2 = try makeAttachment("shot2.png")
        let html = "<div>Intro</div><img><div>Middle</div><img><div>End</div>"
        let content = AppleNoteContent(html: html, attachments: [a1, a2])
        let cfg = WikiVaultConfig(vaultURL: tmp.appendingPathComponent("vault"))
        let r = try WikiExportAssembler().assemble(
            noteID: "n1", title: "Glints Journal", modified: Date(timeIntervalSince1970: 0),
            content: content, config: cfg, exported: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(r.imageCount, 2)
        XCTAssertEqual(r.assetPaths.count, 2)
        let md = try String(contentsOf: r.markdownPath, encoding: .utf8)
        // order: Intro, embed1, Middle, embed2, End
        let iIntro = md.range(of: "Intro")!.lowerBound
        let iImg1  = md.range(of: "glints-journal-01.png")!.lowerBound
        let iMid   = md.range(of: "Middle")!.lowerBound
        let iImg2  = md.range(of: "glints-journal-02.png")!.lowerBound
        let iEnd   = md.range(of: "End")!.lowerBound
        XCTAssertTrue(iIntro < iImg1 && iImg1 < iMid && iMid < iImg2 && iImg2 < iEnd)
        XCTAssertTrue(md.hasPrefix("---\n"))                       // frontmatter
        XCTAssertTrue(md.contains("apple_note_id: n1"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cfg.assetsDir.appendingPathComponent("glints-journal-01.png").path))
    }

    func testMoreAttachmentsThanImagesGoUnplaced() throws {
        let a1 = try makeAttachment("a.png")
        let a2 = try makeAttachment("b.pdf")     // non-image, no <img> for it
        let html = "<div>Only one image</div><img>"
        let content = AppleNoteContent(html: html, attachments: [a1, a2])
        let cfg = WikiVaultConfig(vaultURL: tmp.appendingPathComponent("vault"))
        let r = try WikiExportAssembler().assemble(noteID: "n2", title: "T", modified: Date(timeIntervalSince1970: 0),
                                                   content: content, config: cfg, exported: Date(timeIntervalSince1970: 0))
        let md = try String(contentsOf: r.markdownPath, encoding: .utf8)
        XCTAssertTrue(md.contains("## Unplaced attachments"))
        XCTAssertTrue(md.contains("b.pdf"))
        XCTAssertFalse(r.warnings.isEmpty)
    }

    func testFilenameCollisionSuffixes() throws {
        let cfg = WikiVaultConfig(vaultURL: tmp.appendingPathComponent("vault"))
        try FileManager.default.createDirectory(at: cfg.journalDir, withIntermediateDirectories: true)
        let day = WikiNaming.isoDay(Date(timeIntervalSince1970: 0))
        try "x".write(to: cfg.journalDir.appendingPathComponent("\(day)-t.md"), atomically: true, encoding: .utf8)
        let content = AppleNoteContent(html: "<div>hi</div>", attachments: [])
        let r = try WikiExportAssembler().assemble(noteID: "n3", title: "T", modified: Date(timeIntervalSince1970: 0),
                                                   content: content, config: cfg, exported: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(r.markdownPath.lastPathComponent, "\(day)-t-2.md")
    }
}
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `swift test --filter WikiExportAssemblerTests`
Expected: FAIL ("cannot find 'WikiExportAssembler'").

- [ ] **Step 3: Implement**

```swift
import Foundation

struct WikiExportAssembler {
    let fileManager: FileManager
    init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    private static let imageExts: Set<String> = ["png","jpg","jpeg","gif","heic","heif","webp","tiff","bmp"]

    func assemble(noteID: String, title: String, modified: Date,
                  content: AppleNoteContent, config: WikiVaultConfig,
                  exported: Date = Date()) throws -> WikiExportResult {
        try fileManager.createDirectory(at: config.journalDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: config.assetsDir, withIntermediateDirectories: true)

        let slug = WikiNaming.slug(from: title)
        let blocks = NoteConverter.convert(html: content.html, attachments: content.attachments)

        var warnings: [String] = []
        var assetPaths: [URL] = []
        var inlineByID: [UUID: String] = [:]
        var usedNames = Set<String>()
        var matchedLocalPaths = Set<URL>()
        var assetIndex = 0

        // Place images where placeholders are (block order).
        for block in blocks {
            if case .imagePlaceholder(let id, let localPath) = block {
                guard let att = content.attachments.first(where: { $0.localURL == localPath }) else {
                    warnings.append("placeholder had no attachment on disk")
                    continue
                }
                assetIndex += 1
                let ext = localPath.pathExtension
                var name = WikiNaming.assetFilename(slug: slug, index: assetIndex, ext: ext)
                name = WikiNaming.uniqueName(name, existing: usedNames)
                usedNames.insert(name)
                let dest = config.assetsDir.appendingPathComponent(name)
                do {
                    if fileManager.fileExists(atPath: dest.path) { try fileManager.removeItem(at: dest) }
                    try fileManager.copyItem(at: att.localURL, to: dest)
                    assetPaths.append(dest)
                    matchedLocalPaths.insert(att.localURL)
                    inlineByID[id] = Self.imageExts.contains(ext.lowercased())
                        ? "![[\(name)]]"
                        : "[\(att.filename)](\(config.assetsSubpath)/\(name))"
                } catch {
                    warnings.append("failed to copy asset \(att.filename): \(error.localizedDescription)")
                }
            }
        }

        let rendered = MarkdownRenderer.render(blocks, inlineAsset: { inlineByID[$0] })
        warnings.append(contentsOf: rendered.warnings)

        // Unplaced attachments (never referenced by a placeholder).
        var unplacedLines: [String] = []
        for att in content.attachments where !matchedLocalPaths.contains(att.localURL) {
            assetIndex += 1
            let ext = att.localURL.pathExtension
            var name = WikiNaming.assetFilename(slug: slug, index: assetIndex, ext: ext)
            name = WikiNaming.uniqueName(name, existing: usedNames)
            usedNames.insert(name)
            let dest = config.assetsDir.appendingPathComponent(name)
            do {
                if fileManager.fileExists(atPath: dest.path) { try fileManager.removeItem(at: dest) }
                try fileManager.copyItem(at: att.localURL, to: dest)
                assetPaths.append(dest)
                let isImg = Self.imageExts.contains(ext.lowercased())
                unplacedLines.append(isImg ? "- ![[\(name)]]" : "- [\(att.filename)](\(config.assetsSubpath)/\(name))")
            } catch {
                warnings.append("failed to copy unplaced asset \(att.filename): \(error.localizedDescription)")
            }
        }
        if !unplacedLines.isEmpty {
            warnings.append("\(unplacedLines.count) attachment(s) not referenced inline → appended to Unplaced section")
        }

        let frontmatter = WikiNaming.frontmatter(noteID: noteID, title: title, modified: modified, exported: exported)
        var body = frontmatter + rendered.markdown
        if !unplacedLines.isEmpty {
            body += "\n## Unplaced attachments\n\n" + unplacedLines.joined(separator: "\n") + "\n"
        }

        let existing = Set((try? fileManager.contentsOfDirectory(atPath: config.journalDir.path)) ?? [])
        let mdName = WikiNaming.uniqueName(WikiNaming.markdownFilename(date: modified, slug: slug), existing: existing)
        let mdURL = config.journalDir.appendingPathComponent(mdName)
        try body.write(to: mdURL, atomically: true, encoding: .utf8)

        let imageCount = assetPaths.filter { Self.imageExts.contains($0.pathExtension.lowercased()) }.count
        return WikiExportResult(markdownPath: mdURL, assetPaths: assetPaths, imageCount: imageCount, warnings: warnings)
    }
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `swift test --filter WikiExportAssemblerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppleNotestoX/Services/WikiExportAssembler.swift Tests/AppleNotestoXTests/WikiExportAssemblerTests.swift
git commit -m "feat(wiki): export assembler (assets + markdown + provenance, order-preserving)"
```

---

## Task 5: WikiExportCoordinator (progress stream)

**Files:**
- Create: `Sources/AppleNotestoX/Services/WikiExportCoordinator.swift`

**Interfaces — Consumes:** `AppleNotesService`, `AppleNotesHierarchy`, `WikiExportAssembler`, `WikiExportJob`, `WikiExportProgress`.
**Produces:** `func export(job:hierarchy:) -> AsyncStream<[WikiExportProgress]>` (mirrors `ArchiveCoordinator.archive`).

- [ ] **Step 1: Implement** (mirror `ArchiveCoordinator.swift` structure)

```swift
import Foundation

actor WikiExportCoordinator {
    private let notes: AppleNotesService
    private let assembler: WikiExportAssembler

    init(notes: AppleNotesService, assembler: WikiExportAssembler = WikiExportAssembler()) {
        self.notes = notes
        self.assembler = assembler
    }

    nonisolated func export(job: WikiExportJob, hierarchy: AppleNotesHierarchy) -> AsyncStream<[WikiExportProgress]> {
        AsyncStream { continuation in
            let task = Task {
                nonisolated(unsafe) var progresses: [WikiExportProgress] = job.noteIDs.map { id in
                    WikiExportProgress(id: id, title: hierarchy.notes[id]?.name ?? id, status: .pending)
                }
                @Sendable func snapshot() -> [WikiExportProgress] { progresses }
                @Sendable func update(_ i: Int, _ s: WikiExportStatus) { progresses[i].status = s; continuation.yield(snapshot()) }

                continuation.yield(snapshot())
                for (i, noteID) in job.noteIDs.enumerated() {
                    do {
                        update(i, .fetching)
                        let content = try await self.notes.fetchNote(id: noteID)
                        update(i, .converting)
                        let note = hierarchy.notes[noteID]
                        let title = note?.name ?? "(untitled)"
                        let modified = note?.modifiedAt ?? Date()
                        let total = content.attachments.count
                        update(i, .savingAssets(done: 0, total: total))
                        let result = try self.assembler.assemble(
                            noteID: noteID, title: title, modified: modified,
                            content: content, config: job.config, exported: Date())
                        update(i, .writing)
                        update(i, .done(result: result))
                    } catch {
                        update(i, .failed(message: error.localizedDescription))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: compiles.

- [ ] **Step 3: Commit**

```bash
git add Sources/AppleNotestoX/Services/WikiExportCoordinator.swift
git commit -m "feat(wiki): export coordinator with progress stream"
```

---

## Task 6: AppState wiring (destination + persisted vault + runWikiExport)

**Files:**
- Modify: `Sources/AppleNotestoX/App/AppState.swift`

**Interfaces — Produces:** `enum ExportDestination { case notion, wiki }`, `var exportDestination`, `var vaultURL: URL?`, `func chooseVault(_:)`, `func runWikiExport()`. Reuses `archiveProgress`-style display via a new `wikiProgress: [WikiExportProgress]`.

- [ ] **Step 1: Implement** (add to `AppState`, do not remove Notion members)

```swift
// add near other state
enum ExportDestination: String, Sendable { case notion, wiki }
// in AppState:
var exportDestination: ExportDestination = .notion
var vaultURL: URL? = nil
var wikiProgress: [WikiExportProgress] = []
let wikiCoordinator: WikiExportCoordinator
private let vaultBookmarkKey = "wiki_vault_bookmark"

// in init(): after other service init
self.wikiCoordinator = WikiExportCoordinator(notes: a)
// then: restoreVaultBookmark()

func chooseVault(_ url: URL) {
    vaultURL = url
    if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
        UserDefaults.standard.set(data, forKey: vaultBookmarkKey)
    }
}
func restoreVaultBookmark() {
    guard let data = UserDefaults.standard.data(forKey: vaultBookmarkKey) else { return }
    var stale = false
    if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) {
        vaultURL = url
    }
}
func runWikiExport() async {
    guard let vault = vaultURL, !selectedNoteIDs.isEmpty, let h = hierarchy else { return }
    let didAccess = vault.startAccessingSecurityScopedResource()
    defer { if didAccess { vault.stopAccessingSecurityScopedResource() } }
    let job = WikiExportJob(noteIDs: Array(selectedNoteIDs), config: WikiVaultConfig(vaultURL: vault))
    isArchiving = true
    wikiProgress = []
    for await snap in wikiCoordinator.export(job: job, hierarchy: h) { wikiProgress = snap }
    isArchiving = false
    selectedNoteIDs.removeAll()
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: compiles. (Resolve any actor-isolation warnings by keeping `runWikiExport` on `@MainActor` as the class already is.)

- [ ] **Step 3: Commit**

```bash
git add Sources/AppleNotestoX/App/AppState.swift
git commit -m "feat(wiki): AppState destination toggle + persisted vault + runWikiExport"
```

---

## Task 7: GUI — DestinationPane switch + vault chooser + toolbar

**Files:**
- Modify: `Sources/AppleNotestoX/UI/DestinationPane.swift`
- Modify: `Sources/AppleNotestoX/UI/ContentView.swift`

- [ ] **Step 1: Implement DestinationPane Wiki mode** (wrap existing Notion content in a `switch state.exportDestination`)

```swift
// At top of DestinationPane.body, add a Picker bound to state.exportDestination:
Picker("", selection: Bindable(state).exportDestination) {
    Text("Notion").tag(AppState.ExportDestination.notion)
    Text("Wiki").tag(AppState.ExportDestination.wiki)
}.pickerStyle(.segmented).padding(.horizontal, 12).padding(.top, 8)

// Then render Notion UI when .notion (existing), and for .wiki:
//   - show state.vaultURL?.path ?? "No vault chosen"
//   - Button("Choose vault…") { open NSOpenPanel (canChooseDirectories=true) → state.chooseVault(url) }
```

NSOpenPanel snippet:
```swift
let panel = NSOpenPanel()
panel.canChooseDirectories = true
panel.canChooseFiles = false
panel.allowsMultipleSelection = false
if panel.runModal() == .OK, let url = panel.url { state.chooseVault(url) }
```

- [ ] **Step 2: Implement ContentView toolbar gating**

```swift
// Replace the single Archive button with destination-aware action:
if state.exportDestination == .wiki {
    Button("Export to wiki") { Task { await state.runWikiExport() } }
        .keyboardShortcut(.return, modifiers: [.command])
        .disabled(state.selectedNoteIDs.isEmpty || state.vaultURL == nil || state.isArchiving)
} else {
    Button("Archive…") { showPreview = true }
        .keyboardShortcut(.return, modifiers: [.command])
        .disabled(state.selectedNoteIDs.isEmpty || state.selectedNotionPageID == nil || state.isArchiving)
}
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: compiles.

- [ ] **Step 4: Commit**

```bash
git add Sources/AppleNotestoX/UI/DestinationPane.swift Sources/AppleNotestoX/UI/ContentView.swift
git commit -m "feat(wiki): GUI destination switch, vault chooser, export action"
```

---

## Task 8: Full verification + Glints acceptance

- [ ] **Step 1: Full test suite**

Run: `swift test`
Expected: all tests PASS (existing + new). Fix any regressions before proceeding.

- [ ] **Step 2: Manual acceptance (owner machine, requires Notes Automation permission)**

1. `swift run AppleNotestoX` (or open in Xcode).
2. Switch destination to **Wiki**; choose vault `~/Projects/Personal_LLM_Wiki`.
3. Select the **Glints** note; click **Export to wiki**.
4. Verify `raw/journal/<date>-glints-*.md` exists with provenance frontmatter; screenshots in `raw/assets/`.
5. Open the vault in Obsidian; confirm each screenshot sits beside the correct paragraph; check any `> [!warning]` callouts.
6. In opencode, ask the wiki to **ingest** the new file (existing `Personal_LLM_Wiki` workflow).

- [ ] **Step 3: Update PROGRESS_REPORT.md** (Completed bullet: what shipped, files, commit SHAs, verify status).

---

## Self-Review (completed during planning)

- **Spec coverage:** §5 components → Tasks 1–7; §6 output shape → Tasks 1,4; §7 data flow → Tasks 4,5; §8 error handling → Tasks 2,4 (warnings/unplaced/missing); §9 testing → Tasks 1,2,4,8. ✓
- **Placeholders:** none — every code step has concrete code. ✓
- **Type consistency:** `MarkdownRenderer.render(_:inlineAsset:)`, `WikiExportAssembler.assemble(noteID:title:modified:content:config:exported:)`, `WikiExportCoordinator.export(job:hierarchy:)`, `WikiNaming` signatures used identically across tasks. ✓
- **Note:** UI/AppState tasks are verified by build + manual acceptance (SwiftUI/AppKit + security-scoped bookmarks aren't unit-tested) — explicitly called out, not a placeholder.
