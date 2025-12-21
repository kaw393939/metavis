import Foundation

/// Manages loaded FITS assets to prevent redundant disk I/O and parsing.
/// Thread-safe via Actor isolation.
public actor FITSAssetRegistry {
    
    /// Shared singleton instance for global access.
    public static let shared = FITSAssetRegistry()
    
    private var cache: [URL: FITSAsset] = [:]
    private let reader = FITSReader()
    
    public init() {}
    
    /// Loads a FITS asset from the given URL.
    /// Returns the cached instance if available, otherwise reads from disk.
    public func load(url: URL) throws -> FITSAsset {
        if let asset = cache[url] {
            return asset
        }
        
        // Read from disk
        let asset = try reader.read(url: url)
        
        // Cache it
        cache[url] = asset
        
        return asset
    }
    
    /// Manually registers an asset (e.g. created synthetically).
    public func register(asset: FITSAsset) {
        cache[asset.url] = asset
    }
    
    /// Clears all cached assets to free memory.
    public func clearCache() {
        cache.removeAll()
    }
    
    /// Removes a specific asset from the cache.
    public func unload(url: URL) {
        cache.removeValue(forKey: url)
    }
}
