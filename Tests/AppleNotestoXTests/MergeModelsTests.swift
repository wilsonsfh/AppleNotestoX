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
