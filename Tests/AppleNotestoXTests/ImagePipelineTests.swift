import XCTest
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import AppleNotestoX

final class ImagePipelineTests: XCTestCase {

    private func makePNG(width: Int, height: Int) throws -> URL {
        let cs = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        let totalBytes = bytesPerRow * height
        var pixels = [UInt8](repeating: 0, count: totalBytes)
        // Fill with random noise so it doesn't compress to nothing.
        for i in 0..<totalBytes { pixels[i] = UInt8.random(in: 0...255) }
        guard let ctx = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cg = ctx.makeImage() else {
            throw NSError(domain: "test", code: 1)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".png")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "test", code: 2)
        }
        CGImageDestinationAddImage(dest, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    func test_smallImage_roundtrip() async throws {
        let url = try makePNG(width: 200, height: 200)
        let pipeline = ImagePipeline(notion: NotionService())
        let data = try await pipeline.resizeToFit(localURL: url)
        XCTAssertLessThanOrEqual(data.count, 4_900_000)
        XCTAssertGreaterThan(data.count, 0)
    }

    func test_largeImage_compressesUnderCap() async throws {
        // 3000x3000 noise → PNG is large; pipeline must produce a JPEG ≤ 4.9MB.
        let url = try makePNG(width: 3000, height: 3000)
        let pipeline = ImagePipeline(notion: NotionService())
        let data = try await pipeline.resizeToFit(localURL: url)
        XCTAssertLessThanOrEqual(data.count, 4_900_000)
    }

    func test_corruptInput_throws() async {
        let bad = FileManager.default.temporaryDirectory.appendingPathComponent("bad-\(UUID()).bin")
        try? Data(repeating: 0, count: 16).write(to: bad)
        let pipeline = ImagePipeline(notion: NotionService())
        do {
            _ = try await pipeline.resizeToFit(localURL: bad)
            XCTFail("expected throw")
        } catch {
            // good
        }
    }

    func test_tightCap_exercisesLadder() async throws {
        let url = try makePNG(width: 3000, height: 3000)
        // Force the cap so low that the largest step won't fit, ensuring fallback steps run.
        let pipeline = ImagePipeline(
            notion: NotionService(),
            maxBytes: 200_000,
            ladder: [2048, 1024, 512],
            quality: 0.85
        )
        let data = try await pipeline.resizeToFit(localURL: url)
        XCTAssertLessThanOrEqual(data.count, 200_000)
    }
}
