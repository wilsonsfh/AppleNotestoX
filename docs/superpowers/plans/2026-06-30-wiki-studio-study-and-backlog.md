# Wiki Studio Pass 1 — Study core + Synthesis backlog — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a study-first surface to AppleNotestoX — one-click *Refresh study data* + *Launch Wiki Review* with the wiki as the visual hero, plus a *synthesis backlog* of `raw/` notes not yet in `wiki/`.

**Architecture:** Small, independently-testable Swift units. Extract the (deadlock-safe) process runner into a shared `ProcessRunner`. `RepoPaths` resolves the `review/` folder (via `#filePath` + a Settings override) and the `node` binary. `StudyDataService` runs `review/generate.mjs` then reads `study-data.js`. `SynthesisBacklog` is pure file-list logic. A top-level `Study | Capture` mode switch shows the new `StudyView` (default) or the unchanged export split.

**Tech Stack:** Swift 6 / SwiftUI / Observation, macOS 14+, Foundation `Process`, `NSWorkspace`, `NSPasteboard`. The generator is Node (existing `review/generate.mjs`, no deps).

## Global Constraints

- Swift tools 6.0, `.macOS(.v14)`; Swift 6 language mode (strict concurrency).
- No new SPM dependencies.
- The app **must not** write into `vault/wiki/` — synthesis stays LLM-owned (vault `AGENTS.md`).
- Reuse existing patterns: `@Observable @MainActor final class AppState`; services are `actor`/`enum`; tests are XCTest with `@testable import AppleNotestoX`.
- XCTest can't run on Command-Line-Tools-only machines (`swift test` → "no such module 'XCTest'"); tests run under Xcode/CI. `swift build` must stay green everywhere.
- Conform to the review app's Direction-B look (indigo accent on near-black); native SwiftUI controls — no Kumo (not a Cloudflare app).

---

### Task 1: Extract `ProcessRunner` (shared, deadlock-safe)

Move `ProcessResult` + `runProcess` + `DataBox` out of `AppleNotesService` into a shared type so `StudyDataService` can reuse it. Behavior is unchanged (concurrent pipe drain).

**Files:**
- Create: `Sources/AppleNotestoX/Services/ProcessRunner.swift`
- Modify: `Sources/AppleNotestoX/Services/AppleNotesService.swift` (remove `DataBox`, `ProcessResult`, `runProcess`; `runScript` calls `ProcessRunner.run`)
- Modify: `Tests/AppleNotestoXTests/ProcessRunnerTests.swift` (call `ProcessRunner.run` → `ProcessRunner.Result`)

**Interfaces:**
- Produces: `enum ProcessRunner { struct Result: Sendable { let stdout: String; let stderr: String; let status: Int32 }; static func run(executableURL: URL, arguments: [String]) async throws -> Result }`

- [ ] **Step 1: Update the existing test to the new home**

In `Tests/AppleNotestoXTests/ProcessRunnerTests.swift`, replace both `AppleNotesService.runProcess(` calls with `ProcessRunner.run(` and the type reference stays `result.status/stdout/stderr`. (Three call sites: large-stdout, stderr, echo.)

- [ ] **Step 2: Run test to verify it fails to compile**

Run: `swift build --build-tests`
Expected: FAIL — `type 'AppleNotesService' has no member 'runProcess'` is gone → now `cannot find 'ProcessRunner' in scope`.

- [ ] **Step 3: Create `ProcessRunner.swift`**

```swift
import Foundation

/// Thread-safe holder so a value read on one queue can be handed back to another.
private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Data()
    func set(_ d: Data) { lock.lock(); value = d; lock.unlock() }
    func get() -> Data { lock.lock(); defer { lock.unlock() }; return value }
}

/// Runs child processes, draining stdout/stderr concurrently so a full OS pipe
/// buffer (~64 KB) can never deadlock `waitUntilExit()`.
enum ProcessRunner {
    struct Result: Sendable {
        let stdout: String
        let stderr: String
        let status: Int32
    }

    static func run(executableURL: URL, arguments: [String]) async throws -> Result {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Result, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = executableURL
                proc.arguments = arguments
                let outPipe = Pipe()
                let errPipe = Pipe()
                proc.standardOutput = outPipe
                proc.standardError = errPipe
                do { try proc.run() } catch { cont.resume(throwing: error); return }

                let errBox = DataBox()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    errBox.set(errPipe.fileHandleForReading.readDataToEndOfFile())
                    group.leave()
                }
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                proc.waitUntilExit()

                let out = String(data: outData, encoding: .utf8) ?? ""
                let err = String(data: errBox.get(), encoding: .utf8) ?? ""
                cont.resume(returning: Result(stdout: out, stderr: err, status: proc.terminationStatus))
            }
        }
    }
}
```

- [ ] **Step 4: Delete the moved code from `AppleNotesService.swift` and rewire `runScript`**

Remove the top-of-file `private final class DataBox { … }`. Remove `struct ProcessResult { … }` and `static func runProcess(…) { … }`. Replace the body of `runScript` to call the shared runner:

```swift
private func runScript(_ source: String, args: [String] = []) async throws -> String {
    var procArgs = ["-e", source]
    if !args.isEmpty {
        procArgs.append("--")
        procArgs.append(contentsOf: args)
    }
    let result = try await ProcessRunner.run(
        executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
        arguments: procArgs
    )
    if result.status != 0 {
        let err = result.stderr
        if err.contains("(-1743)") || err.contains("Not authorized") || err.contains("not allowed") || err.contains("isn't allowed") {
            throw AppleNotesError.permissionDenied
        }
        throw AppleNotesError.scriptFailed(err.isEmpty ? result.stdout : err)
    }
    return result.stdout
}
```

- [ ] **Step 5: Verify build + tests**

Run: `swift build` → Expected: exit 0.
Run (Xcode/CI): `swift test --filter ProcessRunnerTests` → Expected: PASS (large-stdout no-deadlock, stderr/status, echo).

- [ ] **Step 6: Commit**

```bash
git add Sources/AppleNotestoX/Services/ProcessRunner.swift Sources/AppleNotestoX/Services/AppleNotesService.swift Tests/AppleNotestoXTests/ProcessRunnerTests.swift
git commit -m "refactor(process): extract shared ProcessRunner from AppleNotesService"
```

---

### Task 2: `RepoPaths` — resolve `review/` + `node`

**Files:**
- Create: `Sources/AppleNotestoX/Services/RepoPaths.swift`
- Test: `Tests/AppleNotestoXTests/RepoPathsTests.swift`

**Interfaces:**
- Produces:
  - `enum RepoPaths`
  - `static var reviewFolderOverrideKey: String` (`"review_folder_override"`)
  - `static func firstExisting(_ paths: [String], fileManager: FileManager = .default) -> URL?`
  - `static func reviewDir() -> URL` / `generateScript() -> URL` / `indexHTML() -> URL` / `studyDataJS() -> URL`
  - `static func nodeInvocation() -> (executable: URL, argPrefix: [String])`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AppleNotestoX

final class RepoPathsTests: XCTestCase {
    func testFirstExistingPicksFirstPresentPath() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let real = tmp.appendingPathComponent("node")
        FileManager.default.createFile(atPath: real.path, contents: Data("x".utf8))
        let got = RepoPaths.firstExisting(["/no/such/node", real.path, "/also/missing"])
        XCTAssertEqual(got?.path, real.path)
    }

    func testFirstExistingReturnsNilWhenNoneExist() {
        XCTAssertNil(RepoPaths.firstExisting(["/no/such/a", "/no/such/b"]))
    }

    func testReviewPathsShareReviewDir() {
        XCTAssertEqual(RepoPaths.generateScript().deletingLastPathComponent(), RepoPaths.reviewDir())
        XCTAssertEqual(RepoPaths.indexHTML().lastPathComponent, "index.html")
        XCTAssertEqual(RepoPaths.studyDataJS().lastPathComponent, "study-data.js")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift build --build-tests`
Expected: FAIL — `cannot find 'RepoPaths' in scope`.

- [ ] **Step 3: Implement `RepoPaths.swift`**

```swift
import Foundation

/// Resolves paths to the bundled-alongside `review/` tooling and the `node` binary.
/// The repo root is derived from this source file's compile-time path (`#filePath`);
/// a UserDefaults override (`review_folder_override`) wins when set — useful if the
/// app is ever run from outside the checkout.
enum RepoPaths {
    static let reviewFolderOverrideKey = "review_folder_override"

    /// First path in `paths` that exists on disk, as a file URL.
    static func firstExisting(_ paths: [String], fileManager: FileManager = .default) -> URL? {
        for p in paths where fileManager.fileExists(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        return nil
    }

    /// repo root = <root>/Sources/AppleNotestoX/Services/RepoPaths.swift → up 4.
    private static func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Services
            .deletingLastPathComponent()   // AppleNotestoX
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // repo root
    }

    static func reviewDir() -> URL {
        if let override = UserDefaults.standard.string(forKey: reviewFolderOverrideKey), !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return repoRoot().appendingPathComponent("review", isDirectory: true)
    }

    static func generateScript() -> URL { reviewDir().appendingPathComponent("generate.mjs") }
    static func indexHTML() -> URL { reviewDir().appendingPathComponent("index.html") }
    static func studyDataJS() -> URL { reviewDir().appendingPathComponent("study-data.js") }

    /// Prefer an absolute `node`; fall back to `/usr/bin/env node` (uses PATH).
    static func nodeInvocation() -> (executable: URL, argPrefix: [String]) {
        if let node = firstExisting(["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]) {
            return (node, [])
        }
        return (URL(fileURLWithPath: "/usr/bin/env"), ["node"])
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run (Xcode/CI): `swift test --filter RepoPathsTests` → Expected: PASS (3 tests).
Run: `swift build` → exit 0.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppleNotestoX/Services/RepoPaths.swift Tests/AppleNotestoXTests/RepoPathsTests.swift
git commit -m "feat(studio): RepoPaths — resolve review/ dir + node binary"
```

---

### Task 3: `StudyData` model + parser (pure)

**Files:**
- Create: `Sources/AppleNotestoX/Models/StudyData.swift`
- Test: `Tests/AppleNotestoXTests/StudyDataParseTests.swift`

**Interfaces:**
- Produces:
  - `struct StudyData: Sendable, Equatable { let conceptCount: Int; let cardCount: Int; let edgeCount: Int; let generatedAt: String?; let topConcepts: [String] }`
  - `static func StudyData.parse(_ js: String, topN: Int = 6) -> StudyData?`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AppleNotestoX

final class StudyDataParseTests: XCTestCase {
    private let sample = """
    // GENERATED by review/generate.mjs from Personal_LLM_Wiki — do not edit by hand.
    window.STUDY_DATA = {
      "generatedAt": "2026-06-30T08:58:40.332Z",
      "vault": "Personal_LLM_Wiki",
      "concepts": [
        {"id":"a","title":"Alpha","type":"concept","summary":"","tags":[],"links":["b","c"]},
        {"id":"b","title":"Beta","type":"concept","summary":"","tags":[],"links":["a"]},
        {"id":"c","title":"Gamma","type":"concept","summary":"","tags":[],"links":["a"]}
      ],
      "cards": [ {"id":"a::def","deck":"concept","front":"?","back":".","source":"a"} ],
      "edges": [ {"source":"a","target":"b"}, {"source":"a","target":"c"} ]
    };
    """

    func testParsesCountsAndGeneratedAt() {
        let d = StudyData.parse(sample)
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.conceptCount, 3)
        XCTAssertEqual(d?.cardCount, 1)
        XCTAssertEqual(d?.edgeCount, 2)
        XCTAssertEqual(d?.generatedAt, "2026-06-30T08:58:40.332Z")
    }

    func testTopConceptsRankedByEdgeDegree() {
        // "a" touches both edges (degree 2); b and c degree 1 → Alpha first.
        XCTAssertEqual(StudyData.parse(sample, topN: 1)?.topConcepts, ["Alpha"])
    }

    func testMalformedReturnsNil() {
        XCTAssertNil(StudyData.parse("not javascript"))
        XCTAssertNil(StudyData.parse(""))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift build --build-tests` → FAIL: `cannot find 'StudyData' in scope`.

- [ ] **Step 3: Implement `StudyData.swift`**

```swift
import Foundation

/// A parsed snapshot of `review/study-data.js` (`window.STUDY_DATA = {…};`).
struct StudyData: Sendable, Equatable {
    let conceptCount: Int
    let cardCount: Int
    let edgeCount: Int
    let generatedAt: String?
    let topConcepts: [String]   // titles, ranked by edge degree (desc)

    private struct Raw: Decodable {
        struct Concept: Decodable { let id: String; let title: String }
        struct Edge: Decodable { let source: String; let target: String }
        let generatedAt: String?
        let concepts: [Concept]
        let cards: [AnyCard]
        let edges: [Edge]
        struct AnyCard: Decodable {}   // count only
    }

    /// Strips the `window.STUDY_DATA = ` wrapper and decodes the JSON object.
    static func parse(_ js: String, topN: Int = 6) -> StudyData? {
        guard let start = js.firstIndex(of: "{"), let end = js.lastIndex(of: "}"), start < end else { return nil }
        let json = String(js[start...end])
        guard let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode(Raw.self, from: data) else { return nil }

        var degree: [String: Int] = [:]
        for e in raw.edges { degree[e.source, default: 0] += 1; degree[e.target, default: 0] += 1 }
        let top = raw.concepts
            .sorted { (degree[$0.id] ?? 0, $1.title) > (degree[$1.id] ?? 0, $0.title) }
            .prefix(topN)
            .map(\.title)

        return StudyData(
            conceptCount: raw.concepts.count,
            cardCount: raw.cards.count,
            edgeCount: raw.edges.count,
            generatedAt: raw.generatedAt,
            topConcepts: Array(top)
        )
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run (Xcode/CI): `swift test --filter StudyDataParseTests` → PASS (3 tests).
Run: `swift build` → exit 0.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppleNotestoX/Models/StudyData.swift Tests/AppleNotestoXTests/StudyDataParseTests.swift
git commit -m "feat(studio): StudyData model + study-data.js parser"
```

---

### Task 4: `StudyDataService` — run generator, read snapshot

**Files:**
- Create: `Sources/AppleNotestoX/Services/StudyDataService.swift`
- Test: `Tests/AppleNotestoXTests/StudyDataServiceTests.swift`

**Interfaces:**
- Consumes: `ProcessRunner.run`, `RepoPaths.*`, `StudyData.parse`
- Produces:
  - `enum StudyError: Error, LocalizedError { case scriptMissing(String); case generatorFailed(String); case studyDataUnreadable }`
  - `enum StudyDataService`
  - `static func loadExisting() -> StudyData?`
  - `static func refresh(vaultURL: URL) async throws -> StudyData`

- [ ] **Step 1: Write the failing test** (covers `loadExisting` parsing path via a temp file it can read directly through `StudyData.parse`; the generator run is integration-only)

```swift
import XCTest
@testable import AppleNotestoX

final class StudyDataServiceTests: XCTestCase {
    func testStudyErrorHasMessages() {
        XCTAssertNotNil(StudyError.scriptMissing("/x/generate.mjs").errorDescription)
        XCTAssertTrue(StudyError.generatorFailed("no wiki/ folder").errorDescription!.contains("no wiki/"))
        XCTAssertNotNil(StudyError.studyDataUnreadable.errorDescription)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift build --build-tests` → FAIL: `cannot find 'StudyError' in scope`.

- [ ] **Step 3: Implement `StudyDataService.swift`**

```swift
import Foundation

enum StudyError: Error, LocalizedError {
    case scriptMissing(String)
    case generatorFailed(String)
    case studyDataUnreadable

    var errorDescription: String? {
        switch self {
        case .scriptMissing(let p): return "Can't find the study generator at \(p). Set the Review folder in Settings."
        case .generatorFailed(let m): return "Study generator failed: \(m)"
        case .studyDataUnreadable: return "Couldn't read study-data.js after generating."
        }
    }
}

/// Runs `review/generate.mjs` against a vault, then reads the produced `study-data.js`.
enum StudyDataService {
    /// Read the current snapshot without regenerating (nil if never generated).
    static func loadExisting() -> StudyData? {
        guard let js = try? String(contentsOf: RepoPaths.studyDataJS(), encoding: .utf8) else { return nil }
        return StudyData.parse(js)
    }

    /// Regenerate from the vault, then parse the result.
    static func refresh(vaultURL: URL) async throws -> StudyData {
        let script = RepoPaths.generateScript()
        guard FileManager.default.fileExists(atPath: script.path) else {
            throw StudyError.scriptMissing(script.path)
        }
        let out = RepoPaths.studyDataJS()
        let node = RepoPaths.nodeInvocation()
        let args = node.argPrefix + [script.path, "--vault", vaultURL.path, "--out", out.path]

        let result = try await ProcessRunner.run(executableURL: node.executable, arguments: args)
        guard result.status == 0 else {
            let msg = result.stderr.isEmpty ? result.stdout : result.stderr
            throw StudyError.generatorFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let data = loadExisting() else { throw StudyError.studyDataUnreadable }
        return data
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run (Xcode/CI): `swift test --filter StudyDataServiceTests` → PASS.
Run: `swift build` → exit 0.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppleNotestoX/Services/StudyDataService.swift Tests/AppleNotestoXTests/StudyDataServiceTests.swift
git commit -m "feat(studio): StudyDataService — regenerate + read study snapshot"
```

---

### Task 5: `SynthesisBacklog` — pure scan + prompt

**Files:**
- Create: `Sources/AppleNotestoX/Services/SynthesisBacklog.swift`
- Test: `Tests/AppleNotestoXTests/SynthesisBacklogTests.swift`

**Interfaces:**
- Produces:
  - `struct BacklogItem: Sendable, Equatable, Identifiable { let id: String; let date: String; let slug: String; let url: URL }`
  - `enum SynthesisBacklog`
  - `static func pending(rawJournal: [String], wikiSources: Set<String>) -> [String]`  (filenames in → pending filenames out, sorted desc)
  - `static func scan(vaultURL: URL, fileManager: FileManager = .default) -> [BacklogItem]`
  - `static func opencodePrompt(_ items: [BacklogItem]) -> String`

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift build --build-tests` → FAIL: `cannot find 'SynthesisBacklog' in scope`.

- [ ] **Step 3: Implement `SynthesisBacklog.swift`**

```swift
import Foundation

/// A `raw/journal` note not yet mirrored by a `wiki/sources/<same-name>.md` page.
struct BacklogItem: Sendable, Equatable, Identifiable {
    let id: String      // filename, e.g. "2026-06-30-mindset.md"
    let date: String    // "YYYY-MM-DD" prefix, or "" if none
    let slug: String    // remainder without date + ".md"
    let url: URL
}

/// Surfaces what's captured in `raw/` but not yet synthesized into `wiki/`.
/// Heuristic v1: filename match between `raw/journal/*.md` and `wiki/sources/*.md`.
enum SynthesisBacklog {
    static func pending(rawJournal: [String], wikiSources: Set<String>) -> [String] {
        rawJournal.filter { !wikiSources.contains($0) }.sorted(by: >)
    }

    static func scan(vaultURL: URL, fileManager: FileManager = .default) -> [BacklogItem] {
        let journal = vaultURL.appendingPathComponent("raw/journal", isDirectory: true)
        let sources = vaultURL.appendingPathComponent("wiki/sources", isDirectory: true)
        let raw = mdFilenames(in: journal, fileManager: fileManager)
        let src = Set(mdFilenames(in: sources, fileManager: fileManager))
        return pending(rawJournal: raw, wikiSources: src).map { name in
            let (date, slug) = split(name)
            return BacklogItem(id: name, date: date, slug: slug,
                               url: journal.appendingPathComponent(name))
        }
    }

    static func opencodePrompt(_ items: [BacklogItem]) -> String {
        let list = items.map { "- raw/journal/\($0.id)" }.joined(separator: "\n")
        return """
        Synthesize these raw/ notes into the wiki per AGENTS.md — provenance-stamped, \
        with [[wikilinks]] and one wiki/sources/ page each:
        \(list)
        """
    }

    // MARK: helpers
    private static func mdFilenames(in dir: URL, fileManager: FileManager) -> [String] {
        (try? fileManager.contentsOfDirectory(atPath: dir.path))?.filter { $0.hasSuffix(".md") } ?? []
    }

    private static func split(_ name: String) -> (date: String, slug: String) {
        let base = name.hasSuffix(".md") ? String(name.dropLast(3)) : name
        if base.count >= 10, base.prefix(10).allSatisfy({ $0.isNumber || $0 == "-" }),
           base.dropFirst(10).first == "-" {
            return (String(base.prefix(10)), String(base.dropFirst(11)))
        }
        return ("", base)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run (Xcode/CI): `swift test --filter SynthesisBacklogTests` → PASS (4 tests).
Run: `swift build` → exit 0.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppleNotestoX/Services/SynthesisBacklog.swift Tests/AppleNotestoXTests/SynthesisBacklogTests.swift
git commit -m "feat(studio): SynthesisBacklog — raw/ not-yet-in-wiki scanner + opencode prompt"
```

---

### Task 6: `AppState` — mode + study/backlog state & actions

**Files:**
- Modify: `Sources/AppleNotestoX/App/AppState.swift`

**Interfaces:**
- Consumes: `StudyDataService`, `SynthesisBacklog`, `RepoPaths`
- Produces (new members on `AppState`):
  - `enum AppMode: String, Sendable { case study, capture }`
  - `var appMode: AppMode`, `var studyData: StudyData?`, `var isRefreshingStudy: Bool`, `var studyError: String?`, `var backlogItems: [BacklogItem]`
  - `func loadStudyOnAppear()`, `func refreshStudyData() async`, `func launchWikiReview()`, `func loadBacklog()`, `func copyBacklogPrompt()`

- [ ] **Step 1: Add imports + state**

At top of `AppState.swift` add `import AppKit` (for `NSWorkspace`/`NSPasteboard`) after `import Foundation`. Inside the class, after the `// Wiki export` block add:

```swift
    // Study + synthesis (Wiki Studio pass 1)
    enum AppMode: String, Sendable { case study, capture }
    var appMode: AppMode = .study
    var studyData: StudyData? = nil
    var isRefreshingStudy = false
    var studyError: String? = nil
    var backlogItems: [BacklogItem] = []
```

- [ ] **Step 2: Add actions** (append inside the class, before the closing brace)

```swift
    // MARK: - Study + backlog

    /// Cheap load on first show: read any existing snapshot + scan the backlog.
    func loadStudyOnAppear() {
        if studyData == nil { studyData = StudyDataService.loadExisting() }
        loadBacklog()
    }

    func refreshStudyData() async {
        guard let vault = vaultURL else { studyError = "Choose your vault first."; return }
        isRefreshingStudy = true
        studyError = nil
        defer { isRefreshingStudy = false }
        let didAccess = vault.startAccessingSecurityScopedResource()
        defer { if didAccess { vault.stopAccessingSecurityScopedResource() } }
        do {
            studyData = try await StudyDataService.refresh(vaultURL: vault)
            loadBacklog()
        } catch {
            studyError = error.localizedDescription
        }
    }

    func launchWikiReview() {
        NSWorkspace.shared.open(RepoPaths.indexHTML())
    }

    func loadBacklog() {
        guard let vault = vaultURL else { backlogItems = []; return }
        let didAccess = vault.startAccessingSecurityScopedResource()
        defer { if didAccess { vault.stopAccessingSecurityScopedResource() } }
        backlogItems = SynthesisBacklog.scan(vaultURL: vault)
    }

    func copyBacklogPrompt() {
        let prompt = SynthesisBacklog.opencodePrompt(backlogItems)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
    }
```

- [ ] **Step 3: Verify build**

Run: `swift build` → Expected: exit 0 (no test for `@MainActor` state here; verified by build + Task 7/8 wiring + manual).

- [ ] **Step 4: Commit**

```bash
git add Sources/AppleNotestoX/App/AppState.swift
git commit -m "feat(studio): AppState — study/backlog state + refresh/launch/copy actions"
```

---

### Task 7: `StudyView` — the wiki-hero surface

**Files:**
- Create: `Sources/AppleNotestoX/UI/StudyView.swift`

**Interfaces:**
- Consumes: `AppState` (`studyData`, `isRefreshingStudy`, `studyError`, `backlogItems`, `vaultURL`, actions)

- [ ] **Step 1: Implement `StudyView.swift`**

```swift
import SwiftUI
import AppKit

/// Study-first hero: big counts + Launch/Refresh + "jump back in", with a quieter
/// synthesis-backlog panel. The wiki is the focal point.
struct StudyView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            hero
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(24)
            Divider()
            backlog
                .frame(width: 300)
                .padding(20)
        }
        .task { state.loadStudyOnAppear() }
    }

    // MARK: hero (the wiki)
    @ViewBuilder private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("STUDY YOUR WIKI").font(.caption).fontWeight(.bold)
                .foregroundStyle(.tertiary).kerning(1)

            if state.vaultURL == nil {
                emptyVault
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(state.studyData?.conceptCount ?? 0)")
                        .font(.system(size: 52, weight: .bold)).monospacedDigit()
                    Text("concepts · \(state.studyData?.cardCount ?? 0) cards")
                        .foregroundStyle(.secondary)
                }
                if let gen = state.studyData?.generatedAt {
                    Text("last refreshed \(relative(gen)) · \(state.studyData?.edgeCount ?? 0) links")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("No study data yet — hit Refresh to build it.")
                        .font(.callout).foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await state.refreshStudyData() }
                    } label: {
                        if state.isRefreshingStudy { ProgressView().controlSize(.small) }
                        else { Label("Refresh", systemImage: "arrow.clockwise") }
                    }
                    .disabled(state.isRefreshingStudy)

                    Button {
                        state.launchWikiReview()
                    } label: { Label("Launch Wiki Review", systemImage: "sparkles") }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.studyData == nil)
                }

                if let err = state.studyError {
                    Text(err).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }

                if let top = state.studyData?.topConcepts, !top.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("JUMP BACK IN").font(.caption2).fontWeight(.bold)
                            .foregroundStyle(.tertiary).kerning(1).padding(.top, 6)
                        FlowChips(items: top)
                    }
                }
            }
            Spacer()
        }
    }

    @ViewBuilder private var emptyVault: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose your vault to begin").font(.title3).bold()
            Text("Wiki Studio studies your Personal_LLM_Wiki. Pick the vault folder in the Wiki (Capture) tab.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Go to Capture") { state.appMode = .capture }
        }
    }

    // MARK: backlog (supporting)
    @ViewBuilder private var backlog: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Awaiting synthesis").font(.headline)
                if !state.backlogItems.isEmpty {
                    Text("\(state.backlogItems.count)").font(.caption).fontWeight(.bold)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.18), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
            if state.backlogItems.isEmpty {
                Text("All caught up — nothing waiting in raw/.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(state.backlogItems.prefix(8)) { item in
                    HStack(spacing: 8) {
                        Text(item.date).font(.caption).monospacedDigit().foregroundStyle(.tertiary)
                        Text(item.slug).font(.callout).lineLimit(1)
                    }
                }
                if state.backlogItems.count > 8 {
                    Text("+ \(state.backlogItems.count - 8) more").font(.caption).foregroundStyle(.tertiary)
                }
                HStack {
                    Button("Copy opencode prompt") { state.copyBacklogPrompt() }
                    Button {
                        if let v = state.vaultURL {
                            NSWorkspace.shared.open(v.appendingPathComponent("raw/journal"))
                        }
                    } label: { Image(systemName: "folder") }
                    .help("Reveal raw/journal in Finder")
                }
                .controlSize(.small)
                .padding(.top, 4)
            }
            Spacer()
            Text("Synthesis stays LLM-owned — the app surfaces what's in raw/ but not yet in wiki/sources/.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func relative(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return "recently" }
        let rel = RelativeDateTimeFormatter(); rel.unitsStyle = .full
        return rel.localizedString(for: date, relativeTo: Date())
    }
}

/// Simple wrapping chip row for the "jump back in" concept titles.
private struct FlowChips: View {
    let items: [String]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)],
                  alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { t in
                Text(t).font(.callout).lineLimit(1)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build` → exit 0. (SwiftUI views are verified by build + manual; no XCTest.)

- [ ] **Step 3: Commit**

```bash
git add Sources/AppleNotestoX/UI/StudyView.swift
git commit -m "feat(studio): StudyView — wiki-hero counts + launch/refresh + backlog panel"
```

---

### Task 8: Wire the mode switch + Settings override

**Files:**
- Modify: `Sources/AppleNotestoX/UI/ContentView.swift`
- Modify: `Sources/AppleNotestoX/UI/SettingsView.swift`

**Interfaces:**
- Consumes: `AppState.appMode`, `StudyView`, `RepoPaths.reviewFolderOverrideKey`

- [ ] **Step 1: ContentView — switch body on mode + add the picker**

Replace the `NavigationSplitView { … } detail: { … }` with a mode switch and move the split into a computed property. Change the `body` to:

```swift
    var body: some View {
        @Bindable var state = state

        Group {
            switch state.appMode {
            case .study: StudyView()
            case .capture: captureSplit
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Mode", selection: $state.appMode) {
                    Text("Study").tag(AppState.AppMode.study)
                    Text("Capture").tag(AppState.AppMode.capture)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            ToolbarItem(placement: .principal) {
                if state.isArchiving {
                    HStack { ProgressView().controlSize(.small); Text(progressLabel) }
                } else if hasProgress {
                    Text(summaryLabel).foregroundStyle(.secondary)
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await state.loadAppleHierarchy(); await state.verifyAndLoadNotion() }
                } label: { Image(systemName: "arrow.clockwise") }
                .help("Reload both panes")

                Button { showSettings = true } label: { Image(systemName: "gear") }

                if state.appMode == .capture {
                    if isWiki {
                        Button("Export to wiki") { Task { await state.runWikiExport() } }
                            .keyboardShortcut(.return, modifiers: [.command])
                            .disabled(state.selectedNoteIDs.isEmpty || state.vaultURL == nil || state.isArchiving)
                    } else {
                        Button("Archive…") { showPreview = true }
                            .keyboardShortcut(.return, modifiers: [.command])
                            .disabled(state.selectedNoteIDs.isEmpty || state.selectedNotionPageID == nil || state.isArchiving)
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showPreview) { PreviewSheet() }
        .sheet(isPresented: $state.permissionDeniedSheet) { PermissionDeniedSheet() }
        .alert("Error", isPresented: .constant(state.errorMessage != nil)) {
            Button("OK") { state.errorMessage = nil }
        } message: { Text(state.errorMessage ?? "") }
    }

    private var captureSplit: some View {
        NavigationSplitView {
            SourcePane().navigationSplitViewColumnWidth(min: 280, ideal: 360)
        } detail: {
            DestinationPane().navigationSplitViewColumnWidth(min: 320, ideal: 420)
        }
    }
```

- [ ] **Step 2: SettingsView — add the Review-folder override**

In `SettingsView.body`, after the "Apple Notes permission" `VStack` and before `Spacer()`, insert:

```swift
            Divider().padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("Review folder (advanced)").font(.subheadline).bold()
                Text("Where review/generate.mjs and index.html live. Leave blank to use the app's bundled copy.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("~/Projects/AppleNotestoX/review", text: $reviewDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true; panel.canChooseFiles = false
                        if panel.runModal() == .OK, let u = panel.url { reviewDraft = u.path }
                    }
                }
            }
```

Add the state property near `@State private var draft` :

```swift
    @State private var reviewDraft: String = UserDefaults.standard.string(forKey: RepoPaths.reviewFolderOverrideKey) ?? ""
```

And persist it in the **Save** button action (before `dismiss()` in the existing Save closure add):

```swift
                        let trimmed = reviewDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        UserDefaults.standard.set(trimmed, forKey: RepoPaths.reviewFolderOverrideKey)
```

Also import AppKit at top if not present (SettingsView already uses `NSWorkspace`, so `import SwiftUI` implicitly brings AppKit on macOS; add `import AppKit` to be safe).

- [ ] **Step 3: Verify build**

Run: `swift build` → exit 0.

- [ ] **Step 4: Manual acceptance (under Xcode / `swift run`)**

- Launch → defaults to **Study**; big counts show (or "No study data yet").
- Click **Refresh** → regenerates; counts update; "last refreshed just now".
- Click **Launch Wiki Review** → browser opens `review/index.html`.
- Backlog panel lists pending `raw/journal` notes; **Copy opencode prompt** puts text on clipboard; folder button reveals `raw/journal`.
- Switch to **Capture** → the original Apple Notes → Notion/Wiki flow is intact; export button reappears.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppleNotestoX/UI/ContentView.swift Sources/AppleNotestoX/UI/SettingsView.swift
git commit -m "feat(studio): Study|Capture mode switch + Review-folder setting"
```

---

## Self-review

- **Spec coverage:** Refresh (T4/T6/T7) ✓; Launch (T6/T7) ✓; live counts + jump-back-in (T3/T7) ✓; backlog scan + count + copy prompt + reveal (T5/T6/T7) ✓; no in-app "due" (T7 shows concepts+cards only) ✓; filename-match heuristic (T5) ✓; `#filePath` + Settings override (T2/T8) ✓; node discovery (T2) ✓; ProcessRunner reuse (T1) ✓; Study|Capture mode, Capture unchanged (T8) ✓; states/errors (T4 `StudyError`, T7 empty/error/refreshing) ✓.
- **Placeholder scan:** none — every code step is complete.
- **Type consistency:** `ProcessRunner.Result{stdout,stderr,status}` used identically in T1/T4; `StudyData{conceptCount,cardCount,edgeCount,generatedAt,topConcepts}` produced T3, consumed T6/T7; `BacklogItem{id,date,slug,url}` produced T5, consumed T6/T7; `AppMode` produced T6, consumed T8; action names (`refreshStudyData/launchWikiReview/loadBacklog/copyBacklogPrompt/loadStudyOnAppear`) consistent T6↔T7↔T8.

## Out of scope (later passes)
Pass 2 hub shell + in-app Browse (rendered wiki pages); Pass 3 unified Capture menu; Pass 4 X bookmarks (paste-URL MVP first, OAuth sync if paid tier).
