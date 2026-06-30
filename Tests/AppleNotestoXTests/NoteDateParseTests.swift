import XCTest
@testable import AppleNotestoX

/// `listScript` emits local-time "yyyy-MM-dd'T'HH:mm:ss" timestamps. We parse them
/// with a fast hand-rolled parser instead of a per-note `DateFormatter` (ICU), which
/// dominated CPU while reading large Notes libraries.
final class NoteDateParseTests: XCTestCase {
    private var localGregorian: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    func testParsesLocalDateTime() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 3; comps.day = 24
        comps.hour = 17; comps.minute = 5; comps.second = 9
        let expected = localGregorian.date(from: comps)!
        XCTAssertEqual(AppleNotesService.parseNoteDate("2026-03-24T17:05:09"), expected)
    }

    func testMatchesDateFormatterForManyDates() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.timeZone = .current
        let samples = [
            "1970-01-01T00:00:00", "2001-02-03T04:05:06", "2024-02-29T23:59:59",
            "2026-06-30T12:34:56", "2019-12-31T18:00:00", "2008-07-04T09:09:09",
        ]
        for s in samples {
            XCTAssertEqual(AppleNotesService.parseNoteDate(s), f.date(from: s), "mismatch for \(s)")
        }
    }

    func testRejectsMalformed() {
        XCTAssertNil(AppleNotesService.parseNoteDate(""))
        XCTAssertNil(AppleNotesService.parseNoteDate("2026-03-24"))         // no time
        XCTAssertNil(AppleNotesService.parseNoteDate("2026-03-24T17:05"))   // missing seconds
        XCTAssertNil(AppleNotesService.parseNoteDate("nope"))
        XCTAssertNil(AppleNotesService.parseNoteDate("2026/03/24T17:05:09"))
    }
}
