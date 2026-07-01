import XCTest
@testable import AppleNotestoX

final class StudyDataServiceTests: XCTestCase {
    func testStudyErrorHasMessages() {
        XCTAssertNotNil(StudyError.scriptMissing("/x/generate.mjs").errorDescription)
        XCTAssertTrue(StudyError.generatorFailed("no wiki/ folder").errorDescription!.contains("no wiki/"))
        XCTAssertNotNil(StudyError.studyDataUnreadable.errorDescription)
    }
}
