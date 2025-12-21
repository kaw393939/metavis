import Foundation

public enum AssetQuality {
    case proxy
    case preview
    case original
}

/// Manages the lifecycle and resolution of Assets.
/// Handles the logic for selecting the best available representation based on requested quality.
public class AssetManager {
    private var assets: [UUID: Asset] = [:]
    private let fileManager = FileManager.default
    
    public init() {}
    
    public func register(asset: Asset) {
        assets[asset.id] = asset
    }
    
    public func get(id: UUID) -> Asset? {
        return assets[id]
    }
    
    /// Resolves the best URL for an asset based on the requested quality.
    /// - Parameters:
    ///   - assetId: The ID of the asset.
    ///   - quality: The desired quality level.
    /// - Returns: The URL to the file or stream, or nil if not found.
    public func resolve(assetId: UUID, quality: AssetQuality) -> URL? {
        guard let asset = assets[assetId] else { return nil }
        
        // 1. Check for specific representation
        switch quality {
        case .proxy:
            if let rep = asset.representations.first(where: { $0.type == .proxy }) {
                return rep.url
            }
            // Fallback to original if proxy missing
            fallthrough
            
        case .preview:
            // Prefer stream or proxy, then original
            if let rep = asset.representations.first(where: { $0.type == .stream }) {
                return rep.url
            }
            if let rep = asset.representations.first(where: { $0.type == .proxy }) {
                return rep.url
            }
            fallthrough
            
        case .original:
            if let rep = asset.representations.first(where: { $0.type == .original }) {
                return rep.url
            }
            // Legacy fallback: use the main URL property
            return asset.url
        }
    }
    
    /// Updates an asset with a new representation (e.g. when a proxy is generated or master is synced).
    public func addRepresentation(assetId: UUID, representation: AssetRepresentation) {
        guard var asset = assets[assetId] else { return }
        
        // Remove existing of same type if any
        asset.representations.removeAll { $0.type == representation.type }
        asset.representations.append(representation)
        
        assets[assetId] = asset
        print("AssetManager: Updated \(asset.name) with \(representation.type) representation.")
    }
}
