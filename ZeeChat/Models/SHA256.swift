import Foundation
import CryptoKit

/// Thin wrapper over CryptoKit's SHA256 so call sites stay readable and
/// we can swap to a pure-Swift impl later if we ever need to vendor it.
enum SHA256 {
    static func hash(_ bytes: [UInt8]) -> [UInt8] {
        let digest = CryptoKit.SHA256.hash(data: Data(bytes))
        return Array(digest)
    }
}
