import XCTest
@testable import AppleNotestoX

final class WikiContentSimilarityTests: XCTestCase {
    func test_jaccardSimilarity_identicalText_isOne() {
        let text = "The quick brown fox jumps over the lazy dog near the river bank today"

        XCTAssertEqual(WikiContentSimilarity.jaccardSimilarity(text, text), 1.0)
    }

    func test_jaccardSimilarity_completelyDifferentText_isLow() {
        let a = "The quick brown fox jumps over the lazy dog near the river bank today"
        let b = "Quarterly tax filing deadlines require careful bookkeeping and receipts collection"

        XCTAssertLessThan(WikiContentSimilarity.jaccardSimilarity(a, b), 0.2)
    }

    func test_jaccardSimilarity_oneWordEditedInLongText_staysAboveDefaultThreshold() {
        let a = "The quick brown fox jumps over the lazy dog near the river bank today"
        let b = "The quick brown fox jumps over the lazy dog near the river bank yesterday"

        XCTAssertGreaterThanOrEqual(
            WikiContentSimilarity.jaccardSimilarity(a, b), WikiContentSimilarity.defaultThreshold
        )
    }

    func test_jaccardSimilarity_isCaseInsensitive() {
        let a = "Hello World this is a Test Note about Cafes"
        let b = "hello world this is a test note about cafes"

        XCTAssertEqual(WikiContentSimilarity.jaccardSimilarity(a, b), 1.0)
    }

    func test_jaccardSimilarity_bothEmpty_isZero() {
        XCTAssertEqual(WikiContentSimilarity.jaccardSimilarity("", ""), 0.0)
    }

    func test_jaccardSimilarity_oneEmpty_isZero() {
        XCTAssertEqual(WikiContentSimilarity.jaccardSimilarity("", "some content here"), 0.0)
    }

    func test_defaultThreshold_isEightyPercent() {
        XCTAssertEqual(WikiContentSimilarity.defaultThreshold, 0.8)
    }
}
