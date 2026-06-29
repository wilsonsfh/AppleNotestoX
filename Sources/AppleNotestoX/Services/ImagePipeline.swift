import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

actor ImagePipeline {
    enum ImagePipelineError: Error, LocalizedError {
        case sourceUnreadable
        case encodeFailed
        case stillTooLargeAfterAllSteps(Int)

        var errorDescription: String? {
            switch self {
            case .sourceUnreadable: return "Image source is not readable (corrupt or non-image file)."
            case .encodeFailed: return "Could not encode image to JPEG."
            case .stillTooLargeAfterAllSteps(let n): return "Image still \(n) bytes after maximum compression."
            }
        }
    }

    private let notion: NotionService
    private let maxBytes: Int
    private let ladder: [Int]
    private let quality: CGFloat

    init(
        notion: NotionService,
        maxBytes: Int = 4_900_000,
        ladder: [Int] = [2048, 1600, 1200, 1024],
        quality: CGFloat = 0.85
    ) {
        self.notion = notion
        self.maxBytes = maxBytes
        self.ladder = ladder
        self.quality = quality
    }

    /// Resize+compress to fit under cap, then upload via Notion. Returns `file_upload_id`.
    func uploadResized(localURL: URL) async throws -> String {
        let jpeg = try resizeToFit(localURL: localURL)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".jpg")
        try jpeg.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        return try await notion.uploadFile(localURL: tmp, mimeType: "image/jpeg")
    }

    /// Re-encodes the source as JPEG at decreasing max-edge sizes until it fits under `maxBytes`.
    func resizeToFit(localURL: URL) throws -> Data {
        guard let src = CGImageSourceCreateWithURL(localURL as CFURL, nil) else {
            throw ImagePipelineError.sourceUnreadable
        }
        var lastSize = 0
        for maxEdge in ladder {
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxEdge,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { continue }
            let data = try encodeJPEG(thumb)
            lastSize = data.count
            if data.count <= maxBytes {
                return data
            }
        }
        throw ImagePipelineError.stillTooLargeAfterAllSteps(lastSize)
    }

    private func encodeJPEG(_ image: CGImage) throws -> Data {
        let buffer = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            buffer as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1, nil
        ) else { throw ImagePipelineError.encodeFailed }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ImagePipelineError.encodeFailed }
        return Data(referencing: buffer)
    }
}
