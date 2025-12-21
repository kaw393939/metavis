import Foundation

/// Manages the collection of assets in the session.
public struct AssetRegistry: Codable, Sendable {
    private var assets: [UUID: Asset] = [:]
    
    public init() {}
    
    public mutating func register(_ asset: Asset) {
        assets[asset.id] = asset
    }
    
    public func asset(for id: UUID) -> Asset? {
        return assets[id]
    }
    
    public mutating func remove(id: UUID) {
        assets.removeValue(forKey: id)
    }
    
    public var allAssets: [Asset] {
        return Array(assets.values)
    }
}
