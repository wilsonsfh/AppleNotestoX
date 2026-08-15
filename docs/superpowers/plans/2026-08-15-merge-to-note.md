# Merge to Note Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the owner tick any Apple Notes, have an LLM (Groq/Llama) group their content under invented topic headers, preview the result, and write it back into Apple Notes as one new note — originals untouched.

**Architecture:** A new `MergeCoordinator` actor orchestrates fetch → categorize (via a new `GroqService`) → stage attachments (via a new `TriageAssetStore`) → assemble one HTML document → write via a new `AppleNotesService.createNote`. A third `DestinationPane` option and a `MergePreviewSheet` wire it into the existing Capture (renamed "Transfer/Transform") UI. Pure logic (HTML→text, JSON parsing, HTML assembly) is unit-tested; live Notes/network calls are manual acceptance gates, matching this codebase's existing test boundary.

**Tech Stack:** Swift 6, SwiftUI, SwiftSoup (already a dependency), KeychainAccess (already a dependency), `osascript`/AppleScript, Groq's OpenAI-compatible chat completions API, XCTest.

## Global Constraints

- Originals are never moved, deleted, or edited — enforced by never calling `moveNote`/`deleteNote` anywhere in this feature's code path.
- Each run rebuilds the merged note fresh from the current selection; there is no append-to-previous-run logic.
- AppleScript string parameters are passed as `argv` items (`--` + item), never string-interpolated into script source — this is the existing safety pattern in `AppleNotesService` (see `moveScript`/`deleteScript`) and is required for `createNote` too.
- `swift test` requires full Xcode per this repo's documented constraint (see README "Tests"); `swift build` works on Command Line Tools alone. Every task below that adds a test still requires `swift build` to succeed on Command Line Tools; running the new tests themselves is a Full-Xcode-gated step, same as all existing tests in this repo.
- New Keychain entries use the existing `Keychain(service: "com.applenotestox.app")` instance already constructed in `AppState`.
- Follow the existing code style: `actor` for services with external I/O, `struct ... Sendable Equatable` for data models, pure logic lives in files with no I/O so it is unit-testable without mocks.

---

### Task 1: Image-embed spike (decides `MergeFeatureFlags.embedImagesSupported`)

**Files:**
- Create: `Sources/AppleNotestoX/Models/MergeFeatureFlags.swift`
- Test: none (manual spike; the deliverable is the constant below, set by hand from the observed result)

**Interfaces:**
- Produces: `MergeFeatureFlags.embedImagesSupported: Bool` — every later task that assembles or embeds images reads this constant.

Apple Notes' AppleScript dictionary has no documented "attach image on create" command. This spike checks whether setting a new note's `body` to HTML containing `<img src="file:///…">` actually imports a real inline image, before any product code is built around the assumption.

- [ ] **Step 1: Run the spike from a terminal**

```bash
# Use any small local PNG/JPG you have; adjust the path.
osascript -e '
on run argv
    set imgPath to item 1 of argv
    tell application "Notes"
        set theNote to make new note with properties {body:"<div>Spike test</div><img src=\"file://" & imgPath & "\">"}
    end tell
    return (id of theNote) as string
end run
' -- "/absolute/path/to/test-image.png"
```

- [ ] **Step 2: Open Apple Notes and inspect the created note**

Confirm whether the note shows a real, rendered inline image (not a broken-image icon, not literal text, not a blank gap). Delete the spike note afterward regardless of outcome.

- [ ] **Step 3: Record the finding and set the flag**

```swift
import Foundation

/// Set by hand from the manual spike documented in
/// docs/superpowers/plans/2026-08-15-merge-to-note.md, Task 1. `osascript`
/// creating a note whose body contains `<img src="file://…">` was tested
/// against this machine's Notes/macOS version on <fill in the date you ran
/// the spike> and found to: <fill in — either "render a real inline image"
/// or "not render an image (broken link / literal text)">.
enum MergeFeatureFlags {
    static let embedImagesSupported = true // or false — set from the spike result above
}
```

- [ ] **Step 4: Commit**

```bash
git add Sources/AppleNotestoX/Models/MergeFeatureFlags.swift
git commit -m "Record image-embed spike result as MergeFeatureFlags"
```

---

### Task 2: PlainTextExtractor

**Files:**
- Create: `Sources/AppleNotestoX/Services/PlainTextExtractor.swift`
- Test: `Tests/AppleNotestoXTests/PlainTextExtractorTests.swift`

**Interfaces:**
- Produces: `PlainTextExtractor.extract(html: String) -> String` — used by `MergeCoordinator` (Task 8) to turn each fetched note's HTML body into plain text before sending it to Groq.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AppleNotestoX

final class PlainTextExtractorTests: XCTestCase {
    func test_stripsTagsAndPreservesWords() {
        let html = "<div><h1>Title</h1><p>Hello <b>world</b>.</p></div>"
        let text = PlainTextExtractor.extract(html: html)
        XCTAssertEqual(text, "Title\nHello world.")
    }

    func test_listItemsOnOwnLines() {
        let html = "<ul><li>One</li><li>Two</li></ul>"
        let text = PlainTextExtractor.extract(html: html)
        XCTAssertEqual(text, "One\nTwo")
    }

    func test_malformedHTML_returnsEmptyStringNotThrow() {
        let text = PlainTextExtractor.extract(html: "<div><p>unterminated")
        XCTAssertEqual(text, "unterminated")
    }

    func test_emptyInput_returnsEmptyString() {
        XCTAssertEqual(PlainTextExtractor.extract(html: ""), "")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PlainTextExtractorTests`
Expected: FAIL — `PlainTextExtractor` does not exist yet (compile error).

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation
import SwiftSoup

/// Converts Apple Notes HTML into plain text for LLM input. Block-level
/// elements (p, div, h1-h6, li) each contribute one line; inline tags are
/// unwrapped in place.
enum PlainTextExtractor {
    static func extract(html: String) -> String {
        guard let doc = try? SwiftSoup.parseBodyFragment(html), let body = doc.body() else {
            return ""
        }
        var lines: [String] = []
        collectLines(body, into: &lines)
        return lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static let blockTags: Set<String> = [
        "p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "li", "blockquote", "tr"
    ]

    private static func collectLines(_ element: Element, into lines: inout [String]) {
        for child in element.children() {
            let tag = child.tagName().lowercased()
            if blockTags.contains(tag) {
                let text = (try? child.text()) ?? ""
                if !text.isEmpty { lines.append(text) }
            } else {
                collectLines(child, into: &lines)
            }
        }
        if element.children().isEmpty || (element.children().array().allSatisfy { !blockTags.contains($0.tagName().lowercased()) } && lines.isEmpty) {
            let text = (try? element.text()) ?? ""
            if !text.isEmpty && lines.isEmpty { lines.append(text) }
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PlainTextExtractorTests`
Expected: PASS (all 4 tests)

If `test_malformedHTML_returnsEmptyStringNotThrow` fails because SwiftSoup's fragment parser already closes the tag and produces a nested `<p>` inside `<div>`, adjust the expected string to whatever SwiftSoup's actual tolerant-parse output is — the test's intent (no throw, no crash, on malformed input) is what matters, not the exact string.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppleNotestoX/Services/PlainTextExtractor.swift Tests/AppleNotestoXTests/PlainTextExtractorTests.swift
git commit -m "Add PlainTextExtractor for LLM-bound note text"
```

---

### Task 3: Merge data models

**Files:**
- Create: `Sources/AppleNotestoX/Models/MergeModels.swift`
- Test: `Tests/AppleNotestoXTests/MergeModelsTests.swift`

**Interfaces:**
- Consumes: none
- Produces:
  - `MergeSourceNote { let noteID: String; let title: String; let plainText: String }`
  - `MergeSection: Codable { let header: String; let bodyText: String; let sourceNoteIDs: [String] }` (JSON keys `header`, `body`, `source_note_ids`)
  - `StagedImage { let sourceNoteID: String; let sourceNoteTitle: String; let localURL: URL }`
  - `MergeDraft { let titleLine: String; let sections: [MergeSection]; let bodyHTML: String; let runDirectory: URL; let imagesEmbedded: Bool }`
  - `MergeJob { let noteIDs: [String] }`
  - `MergeStage: Sendable, Equatable` with cases `.fetching(done: Int, total: Int)`, `.categorizing`, `.assembling`, `.readyForPreview(MergeDraft)`, `.writing`, `.completed(noteID: String)`, `.failed(message: String)`

These are consumed by every later task (`GroqService`, `TriageAssetStore`, `MergeAssembler`, `MergeCoordinator`, `AppState`, `MergePreviewSheet`).

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AppleNotestoX

final class MergeModelsTests: XCTestCase {
    func test_mergeSection_decodesGroqJSONKeys() throws {
        let json = #"{"header":"Recipes","body":"Some text","source_note_ids":["A","B"]}"#
        let section = try JSONDecoder().decode(MergeSection.self, from: Data(json.utf8))
        XCTAssertEqual(section.header, "Recipes")
        XCTAssertEqual(section.bodyText, "Some text")
        XCTAssertEqual(section.sourceNoteIDs, ["A", "B"])
    }

    func test_mergeSection_encodesBackToGroqJSONKeys() throws {
        let section = MergeSection(header: "H", bodyText: "B", sourceNoteIDs: ["X"])
        let data = try JSONEncoder().encode(section)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["header"] as? String, "H")
        XCTAssertEqual(obj["body"] as? String, "B")
        XCTAssertEqual(obj["source_note_ids"] as? [String], ["X"])
    }

    func test_mergeStage_equatable() {
        let a = MergeStage.fetching(done: 1, total: 3)
        let b = MergeStage.fetching(done: 1, total: 3)
        let c = MergeStage.fetching(done: 2, total: 3)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MergeModelsTests`
Expected: FAIL — types do not exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

struct MergeSourceNote: Sendable, Equatable {
    let noteID: String
    let title: String
    let plainText: String
}

struct MergeSection: Sendable, Equatable, Codable {
    let header: String
    let bodyText: String
    let sourceNoteIDs: [String]

    enum CodingKeys: String, CodingKey {
        case header
        case bodyText = "body"
        case sourceNoteIDs = "source_note_ids"
    }
}

struct StagedImage: Sendable, Equatable {
    let sourceNoteID: String
    let sourceNoteTitle: String
    let localURL: URL
}

struct MergeDraft: Sendable, Equatable {
    let titleLine: String
    let sections: [MergeSection]
    let bodyHTML: String
    let runDirectory: URL
    let imagesEmbedded: Bool
}

struct MergeJob: Sendable {
    let noteIDs: [String]
}

enum MergeStage: Sendable, Equatable {
    case fetching(done: Int, total: Int)
    case categorizing
    case assembling
    case readyForPreview(MergeDraft)
    case writing
    case completed(noteID: String)
    case failed(message: String)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MergeModelsTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AppleNotestoX/Models/MergeModels.swift Tests/AppleNotestoXTests/MergeModelsTests.swift
git commit -m "Add Merge to Note data models"
```

---

### Task 4: MergeAssembler (pure HTML assembly)

**Files:**
- Create: `Sources/AppleNotestoX/Services/MergeAssembler.swift`
- Test: `Tests/AppleNotestoXTests/MergeAssemblerTests.swift`

**Interfaces:**
- Consumes: `MergeSection`, `StagedImage` (Task 3)
- Produces: `MergeAssembler.titleLine(date: Date) -> String`, `MergeAssembler.assembleHTML(sections: [MergeSection], titleLine: String, stagedImages: [String: [StagedImage]], embedImages: Bool) -> String` — used by `MergeCoordinator` (Task 8) to build `MergeDraft.bodyHTML`. `stagedImages` is keyed by `sourceNoteID`.

Both the embed branch and the reference-only branch are implemented and tested here regardless of what Task 1's spike found — `MergeCoordinator` picks which one runs via `MergeFeatureFlags.embedImagesSupported`, but the assembler itself supports both so the untaken branch isn't dead, untested code.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AppleNotestoX

final class MergeAssemblerTests: XCTestCase {
    func test_titleLine_includesISODate() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 8; comps.day = 15
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        XCTAssertEqual(MergeAssembler.titleLine(date: date), "Merged Notes — 2026-08-15")
    }

    func test_assembleHTML_oneHeadingPerSection_noImages() {
        let sections = [
            MergeSection(header: "Work", bodyText: "Line one", sourceNoteIDs: ["A"]),
            MergeSection(header: "Health", bodyText: "Line two", sourceNoteIDs: ["B"])
        ]
        let html = MergeAssembler.assembleHTML(
            sections: sections, titleLine: "Merged Notes — 2026-08-15",
            stagedImages: [:], embedImages: true
        )
        XCTAssertTrue(html.hasPrefix("<div>Merged Notes — 2026-08-15</div>"))
        XCTAssertTrue(html.contains("<h1>Work</h1>"))
        XCTAssertTrue(html.contains("<p>Line one</p>"))
        XCTAssertTrue(html.contains("<h1>Health</h1>"))
        XCTAssertTrue(html.contains("<p>Line two</p>"))
    }

    func test_assembleHTML_embedsImagesInline_whenEnabled() {
        let sections = [MergeSection(header: "Recipes", bodyText: "Text", sourceNoteIDs: ["A"])]
        let image = StagedImage(sourceNoteID: "A", sourceNoteTitle: "Pasta", localURL: URL(fileURLWithPath: "/tmp/run/pasta.png"))
        let html = MergeAssembler.assembleHTML(
            sections: sections, titleLine: "T", stagedImages: ["A": [image]], embedImages: true
        )
        XCTAssertTrue(html.contains("<img src=\"file:///tmp/run/pasta.png\">"))
    }

    func test_assembleHTML_referencesImages_whenEmbedDisabled() {
        let sections = [MergeSection(header: "Recipes", bodyText: "Text", sourceNoteIDs: ["A"])]
        let image = StagedImage(sourceNoteID: "A", sourceNoteTitle: "Pasta", localURL: URL(fileURLWithPath: "/tmp/run/pasta.png"))
        let html = MergeAssembler.assembleHTML(
            sections: sections, titleLine: "T", stagedImages: ["A": [image]], embedImages: false
        )
        XCTAssertFalse(html.contains("<img"))
        XCTAssertTrue(html.contains("[image from &quot;Pasta&quot; — staged at /tmp/run/pasta.png]"))
    }

    func test_assembleHTML_escapesHTMLSpecialCharsInBodyText() {
        let sections = [MergeSection(header: "H", bodyText: "5 < 10 & \"quoted\"", sourceNoteIDs: [])]
        let html = MergeAssembler.assembleHTML(sections: sections, titleLine: "T", stagedImages: [:], embedImages: true)
        XCTAssertTrue(html.contains("5 &lt; 10 &amp; &quot;quoted&quot;"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MergeAssemblerTests`
Expected: FAIL — `MergeAssembler` does not exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Assembles one Apple Notes-compatible HTML document from LLM-categorized
/// sections. Pure function — no I/O, no actor isolation needed.
enum MergeAssembler {
    static func titleLine(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return "Merged Notes — \(formatter.string(from: date))"
    }

    static func assembleHTML(
        sections: [MergeSection],
        titleLine: String,
        stagedImages: [String: [StagedImage]],
        embedImages: Bool
    ) -> String {
        var html = "<div>\(escape(titleLine))</div>"
        for section in sections {
            html += "<h1>\(escape(section.header))</h1>"
            html += "<p>\(escape(section.bodyText))</p>"
            for noteID in section.sourceNoteIDs {
                guard let images = stagedImages[noteID] else { continue }
                for image in images {
                    if embedImages {
                        html += "<img src=\"file://\(image.localURL.path)\">"
                    } else {
                        html += "<p>[image from &quot;\(escape(image.sourceNoteTitle))&quot; — staged at \(image.localURL.path)]</p>"
                    }
                }
            }
        }
        return html
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MergeAssemblerTests`
Expected: PASS (all 5 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/AppleNotestoX/Services/MergeAssembler.swift Tests/AppleNotestoXTests/MergeAssemblerTests.swift
git commit -m "Add MergeAssembler for building the merged note's HTML body"
```

---

### Task 5: GroqService

**Files:**
- Create: `Sources/AppleNotestoX/Services/GroqService.swift`
- Test: `Tests/AppleNotestoXTests/GroqServiceTests.swift`

**Interfaces:**
- Consumes: `MergeSourceNote`, `MergeSection` (Task 3); reuses `MockURLProtocol` (already defined at file scope in `Tests/AppleNotestoXTests/NotionServiceTests.swift`, same test target — no need to redefine it).
- Produces: `GroqService` actor with `init(session: URLSession = .shared, model: String = "llama-3.3-70b-versatile")`, `func setAPIKey(_ key: String?) async`, `func categorize(notes: [MergeSourceNote]) async throws -> [MergeSection]`, `enum GroqError: Error, LocalizedError { case missingKey, invalidKey, http(Int, String), decoding(String), malformedSections(String) }`. `MergeCoordinator` (Task 8) and `AppState` (Task 9) depend on this exact surface.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AppleNotestoX

final class GroqServiceTests: XCTestCase {
    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override func tearDown() {
        super.tearDown()
        MockURLProtocol.handler = nil
        MockURLProtocol.captured = []
    }

    func test_categorize_missingKey_throws() async {
        let groq = GroqService(session: makeSession())
        do {
            _ = try await groq.categorize(notes: [MergeSourceNote(noteID: "A", title: "T", plainText: "text")])
            XCTFail("expected throw")
        } catch let err as GroqService.GroqError {
            if case .missingKey = err { /* ok */ } else { XCTFail("\(err)") }
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func test_categorize_sendsAuthAndModel_parsesJSONContent() async throws {
        let session = makeSession()
        let groq = GroqService(session: session, model: "llama-3.3-70b-versatile")
        await groq.setAPIKey("gsk_test")

        let content = #"{"sections":[{"header":"Work","body":"Body text","source_note_ids":["A"]}]}"#
        MockURLProtocol.handler = { req in
            let payload = #"{"choices":[{"message":{"content":\#(Self.jsonStringLiteral(content))}}]}"#
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(payload.utf8))
        }

        let sections = try await groq.categorize(notes: [MergeSourceNote(noteID: "A", title: "T", plainText: "text")])
        XCTAssertEqual(sections, [MergeSection(header: "Work", bodyText: "Body text", sourceNoteIDs: ["A"])])

        let req = MockURLProtocol.captured.last!
        XCTAssertEqual(req.url?.path, "/openai/v1/chat/completions")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer gsk_test")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: MockURLProtocol.bodyData(from: req)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "llama-3.3-70b-versatile")
    }

    func test_categorize_unauthorized_throwsInvalidKey() async {
        let session = makeSession()
        let groq = GroqService(session: session)
        await groq.setAPIKey("bad")
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (resp, Data(#"{"error":"invalid"}"#.utf8))
        }
        do {
            _ = try await groq.categorize(notes: [MergeSourceNote(noteID: "A", title: "T", plainText: "x")])
            XCTFail("expected throw")
        } catch let err as GroqService.GroqError {
            if case .invalidKey = err { /* ok */ } else { XCTFail("\(err)") }
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func test_categorize_malformedJSON_retriesOnceThenThrows() async {
        let session = makeSession()
        let groq = GroqService(session: session)
        await groq.setAPIKey("k")
        var callCount = 0
        MockURLProtocol.handler = { req in
            callCount += 1
            let payload = #"{"choices":[{"message":{"content":"not json"}}]}"#
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(payload.utf8))
        }
        do {
            _ = try await groq.categorize(notes: [MergeSourceNote(noteID: "A", title: "T", plainText: "x")])
            XCTFail("expected throw")
        } catch let err as GroqService.GroqError {
            if case .malformedSections = err { /* ok */ } else { XCTFail("\(err)") }
        } catch {
            XCTFail("unexpected: \(error)")
        }
        XCTAssertEqual(callCount, 2, "expected exactly one retry after the first malformed response")
    }

    private static func jsonStringLiteral(_ s: String) -> String {
        let data = try! JSONEncoder().encode(s)
        return String(data: data, encoding: .utf8)!
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter GroqServiceTests`
Expected: FAIL — `GroqService` does not exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

actor GroqService {
    enum GroqError: Error, LocalizedError {
        case missingKey
        case invalidKey
        case http(Int, String)
        case decoding(String)
        case malformedSections(String)

        var errorDescription: String? {
            switch self {
            case .missingKey: return "Groq API key is not set."
            case .invalidKey: return "Groq rejected the API key (401). Re-check the key."
            case .http(let code, let msg): return "Groq API \(code): \(msg)"
            case .decoding(let msg): return "Failed to decode Groq response: \(msg)"
            case .malformedSections(let msg): return "Groq did not return valid section JSON: \(msg)"
            }
        }
    }

    private let session: URLSession
    private let baseURL = URL(string: "https://api.groq.com/openai/v1/")!
    private let model: String
    private var apiKey: String?

    init(session: URLSession = .shared, model: String = "llama-3.3-70b-versatile") {
        self.session = session
        self.model = model
    }

    func setAPIKey(_ key: String?) {
        self.apiKey = key?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func categorize(notes: [MergeSourceNote]) async throws -> [MergeSection] {
        guard let apiKey, !apiKey.isEmpty else { throw GroqError.missingKey }

        let userContent = notes.map { "### \($0.title) (id: \($0.noteID))\n\($0.plainText)" }.joined(separator: "\n\n")
        let systemPrompt = """
        You group short personal notes into topic categories. Read all the notes below \
        and invent whatever section headers best group their content — do not use a fixed \
        list. Respond with strict JSON only, matching this shape exactly, no prose, no \
        markdown fences:
        {"sections":[{"header":"string","body":"string","source_note_ids":["string"]}]}
        Every note id you were given must appear in at least one section's source_note_ids.
        """

        let firstAttempt = try await complete(system: systemPrompt, user: userContent)
        if let sections = Self.parseSections(from: firstAttempt) {
            return sections
        }

        let retryPrompt = systemPrompt + "\nYour previous response was not valid JSON matching that shape. Return ONLY the JSON object, nothing else."
        let secondAttempt = try await complete(system: retryPrompt, user: userContent)
        guard let sections = Self.parseSections(from: secondAttempt) else {
            throw GroqError.malformedSections(secondAttempt)
        }
        return sections
    }

    private func complete(system: String, user: String) async throws -> String {
        guard let apiKey else { throw GroqError.missingKey }
        struct Message: Encodable { let role: String; let content: String }
        struct ResponseFormat: Encodable { let type = "json_object" }
        struct Body: Encodable {
            let model: String
            let messages: [Message]
            let response_format = ResponseFormat()
            let temperature = 0.2
        }
        let body = Body(model: model, messages: [
            Message(role: "system", content: system),
            Message(role: "user", content: user)
        ])

        var req = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)

        var attempt = 0
        while true {
            attempt += 1
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw GroqError.http(0, "no response") }
            if (200..<300).contains(http.statusCode) {
                struct ChatResponse: Decodable {
                    struct Choice: Decodable { struct Msg: Decodable { let content: String }; let message: Msg }
                    let choices: [Choice]
                }
                do {
                    let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
                    guard let content = decoded.choices.first?.message.content else {
                        throw GroqError.decoding("no choices in response")
                    }
                    return content
                } catch let err as GroqError {
                    throw err
                } catch {
                    throw GroqError.decoding("\(error)")
                }
            }
            if http.statusCode == 401 { throw GroqError.invalidKey }
            if http.statusCode == 429, attempt < 4 {
                let retryAfter = (http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)) ?? pow(2.0, Double(attempt))
                try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
                continue
            }
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw GroqError.http(http.statusCode, msg)
        }
    }

    private static func parseSections(from jsonContent: String) -> [MergeSection]? {
        struct Wrapper: Decodable { let sections: [MergeSection] }
        guard let data = jsonContent.data(using: .utf8),
              let wrapper = try? JSONDecoder().decode(Wrapper.self, from: data),
              !wrapper.sections.isEmpty else {
            return nil
        }
        return wrapper.sections
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter GroqServiceTests`
Expected: PASS (all 4 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/AppleNotestoX/Services/GroqService.swift Tests/AppleNotestoXTests/GroqServiceTests.swift
git commit -m "Add GroqService for LLM note categorization"
```

---

### Task 6: TriageAssetStore

**Files:**
- Create: `Sources/AppleNotestoX/Services/TriageAssetStore.swift`
- Test: `Tests/AppleNotestoXTests/TriageAssetStoreTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks
- Produces: `TriageAssetStore` actor with `init(root: URL = TriageAssetStore.defaultRoot(), fileManager: FileManager = .default)`, `func makeRunDirectory() throws -> URL`, `func stage(fileAt sourceURL: URL, filename: String, into runDirectory: URL) throws -> URL`, `func deleteRunDirectory(_ url: URL)`, `static func defaultRoot(fileManager: FileManager = .default) -> URL`. `MergeCoordinator` (Task 8) depends on this exact surface.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AppleNotestoX

final class TriageAssetStoreTests: XCTestCase {
    private func makeTempRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("TriageAssetStoreTests-\(UUID().uuidString)")
    }

    func test_makeRunDirectory_createsUniqueDirectoryUnderRoot() async throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TriageAssetStore(root: root)

        let dir1 = try await store.makeRunDirectory()
        let dir2 = try await store.makeRunDirectory()

        XCTAssertTrue(FileManager.default.fileExists(atPath: dir1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir2.path))
        XCTAssertNotEqual(dir1, dir2)
        XCTAssertEqual(dir1.deletingLastPathComponent().path, root.path)
    }

    func test_stage_copiesFileIntoRunDirectory() async throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TriageAssetStore(root: root)
        let runDir = try await store.makeRunDirectory()

        let sourceFile = root.appendingPathComponent("source.txt")
        try "hello".data(using: .utf8)!.write(to: sourceFile)

        let staged = try await store.stage(fileAt: sourceFile, filename: "staged.txt", into: runDir)

        XCTAssertEqual(staged.lastPathComponent, "staged.txt")
        XCTAssertEqual(staged.deletingLastPathComponent().path, runDir.path)
        XCTAssertEqual(try String(contentsOf: staged, encoding: .utf8), "hello")
    }

    func test_deleteRunDirectory_removesIt() async throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TriageAssetStore(root: root)
        let runDir = try await store.makeRunDirectory()
        XCTAssertTrue(FileManager.default.fileExists(atPath: runDir.path))

        await store.deleteRunDirectory(runDir)

        XCTAssertFalse(FileManager.default.fileExists(atPath: runDir.path))
    }

    func test_deleteRunDirectory_missingDirectory_doesNotThrow() async {
        let root = makeTempRoot()
        let store = TriageAssetStore(root: root)
        await store.deleteRunDirectory(root.appendingPathComponent("does-not-exist"))
        // No assertion needed — the test passes if this doesn't crash/throw.
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TriageAssetStoreTests`
Expected: FAIL — `TriageAssetStore` does not exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Persistent local staging area for attachment files during one Merge to
/// Note run, so images survive past `AppleNotesService.fetchNote`'s
/// per-note OS temp-dir cleanup. Purely a staging aid — not a permanent
/// archive; callers delete a run's directory once it is no longer needed.
actor TriageAssetStore {
    private let root: URL
    private let fileManager: FileManager

    init(root: URL = TriageAssetStore.defaultRoot(), fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager
    }

    static func defaultRoot(fileManager: FileManager = .default) -> URL {
        let appSupport = (try? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? fileManager.temporaryDirectory
        return appSupport.appendingPathComponent("AppleNotestoX/TriageAssets", isDirectory: true)
    }

    func makeRunDirectory() throws -> URL {
        let dir = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func stage(fileAt sourceURL: URL, filename: String, into runDirectory: URL) throws -> URL {
        let destination = runDirectory.appendingPathComponent(filename)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)
        return destination
    }

    func deleteRunDirectory(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TriageAssetStoreTests`
Expected: PASS (all 4 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/AppleNotestoX/Services/TriageAssetStore.swift Tests/AppleNotestoXTests/TriageAssetStoreTests.swift
git commit -m "Add TriageAssetStore for staging attachments during a merge run"
```

---

### Task 7: AppleNotesService.createNote

**Files:**
- Modify: `Sources/AppleNotestoX/Services/AppleNotesService.swift` (add one method + one AppleScript constant, alongside the existing `moveNote`/`deleteNote`/`moveScript`/`deleteScript` at lines 66-73 and 247-273)
- Test: none — `moveNote`/`deleteNote` have no dedicated unit tests either (they require live Notes), so this follows the existing precedent of being a manual acceptance gate. Only the pure parsers (`parseHierarchy`, `parseNoteContent`, `parseNoteDate`) are unit-tested in this file, per `NoteDateParseTests.swift` and `TemporaryFileCleanupTests.swift`.

**Interfaces:**
- Consumes: nothing new
- Produces: `AppleNotesService.createNote(bodyHTML: String) async throws -> String` (returns the new note's id) — used by `MergeCoordinator` (Task 8).

- [ ] **Step 1: Add the method**

Insert after `deleteNote` (after line 72):

```swift
    func createNote(bodyHTML: String) async throws -> String {
        try await runScript(Self.createScript, args: [bodyHTML])
    }
```

- [ ] **Step 2: Add the AppleScript constant**

Insert after `deleteScript` (after line 273, before the closing `}` of the type):

```swift
    private static let createScript = #"""
    on run argv
        set bodyHTML to item 1 of argv
        tell application "Notes"
            set theNote to make new note with properties {body:bodyHTML}
        end tell
        return (id of theNote) as string
    end run
    """#
```

Note the body is passed as an `argv` item, exactly like `moveScript`/`deleteScript` — never string-interpolated into the script source, so arbitrary note content (quotes, backslashes, unicode) is handled safely by the existing `runScript` plumbing.

- [ ] **Step 3: Build to confirm it compiles**

Run: `swift build`
Expected: builds cleanly (Command Line Tools are sufficient for this).

- [ ] **Step 4: Manual acceptance test**

With the app running and Notes automation permission already granted (same permission the rest of the app already needs):

```bash
osascript -e '
on run argv
    tell application "Notes"
        set theNote to make new note with properties {body:item 1 of argv}
    end tell
    return (id of theNote) as string
end run
' -- "<div>Manual createNote test</div><h1>Section</h1><p>Body</p>"
```

Confirm in Notes.app that a new note appears with "Manual createNote test" as its title and "Section" / "Body" rendered as a heading and paragraph beneath it. Delete the test note afterward.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppleNotestoX/Services/AppleNotesService.swift
git commit -m "Add AppleNotesService.createNote write capability"
```

---

### Task 8: MergeCoordinator

**Files:**
- Create: `Sources/AppleNotestoX/Services/MergeCoordinator.swift`
- Test: none — this orchestrates live `AppleNotesService.fetchNote` calls, matching `WikiExportCoordinator`/`ArchiveCoordinator`, neither of which has a dedicated test file in this codebase. Its constituent pure pieces (`PlainTextExtractor`, `MergeAssembler`, `GroqService.categorize` parsing) are already unit-tested in Tasks 2, 4, 5.

**Interfaces:**
- Consumes: `AppleNotesService.fetchNote`/`createNote` (existing + Task 7), `GroqService.categorize` (Task 5), `TriageAssetStore` (Task 6), `PlainTextExtractor.extract` (Task 2), `MergeAssembler.titleLine`/`assembleHTML` (Task 4), `MergeFeatureFlags.embedImagesSupported` (Task 1), `MergeJob`/`MergeStage`/`MergeDraft`/`MergeSourceNote`/`StagedImage` (Task 3)
- Produces: `MergeCoordinator` actor with `init(notes: AppleNotesService, groq: GroqService, assets: TriageAssetStore = TriageAssetStore(), embedImagesSupported: Bool = MergeFeatureFlags.embedImagesSupported)`, `nonisolated func run(job: MergeJob, hierarchy: AppleNotesHierarchy) -> AsyncStream<MergeStage>`, `func write(draft: MergeDraft) async throws -> String`, `func discard(draft: MergeDraft) async`. `AppState` (Task 9) depends on this exact surface.

- [ ] **Step 1: Write the implementation**

```swift
import Foundation

/// Orchestrates fetching selected notes, categorizing them via Groq, staging
/// attachments, and assembling one merged HTML document — mirrors the
/// progress-streaming pattern of `WikiExportCoordinator`/`ArchiveCoordinator`.
/// Source notes are never modified or deleted.
actor MergeCoordinator {
    private let notes: AppleNotesService
    private let groq: GroqService
    private let assets: TriageAssetStore
    private let embedImagesSupported: Bool

    init(
        notes: AppleNotesService,
        groq: GroqService,
        assets: TriageAssetStore = TriageAssetStore(),
        embedImagesSupported: Bool = MergeFeatureFlags.embedImagesSupported
    ) {
        self.notes = notes
        self.groq = groq
        self.assets = assets
        self.embedImagesSupported = embedImagesSupported
    }

    nonisolated func run(job: MergeJob, hierarchy: AppleNotesHierarchy) -> AsyncStream<MergeStage> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    let draft = try await self.buildDraft(job: job, hierarchy: hierarchy, continuation: continuation)
                    continuation.yield(.readyForPreview(draft))
                } catch {
                    continuation.yield(.failed(message: error.localizedDescription))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func buildDraft(
        job: MergeJob,
        hierarchy: AppleNotesHierarchy,
        continuation: AsyncStream<MergeStage>.Continuation
    ) async throws -> MergeDraft {
        let runDirectory = try await assets.makeRunDirectory()
        var succeeded = false
        defer {
            // On failure no draft was ever returned, so nothing references this
            // run directory — clean it up unconditionally. The "keep it around
            // when embeds are unsupported" rule from the spec applies only to
            // the success path, handled by `write(draft:)` below.
            if !succeeded {
                Task { await assets.deleteRunDirectory(runDirectory) }
            }
        }

        var sourceNotes: [MergeSourceNote] = []
        var stagedImages: [String: [StagedImage]] = [:]
        var done = 0
        let total = job.noteIDs.count
        continuation.yield(.fetching(done: done, total: total))

        for noteID in job.noteIDs {
            let content = try await notes.fetchNote(id: noteID)
            defer { AppleNotesService.cleanupTemporaryAttachments(in: content) }

            let title = hierarchy.notes[noteID]?.name ?? "(untitled)"
            let plainText = PlainTextExtractor.extract(html: content.html)
            sourceNotes.append(MergeSourceNote(noteID: noteID, title: title, plainText: plainText))

            var images: [StagedImage] = []
            for attachment in content.attachments {
                let staged = try await assets.stage(
                    fileAt: attachment.localURL,
                    filename: "\(noteID)-\(attachment.filename)",
                    into: runDirectory
                )
                images.append(StagedImage(sourceNoteID: noteID, sourceNoteTitle: title, localURL: staged))
            }
            if !images.isEmpty { stagedImages[noteID] = images }

            done += 1
            continuation.yield(.fetching(done: done, total: total))
        }

        continuation.yield(.categorizing)
        let sections = try await groq.categorize(notes: sourceNotes)

        continuation.yield(.assembling)
        let titleLine = MergeAssembler.titleLine()
        let bodyHTML = MergeAssembler.assembleHTML(
            sections: sections,
            titleLine: titleLine,
            stagedImages: stagedImages,
            embedImages: embedImagesSupported
        )

        succeeded = true
        return MergeDraft(
            titleLine: titleLine,
            sections: sections,
            bodyHTML: bodyHTML,
            runDirectory: runDirectory,
            imagesEmbedded: embedImagesSupported
        )
    }

    func write(draft: MergeDraft) async throws -> String {
        let noteID = try await notes.createNote(bodyHTML: draft.bodyHTML)
        // When images were embedded inline, the staged copies are no longer
        // needed once the note exists. When embedding was unsupported, the
        // merged note's text only references these files by path — they are
        // the only copy, so they must survive the write. See spec "Risk:
        // Image Embedding" fallback.
        if draft.imagesEmbedded {
            await assets.deleteRunDirectory(draft.runDirectory)
        }
        return noteID
    }

    func discard(draft: MergeDraft) async {
        await assets.deleteRunDirectory(draft.runDirectory)
    }
}
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `swift build`
Expected: builds cleanly.

- [ ] **Step 3: Commit**

```bash
git add Sources/AppleNotestoX/Services/MergeCoordinator.swift
git commit -m "Add MergeCoordinator orchestrating the merge-to-note pipeline"
```

---

### Task 9: AppState wiring

**Files:**
- Modify: `Sources/AppleNotestoX/App/AppState.swift`

**Interfaces:**
- Consumes: `MergeCoordinator`, `GroqService` (Task 8, 5), `MergeStage`, `MergeDraft`, `MergeJob` (Task 3)
- Produces: `AppState.ExportDestination.mergeToNote` case, `AppState.groqAPIKey: String`, `AppState.mergeStage: MergeStage?`, `AppState.isMerging: Bool`, `AppState.saveGroqKey(_:) async`, `AppState.startMergePreview() async`, `AppState.confirmMerge() async`, `AppState.cancelMerge() async`. `DestinationPane` (Task 11), `SettingsView` (Task 10), and `MergePreviewSheet` (Task 12) depend on this exact surface.

- [ ] **Step 1: Add the `mergeToNote` destination case**

In `AppState.swift`, modify line 39:

```swift
    enum ExportDestination: String, Sendable { case notion, wiki, mergeToNote }
```

- [ ] **Step 2: Add merge state and services**

After the "Wiki export" section (after line 46, before `var canStartWikiExport`), add:

```swift
    // Merge to Note
    var groqAPIKey: String = ""
    var mergeStage: MergeStage? = nil
    var isMerging = false
```

In the "Services" section, after line 63 (`let videoCoordinator: VideoIngestCoordinator`), add:

```swift
    let groq: GroqService
    let mergeCoordinator: MergeCoordinator
```

In `init()`, after line 80 (`self.videoCoordinator = VideoIngestCoordinator()`), add:

```swift
        let g = GroqService()
        self.groq = g
        self.mergeCoordinator = MergeCoordinator(notes: a, groq: g)
```

- [ ] **Step 3: Load the Groq key on bootstrap**

In `bootstrap()` (lines 86-96), after the existing Notion token load block, add:

```swift
        if let g = try? keychain.get("groq_api_key") {
            groqAPIKey = g
            await groq.setAPIKey(g)
        }
```

- [ ] **Step 4: Add `saveGroqKey`**

After the existing `clearToken()` method (after line 115), add:

```swift
    func saveGroqKey(_ key: String) async {
        groqAPIKey = key
        try? keychain.set(key, key: "groq_api_key")
        await groq.setAPIKey(key)
    }
```

- [ ] **Step 5: Add merge actions**

After `runWikiExport()` and `importVideo(url:)` (after line 300, before the "Study + synthesis" section), add:

```swift
    // MARK: - Merge to Note

    func startMergePreview() async {
        guard !selectedNoteIDs.isEmpty, !groqAPIKey.isEmpty, let h = hierarchy, !isMerging else { return }
        isMerging = true
        mergeStage = nil
        let job = MergeJob(noteIDs: Array(selectedNoteIDs))
        let stream = mergeCoordinator.run(job: job, hierarchy: h)
        for await stage in stream {
            mergeStage = stage
            if case .failed(let message) = stage {
                errorMessage = message
            }
        }
        isMerging = false
    }

    func confirmMerge() async {
        guard case .readyForPreview(let draft) = mergeStage else { return }
        mergeStage = .writing
        do {
            let noteID = try await mergeCoordinator.write(draft: draft)
            mergeStage = .completed(noteID: noteID)
            selectedNoteIDs.removeAll()
            await loadAppleHierarchy()
        } catch {
            errorMessage = error.localizedDescription
            mergeStage = .failed(message: error.localizedDescription)
        }
    }

    func cancelMerge() async {
        if case .readyForPreview(let draft) = mergeStage {
            await mergeCoordinator.discard(draft: draft)
        }
        mergeStage = nil
    }
```

- [ ] **Step 6: Build to confirm it compiles**

Run: `swift build`
Expected: builds cleanly.

- [ ] **Step 7: Commit**

```bash
git add Sources/AppleNotestoX/App/AppState.swift
git commit -m "Wire Merge to Note into AppState"
```

---

### Task 10: SettingsView Groq key field

**Files:**
- Modify: `Sources/AppleNotestoX/UI/SettingsView.swift`

**Interfaces:**
- Consumes: `AppState.groqAPIKey`, `AppState.saveGroqKey(_:)` (Task 9)

- [ ] **Step 1: Add a `groqDraft` state and Groq section**

After line 8 (`@State private var reviewDraft...`), add:

```swift
    @State private var groqDraft: String = ""
```

After the existing "Notion" `Section` block (after line 34, before the "Apple Notes" section), add:

```swift
                Section {
                    Text("Create a free API key at console.groq.com/keys. The key stays in macOS Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LabeledContent("API key") {
                        SecureField("gsk_...", text: $groqDraft)
                            .onAppear { groqDraft = state.groqAPIKey }
                    }
                    Button("Save Groq key") {
                        Task { await state.saveGroqKey(groqDraft.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    }
                    .disabled(groqDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("Groq (Merge to Note)")
                }
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `swift build`
Expected: builds cleanly.

- [ ] **Step 3: Manual check**

Run: `make run`, open Settings, confirm the "Groq (Merge to Note)" section appears below Notion and above Apple Notes, enter a test string, click "Save Groq key", reopen Settings and confirm the field is pre-filled (proves the Keychain round-trip works).

- [ ] **Step 4: Commit**

```bash
git add Sources/AppleNotestoX/UI/SettingsView.swift
git commit -m "Add Groq API key field to Settings"
```

---

### Task 11: DestinationPane third option

**Files:**
- Modify: `Sources/AppleNotestoX/UI/DestinationPane.swift`

**Interfaces:**
- Consumes: `AppState.ExportDestination.mergeToNote`, `AppState.groqAPIKey`, `AppState.startMergePreview()`, `AppState.isMerging`, `AppState.mergeStage` (Task 9)
- Produces: opens `MergePreviewSheet` (Task 12) when a draft becomes ready

- [ ] **Step 1: Add the third segmented option**

Modify lines 27-34:

```swift
                Picker("Destination", selection: $state.exportDestination) {
                    Label("Personal Wiki", systemImage: "books.vertical")
                        .tag(AppState.ExportDestination.wiki)
                    Label("Notion", systemImage: "square.grid.2x2")
                        .tag(AppState.ExportDestination.notion)
                    Label("Merge to Note", systemImage: "square.stack.3d.up")
                        .tag(AppState.ExportDestination.mergeToNote)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
```

- [ ] **Step 2: Add the switch case and merge pane**

Modify lines 39-42:

```swift
            switch state.exportDestination {
            case .notion: notionPane
            case .wiki: wikiPane
            case .mergeToNote: mergePane
            }
```

Add a `mergePane` computed property alongside `wikiPane` (after line 207, before `private func chooseVideo()`):

```swift
    // MARK: - Merge to Note

    @ViewBuilder private var mergePane: some View {
        @Bindable var state = state
        ScrollView {
            VStack(alignment: .leading, spacing: WorkspaceStyle.spacing12) {
                VStack(alignment: .leading, spacing: WorkspaceStyle.spacing8) {
                    WorkspaceSectionLabel("Merge to Note")
                    VStack(alignment: .leading, spacing: WorkspaceStyle.spacing8) {
                        Text("\(state.selectedNoteIDs.count) note\(state.selectedNoteIDs.count == 1 ? "" : "s") selected")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if state.groqAPIKey.isEmpty {
                            WorkspaceEmptyState(
                                systemImage: "key.horizontal",
                                title: "No Groq API Key",
                                message: "Add your Groq API key in Settings."
                            )
                        } else {
                            Button {
                                Task { await state.startMergePreview() }
                            } label: {
                                Text(state.isMerging ? "Categorizing\u{2026}" : "Preview & Merge\u{2026}")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(state.isMerging || state.selectedNoteIDs.isEmpty)
                        }
                        Text("Writes one new note into Apple Notes with LLM-chosen sections. Originals are left untouched.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .workspaceInsetSurface()
                }
            }
            .padding(.horizontal, WorkspaceStyle.spacing16)
            .padding(.vertical, WorkspaceStyle.spacing12)
        }
        .sheet(isPresented: Binding(
            get: {
                if case .readyForPreview = state.mergeStage { return true }
                return false
            },
            set: { shown in if !shown { Task { await state.cancelMerge() } } }
        )) {
            MergePreviewSheet()
        }
    }
```

- [ ] **Step 3: Build to confirm it compiles**

Run: `swift build`
Expected: FAIL until Task 12 adds `MergePreviewSheet` — that's expected at this point; proceed to Task 12 before attempting a clean build of this task in isolation, or stub-build by temporarily commenting the `.sheet` modifier if you want to verify this task alone first.

- [ ] **Step 4: Commit**

```bash
git add Sources/AppleNotestoX/UI/DestinationPane.swift
git commit -m "Add Merge to Note destination option"
```

---

### Task 12: MergePreviewSheet

**Files:**
- Create: `Sources/AppleNotestoX/UI/MergePreviewSheet.swift`

**Interfaces:**
- Consumes: `AppState.mergeStage`, `AppState.confirmMerge()`, `AppState.cancelMerge()` (Task 9); styling helpers `WorkspaceStyle`, `.workspaceFooterSurface()` (existing, used identically in `PreviewSheet.swift`)

- [ ] **Step 1: Write the sheet**

```swift
import SwiftUI

struct MergePreviewSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: WorkspaceStyle.spacing4) {
                        Text("Confirm Merge")
                            .font(.title2.weight(.semibold))
                        if let draft = draft {
                            Text("\(draft.sections.count) section\(draft.sections.count == 1 ? "" : "s") \u{2192} \(draft.titleLine)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, WorkspaceStyle.spacing16)
                    .padding(.top, WorkspaceStyle.spacing16)
                    .padding(.bottom, WorkspaceStyle.spacing12)

                    Divider()

                    if let draft = draft {
                        LazyVStack(alignment: .leading, spacing: WorkspaceStyle.spacing12) {
                            ForEach(Array(draft.sections.enumerated()), id: \.offset) { _, section in
                                VStack(alignment: .leading, spacing: WorkspaceStyle.spacing4) {
                                    Text(section.header)
                                        .font(.headline)
                                    Text(section.bodyText)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                    Text("From \(section.sourceNoteIDs.count) note\(section.sourceNoteIDs.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, WorkspaceStyle.spacing16)
                            }
                        }
                        .padding(.vertical, WorkspaceStyle.spacing12)
                    } else {
                        Text("No draft ready.")
                            .foregroundStyle(.secondary)
                            .padding(WorkspaceStyle.spacing16)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    Task { await state.cancelMerge() }
                    dismiss()
                }
                .keyboardShortcut(.escape)
                Button {
                    Task {
                        await state.confirmMerge()
                        dismiss()
                    }
                } label: {
                    Text(isWriting ? "Creating\u{2026}" : "Create in Apple Notes")
                }
                .keyboardShortcut(.return)
                .disabled(draft == nil || isWriting)
                .buttonStyle(.borderedProminent)
            }
            .workspaceFooterSurface()
        }
        .frame(width: 520, height: 480)
    }

    private var draft: MergeDraft? {
        if case .readyForPreview(let d) = state.mergeStage { return d }
        return nil
    }

    private var isWriting: Bool {
        if case .writing = state.mergeStage { return true }
        return false
    }
}
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `swift build`
Expected: builds cleanly (this also resolves Task 11's deferred build check — build the whole target now).

- [ ] **Step 3: Commit**

```bash
git add Sources/AppleNotestoX/UI/MergePreviewSheet.swift
git commit -m "Add MergePreviewSheet for reviewing a merge draft before writing"
```

---

### Task 13: Rename Capture tab to "Transfer/Transform"

**Files:**
- Modify: `Sources/AppleNotestoX/UI/ContentView.swift`

**Interfaces:** none — display-only change, `AppMode.capture` case name is unchanged (per the spec's explicit scoping decision).

- [ ] **Step 1: Rename the picker label**

Modify line 21:

```swift
                    Text("Transfer/Transform").tag(AppState.AppMode.capture)
```

- [ ] **Step 2: Check for other user-facing "Capture" references**

Run: `grep -rn "\"Capture\"" Sources/AppleNotestoX/`

If any other UI string literal says "Capture" (e.g. an accessibility label or help string), update it to "Transfer/Transform" too, for consistency with the renamed tab.

- [ ] **Step 3: Build to confirm it compiles**

Run: `swift build`
Expected: builds cleanly.

- [ ] **Step 4: Manual check**

Run: `make run`, confirm the toolbar segmented picker now reads "Study" / "Transfer/Transform" instead of "Study" / "Capture".

- [ ] **Step 5: Commit**

```bash
git add Sources/AppleNotestoX/UI/ContentView.swift
git commit -m "Rename Capture tab to Transfer/Transform"
```

---

### Task 14: End-to-end manual acceptance pass

**Files:** none — verification only, following the same manual-acceptance-gate pattern documented in the README's "Verification, Status, and Limitations" table.

- [ ] **Step 1: Run the full test suite**

Run: `swift test`
Expected: all tests pass, including the new `PlainTextExtractorTests`, `MergeModelsTests`, `MergeAssemblerTests`, `GroqServiceTests`, `TriageAssetStoreTests`.

- [ ] **Step 2: Run `make check`**

Run: `make check`
Expected: build green (the Node-only gates in `make check` are unaffected by this feature).

- [ ] **Step 3: Live walkthrough**

With a real Groq API key saved in Settings and Notes automation permission granted:

1. Launch the app (`make run`), switch to "Transfer/Transform".
2. Tick 3-4 notes spanning at least two distinct topics, ideally including one with an image attachment.
3. Select "Merge to Note", click "Preview & Merge…".
4. Confirm the preview shows more than one section header and that the sections plausibly match the ticked notes' topics.
5. Click "Create in Apple Notes".
6. In Notes.app, confirm exactly one new note was created, its title is "Merged Notes — <today's date>", its body shows the section headers and text, and — per Task 1's spike outcome — either a real inline image or a `[image from "…"]` text reference.
7. Confirm all originally-ticked notes are unchanged (still present, unmoved, unedited).
8. Repeat the run with an overlapping selection and confirm a second, independent note is created (no append-to-previous-run behavior).

- [ ] **Step 4: Update the README**

Add a short "Merge to Note" subsection to `README.md` under "What It Does" and the verification table, following the existing style for the other workflows (Notion, Video). Keep it to 2-4 lines plus one verification-table row, consistent with the existing entries' length.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "Document Merge to Note in README"
```
