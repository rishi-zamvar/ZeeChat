import Foundation
import CryptoKit

/// Thin wrapper over CryptoKit's SHA256 so call sites stay readable and
/// we can swap to a pure-Swift impl later if we ever need to vendor it.
enum SHA256 {
    /// SHA256 of arbitrary Data as a lowercase 64-char hex string. Used by
    /// `Checksum` for message checksums and by `AttachmentClient` for
    /// upload dedup keys.
    static func hex(of data: Data) -> String {
        let digest = CryptoKit.SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
