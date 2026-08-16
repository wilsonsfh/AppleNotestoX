import XCTest
@testable import AppleNotestoX

final class WikiDuplicateAssetsTests: XCTestCase {
    func test_referencedAssetFilenames_extractsObsidianImageEmbeds() {
        let markdown = "Some text\n\n![[cafe-plan-01.png]]\n\nMore text\n\n![[cafe-plan-02.jpg]]"

        let names = WikiDuplicateAssets.referencedAssetFilenames(in: markdown, assetsSubpath: "raw/assets")

        XCTAssertEqual(names, ["cafe-plan-01.png", "cafe-plan-02.jpg"])
    }

    func test_referencedAssetFilenames_extractsPlainAssetLinks() {
        let markdown = "See the [attachment](raw/assets/cafe-plan-01.pdf) for details."

        let names = WikiDuplicateAssets.referencedAssetFilenames(in: markdown, assetsSubpath: "raw/assets")

        XCTAssertEqual(names, ["cafe-plan-01.pdf"])
    }

    func test_referencedAssetFilenames_handlesBothShapesTogether() {
        let markdown = """
        ![[cafe-plan-01.png]]

        See the [attachment](raw/assets/cafe-plan-02.pdf) for details.
        """

        let names = WikiDuplicateAssets.referencedAssetFilenames(in: markdown, assetsSubpath: "raw/assets")

        XCTAssertEqual(names, ["cafe-plan-01.png", "cafe-plan-02.pdf"])
    }

    func test_referencedAssetFilenames_respectsCustomAssetsSubpath() {
        let markdown = "[attachment](custom/assets/file.pdf)"

        XCTAssertEqual(
            WikiDuplicateAssets.referencedAssetFilenames(in: markdown, assetsSubpath: "custom/assets"),
            ["file.pdf"]
        )
        XCTAssertEqual(
            WikiDuplicateAssets.referencedAssetFilenames(in: markdown, assetsSubpath: "raw/assets"),
            []
        )
    }

    func test_referencedAssetFilenames_noReferences_returnsEmpty() {
        XCTAssertEqual(
            WikiDuplicateAssets.referencedAssetFilenames(in: "Just plain text.", assetsSubpath: "raw/assets"),
            []
        )
    }
}
