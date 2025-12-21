import Foundation
import MetaVisCore
import simd

public struct Star {
    public let position: SIMD2<Float> // Normalized UV [0,1]
    public let magnitude: Float       // Relative magnitude
    public let color: SIMD3<Float>    // RGB Color hint
}

public class StarDetector {
    
    public init() {}
    
    /// Detects stars in the provided FITS buffer.
    /// - Parameters:
    ///   - buffer: The processed FITS buffer (usually F090W or F200W).
    ///   - colorMap: A closure or lookup to get the color at a specific UV.
    ///   - threshold: Detection threshold (0.0 - 1.0).
    public func detect(buffer: FITSPreprocessor.ProcessedBuffer, threshold: Float = 0.7, colorSampler: (SIMD2<Float>) -> SIMD3<Float>) -> [Star] {
        var stars: [Star] = []
        let width = buffer.width
        let height = buffer.height
        let data = buffer.data
        
        print("   [StarDetector] Scanning \(width)x\(height) image...")
        
        // Simple local maxima detection
        // We skip edges
        for y in 2..<(height - 2) {
            for x in 2..<(width - 2) {
                let idx = y * width + x
                let val = data[idx]
                
                if val > threshold {
                    // Check 8 neighbors
                    let n1 = data[idx - 1]
                    let n2 = data[idx + 1]
                    let n3 = data[idx - width]
                    let n4 = data[idx + width]
                    let n5 = data[idx - width - 1]
                    let n6 = data[idx - width + 1]
                    let n7 = data[idx + width - 1]
                    let n8 = data[idx + width + 1]
                    
                    if val > n1 && val > n2 && val > n3 && val > n4 &&
                       val > n5 && val > n6 && val > n7 && val > n8 {
                        
                        // Found a peak!
                        // Calculate UV
                        let u = Float(x) / Float(width)
                        let v = Float(y) / Float(height) // Metal UVs are usually top-down or bottom-up depending on texture loading. 
                                                         // FITS is usually bottom-up. Metal textures are top-down (0,0 is top-left).
                                                         // We'll assume standard UV mapping where (0,0) is top-left for now, 
                                                         // but FITS might be flipped. We'll check later.
                        
                        // Magnitude estimation: m = -log10(b)
                        // Since val is [0,1], brighter stars have lower magnitude (standard astronomy)
                        // But for our shader, we might want a "brightness" value.
                        // The spec says: m = -log10(peak_value + epsilon)
                        let mag = -log10(val + 1e-6)
                        
                        let color = colorSampler(SIMD2<Float>(u, v))
                        
                        stars.append(Star(position: SIMD2<Float>(u, v), magnitude: mag, color: color))
                    }
                }
            }
        }
        
        print("   [StarDetector] Found \(stars.count) stars.")
        return stars
    }
}
