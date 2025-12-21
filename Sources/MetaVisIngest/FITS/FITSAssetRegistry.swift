import Foundation
import MetaVisCore

/// Caches loaded FITS assets to avoid redundant disk I/O and parsing.
public actor FITSAssetRegistry {
    public static let shared = FITSAssetRegistry()

    private var cache: [URL: FITSAsset] = [:]
    private let reader = FITSReader()

    public init() {}

    public func load(url: URL) throws -> FITSAsset {
        if let cached = cache[url] { return cached }
        let asset = try reader.read(url: url)
        cache[url] = asset
        return asset
    }

    public func register(asset: FITSAsset) {
        cache[asset.url] = asset
    }

    public func unload(url: URL) {
        cache.removeValue(forKey: url)
    }

    public func clearCache() {
        cache.removeAll()
    }
}
