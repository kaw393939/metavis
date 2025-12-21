import Foundation
import MetaVisCore

/// A tool responsible for scanning, validating, and importing assets into a Project.
public struct IngestTool: Tool {
    public let name = "Universal Ingest Tool"
    public let description = "Scans for media files and registers them as assets in the project."
    
    public init() {}
    
    public func run(project: inout Project, devices: [any VirtualDevice]) async throws {
        print("🔧 Running IngestTool...")
        
        // 1. Iterate over all devices that provide storage
        for device in devices {
            // Check if device has a searchPath parameter
            guard let searchPath = device.parameters["searchPath"]?.asString else {
                continue
            }
            
            print("   📡 Scanning Device: \(device.name) at \(searchPath)")
            
            // Get allowed extensions or default to common media types
            let allowedExtensions = device.parameters["allowedExtensions"]?.asString?
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespaces).lowercased() } 
                ?? ["fits", "mov", "mp4", "jpg", "png", "wav"]
            
            let assetsDir = URL(fileURLWithPath: searchPath)
            let fileManager = FileManager.default
            
            // Recursive Scan
            if let enumerator = fileManager.enumerator(at: assetsDir, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    let ext = fileURL.pathExtension.lowercased()
                    if allowedExtensions.contains(ext) {
                        do {
                            // Use the new Self-Probing Init
                            let asset = try await Asset(from: fileURL)
                            project.assets.append(asset)
                            print("   ✅ Ingested: \(asset.name) (\(asset.type))")
                        } catch {
                            print("   ⚠️ Failed to ingest \(fileURL.lastPathComponent): \(error)")
                        }
                    }
                }
            }
        }
    }
}
