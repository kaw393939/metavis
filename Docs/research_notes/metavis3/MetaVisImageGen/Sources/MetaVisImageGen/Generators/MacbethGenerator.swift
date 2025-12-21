import Foundation
import simd

/// Generates a synthetic Macbeth ColorChecker chart.
/// Used for calibration and verification.
public struct MacbethGenerator {
    
    public init() {}
    
    public struct Patch {
        public let name: String
        public let sRGB: SIMD3<Double> // 0-1 Linear sRGB
    }
    
    // Standard Macbeth ColorChecker values (Linear sRGB approximation)
    // These should ideally be spectral data converted to ACES, but for now we use the standard sRGB reference values.
    public let patches: [Patch] = [
        Patch(name: "Dark Skin", sRGB: SIMD3(0.11, 0.08, 0.06)),
        Patch(name: "Light Skin", sRGB: SIMD3(0.48, 0.36, 0.31)),
        Patch(name: "Blue Sky", sRGB: SIMD3(0.19, 0.28, 0.45)),
        Patch(name: "Foliage", sRGB: SIMD3(0.13, 0.17, 0.08)),
        Patch(name: "Blue Flower", sRGB: SIMD3(0.26, 0.25, 0.46)),
        Patch(name: "Bluish Green", sRGB: SIMD3(0.26, 0.53, 0.44)),
        Patch(name: "Orange", sRGB: SIMD3(0.62, 0.31, 0.06)),
        Patch(name: "Purplish Blue", sRGB: SIMD3(0.15, 0.17, 0.41)),
        Patch(name: "Moderate Red", sRGB: SIMD3(0.53, 0.12, 0.14)),
        Patch(name: "Purple", sRGB: SIMD3(0.18, 0.07, 0.20)),
        Patch(name: "Yellow Green", sRGB: SIMD3(0.44, 0.58, 0.10)),
        Patch(name: "Orange Yellow", sRGB: SIMD3(0.67, 0.48, 0.08)),
        Patch(name: "Blue", sRGB: SIMD3(0.06, 0.08, 0.36)),
        Patch(name: "Green", sRGB: SIMD3(0.14, 0.36, 0.10)),
        Patch(name: "Red", sRGB: SIMD3(0.43, 0.06, 0.06)),
        Patch(name: "Yellow", sRGB: SIMD3(0.78, 0.69, 0.08)),
        Patch(name: "Magenta", sRGB: SIMD3(0.53, 0.11, 0.34)),
        Patch(name: "Cyan", sRGB: SIMD3(0.05, 0.32, 0.46)),
        Patch(name: "White", sRGB: SIMD3(0.95, 0.95, 0.95)),
        Patch(name: "Neutral 8", sRGB: SIMD3(0.78, 0.78, 0.78)),
        Patch(name: "Neutral 6.5", sRGB: SIMD3(0.57, 0.57, 0.57)),
        Patch(name: "Neutral 5", sRGB: SIMD3(0.36, 0.36, 0.36)),
        Patch(name: "Neutral 3.5", sRGB: SIMD3(0.19, 0.19, 0.19)),
        Patch(name: "Black", sRGB: SIMD3(0.05, 0.05, 0.05))
    ]
    
    /// Generates a 10-second test pattern description (JSON-like structure or just data).
    /// For now, returns the patch data.
    public func generateChartData() -> [Patch] {
        return patches
    }
}
