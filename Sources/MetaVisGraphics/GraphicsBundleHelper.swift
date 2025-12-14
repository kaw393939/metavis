import Foundation

/// Helper to access the Bundle containing the compiled Metal Library.
public struct GraphicsBundleHelper {
    public static var bundle: Bundle {
        let b = Bundle.module
        // Debug: Print paths
        // if let resources = b.urls(forResourcesWithExtension: nil, subdirectory: nil) {
        //     print("📦 GraphicsBundle Contents: \(resources.map { $0.lastPathComponent })")
        // }
        return b
    }
}
