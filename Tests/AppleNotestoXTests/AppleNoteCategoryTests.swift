import XCTest
@testable import AppleNotestoX

final class AppleNoteCategoryTests: XCTestCase {
    func test_classify_matchesWholeWordsNotSubstrings() {
        // "said", "email", "again" and "main" contain "ai"; "network" contains "work".
        let category = AppleNoteCategory.classify(
            title: "Weekend trip",
            markdown: "She said she would email the main hotel again about the network."
        )

        XCTAssertEqual(category, .travelAndFinance)
    }

    func test_classify_stillMatchesShortKeywordsAsWholeWords() {
        let category = AppleNoteCategory.classify(title: "AI notes", markdown: "Trying an LLM for coding.")

        XCTAssertEqual(category, .technologyAndLearning)
    }

    func test_classify_matchesMultiWordKeywords() {
        let category = AppleNoteCategory.classify(title: "Prep", markdown: "Got a job offer after the interview.")

        XCTAssertEqual(category, .careerAndWork)
    }

    func test_classify_noKeywords_fallsBackToReference() {
        XCTAssertEqual(AppleNoteCategory.classify(title: "Untitled", markdown: "xyz"), .referenceAndLists)
    }
}
