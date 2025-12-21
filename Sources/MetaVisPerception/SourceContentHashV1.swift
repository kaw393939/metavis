import Foundation
import CryptoKit

/// Computes a stable content hash for a local file URL.
///
/// Purpose: produce a `sourceKey` that is stable across renames and machines.
///
/// Notes:
/// - This intentionally hashes file *contents* (not path) and caches results by (path,size,mtime).
/// - Used by ingest to generate deterministic IDs and can also be used to build stable MobileSAM cache keys.
public final class SourceContentHashV1: @unchecked Sendable {
    public static let shared = SourceContentHashV1()

    private let lock = NSLock()
    private var cache: [String: String] = [:]

    private init() {}

    public func contentHashHex(for url: URL) throws -> String {
        let fileURL = url.standardizedFileURL
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let cacheKey = "\(fileURL.path)|\(size)|\(mtime)"

        lock.lock()
        if let cached = cache[cacheKey] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let computed = try Self.computeContentHashHex(for: fileURL)

        lock.lock()
        cache[cacheKey] = computed
        lock.unlock()

        return computed
    }

    private static func computeContentHashHex(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        let chunkSize = 4 * 1024 * 1024
        while true {
            let data = try handle.read(upToCount: chunkSize) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
