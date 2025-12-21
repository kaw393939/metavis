import Foundation
import CryptoKit

public enum StableHash {
    /// Computes a SHA-256 digest and returns a lowercased hex string.
    public static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    public static func sha256Hex(utf8 string: String) -> String {
        sha256Hex(Data(string.utf8))
    }
}
