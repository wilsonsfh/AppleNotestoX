import XCTest
@testable import AppleNotestoX

final class TextDiffTests: XCTestCase {
    func test_diff_identicalText_allLinesUnchanged() {
        let lines = TextDiff.diff(old: "one\ntwo", new: "one\ntwo")

        XCTAssertEqual(lines, [.unchanged("one"), .unchanged("two")])
    }

    func test_diff_appendedLine_marksOnlyNewLineAdded() {
        let lines = TextDiff.diff(old: "one\ntwo", new: "one\ntwo\nthree")

        XCTAssertEqual(lines, [.unchanged("one"), .unchanged("two"), .added("three")])
    }

    func test_diff_removedLine_marksOnlyMissingLineRemoved() {
        let lines = TextDiff.diff(old: "one\ntwo\nthree", new: "one\nthree")

        XCTAssertEqual(lines, [.unchanged("one"), .removed("two"), .unchanged("three")])
    }

    func test_diff_changedLine_marksOldRemovedAndNewAdded() {
        let lines = TextDiff.diff(old: "one\ntwo", new: "one\ntwo-edited")

        XCTAssertEqual(lines, [.unchanged("one"), .removed("two"), .added("two-edited")])
    }

    func test_diff_emptyOldText_allLinesAdded() {
        let lines = TextDiff.diff(old: "", new: "one\ntwo")

        XCTAssertEqual(lines, [.added("one"), .added("two")])
    }

    func test_diff_emptyNewText_allLinesRemoved() {
        let lines = TextDiff.diff(old: "one\ntwo", new: "")

        XCTAssertEqual(lines, [.removed("one"), .removed("two")])
    }
}
