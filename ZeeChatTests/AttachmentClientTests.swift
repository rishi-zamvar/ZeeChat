import XCTest
import UIKit
@testable import ZeeChat

/// TDD for AttachmentClient. Per RESEARCH.md ranked #4 risk: HEIC ->
/// JPEG round-trip + thumbnail integrity. Iso-runnable; no network.
final class AttachmentClientTests: XCTestCase {

    private func makeImage(width: Int = 800, height: Int = 600,
                           color: UIColor = .systemBlue) -> UIImage {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    // MARK: -

    func test_encode_returnsJpegBytes_andSha256() throws {
        let client = AttachmentClient()
        let image = makeImage()
        let result = try client.encode(image, suggestedFilename: "screenshot.jpg")
        XCTAssertEqual(result.mimeType, "image/jpeg")
        XCTAssertEqual(result.filename, "screenshot.jpg")
        XCTAssertGreaterThan(result.bytes.count, 100, "JPEG should be at least a kilobyte for a solid-color 800x600")
        XCTAssertEqual(result.sha256Hex.count, 64, "SHA256 hex must be 64 chars")
        XCTAssertFalse(result.thumbnailBase64.isEmpty, "Thumbnail must be present")
        // First two JPEG magic bytes: 0xFF 0xD8
        XCTAssertEqual(result.bytes.prefix(2), Data([0xFF, 0xD8]),
                       "Encoded bytes must start with JPEG SOI marker")
    }

    func test_thumbnail_isWithinMaxEdge() throws {
        let client = AttachmentClient()
        let big = makeImage(width: 2400, height: 1200)
        let thumbData = try client.thumbnail(from: big)
        // Decode thumbnail back to check dimensions.
        let thumb = UIImage(data: thumbData)!
        XCTAssertLessThanOrEqual(max(thumb.size.width, thumb.size.height),
                                 AttachmentClient.thumbnailMaxEdge,
                                 "Thumbnail longer edge must be <= 300px")
        // Aspect ratio preserved (within rounding).
        let originalRatio = 2400.0 / 1200.0
        let thumbRatio = thumb.size.width / thumb.size.height
        XCTAssertEqual(originalRatio, thumbRatio, accuracy: 0.05)
    }

    func test_thumbnail_doesNotUpscaleSmallImages() throws {
        let client = AttachmentClient()
        let small = makeImage(width: 100, height: 80)
        let thumbData = try client.thumbnail(from: small)
        let thumb = UIImage(data: thumbData)!
        XCTAssertEqual(thumb.size.width, 100)
        XCTAssertEqual(thumb.size.height, 80)
    }

    /// SHA256 of the same image bytes is deterministic across encodes.
    /// Used for upload dedup later — same screenshot attached twice
    /// should reuse the existing upload.
    func test_encode_sha256IsDeterministicForSameImage() throws {
        let client = AttachmentClient()
        let image = makeImage()
        let a = try client.encode(image)
        let b = try client.encode(image)
        XCTAssertEqual(a.sha256Hex, b.sha256Hex,
                       "Identical image must produce identical sha256")
        XCTAssertEqual(a.bytes, b.bytes,
                       "Identical image must produce byte-identical JPEG")
    }

    /// Encoded thumbnail must itself be valid JPEG (not just any data).
    /// Catches a bug where the renderer hands back something that
    /// imageData() can't roundtrip.
    func test_thumbnail_isValidJpeg() throws {
        let client = AttachmentClient()
        let image = makeImage()
        let result = try client.encode(image)
        let thumbBytes = Data(base64Encoded: result.thumbnailBase64)!
        XCTAssertEqual(thumbBytes.prefix(2), Data([0xFF, 0xD8]),
                       "Thumbnail must start with JPEG SOI marker")
        let decoded = UIImage(data: thumbBytes)
        XCTAssertNotNil(decoded, "Thumbnail must round-trip through UIImage(data:)")
    }
}
