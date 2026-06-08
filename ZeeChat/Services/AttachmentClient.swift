import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers

/// Image attach pipeline for the spec composer.
///
/// Local-only this commit:
///   - Encode any UIImage to JPEG (HEIC source supported transparently
///     since UIImage decodes it on iOS 17+)
///   - Generate a small thumbnail (base64 JPEG, max 300px on longer
///     edge) for the wire `attachment_preview` field
///   - Compute SHA256 of the full bytes for upload dedup later
///
/// Upload + URL serving (~/dispatch/attachments/...) is a separate
/// concern; lands once SWE's POST /api/attachments/upload endpoint
/// is live. This client returns the encoded bytes + thumbnail + sha so
/// the caller can pipe them at that point.
struct AttachmentClient {
    /// Output of a local encode pass — everything iOS needs to ship a
    /// kind="image" message once the upload endpoint is up.
    struct EncodedAttachment: Equatable {
        let filename: String
        let mimeType: String
        let bytes: Data
        let thumbnailBase64: String
        let sha256Hex: String
    }

    enum AttachmentError: Error, Equatable {
        case encodeFailed
        case thumbnailFailed
        case tooLarge(actualBytes: Int, capBytes: Int)
    }

    /// Upload cap matches backend (50 MB per RESEARCH.md spec).
    static let maxUploadBytes = 50 * 1024 * 1024
    /// Thumbnail max edge in pixels.
    static let thumbnailMaxEdge: CGFloat = 300
    /// JPEG quality for full image (0.85 = good quality / reasonable size).
    static let fullJpegQuality: CGFloat = 0.85
    /// JPEG quality for thumbnail (0.7 = small).
    static let thumbnailJpegQuality: CGFloat = 0.7

    /// Encode a UIImage for attach. Returns the wire bundle.
    func encode(_ image: UIImage, suggestedFilename: String = "attachment.jpg") throws -> EncodedAttachment {
        guard let fullData = image.jpegData(compressionQuality: Self.fullJpegQuality) else {
            throw AttachmentError.encodeFailed
        }
        guard fullData.count <= Self.maxUploadBytes else {
            throw AttachmentError.tooLarge(actualBytes: fullData.count, capBytes: Self.maxUploadBytes)
        }
        let thumb = try thumbnail(from: image)
        let thumbB64 = thumb.base64EncodedString()
        return EncodedAttachment(
            filename: suggestedFilename,
            mimeType: "image/jpeg",
            bytes: fullData,
            thumbnailBase64: thumbB64,
            sha256Hex: SHA256.hex(of: fullData)
        )
    }

    /// Down-scale the image so the longer edge <= thumbnailMaxEdge, encode
    /// as JPEG. Preserves aspect ratio.
    func thumbnail(from image: UIImage) throws -> Data {
        let size = image.size
        let longEdge = max(size.width, size.height)
        let scale: CGFloat = longEdge > Self.thumbnailMaxEdge
            ? Self.thumbnailMaxEdge / longEdge
            : 1.0
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        // Force scale=1.0 so the rendered JPEG has the exact pixel
        // dimensions we asked for. UIGraphicsImageRenderer defaults to
        // the screen scale (e.g. 3x on iPhone), which would 3x the
        // pixel count + bloat the thumbnail.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let data = scaled.jpegData(compressionQuality: Self.thumbnailJpegQuality) else {
            throw AttachmentError.thumbnailFailed
        }
        return data
    }
}
