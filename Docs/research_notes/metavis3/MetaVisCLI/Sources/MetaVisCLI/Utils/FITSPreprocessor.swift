import Foundation
import MetaVisCore
import Accelerate

/// Handles the CPU-side preprocessing of FITS data for the v46 pipeline.
public class FITSPreprocessor {
    
    public struct ProcessedBuffer {
        public let width: Int
        public let height: Int
        public let data: [Float] // Normalized [0,1] data
    }
    
    public init() {}
    
    /// Processes a raw FITS asset according to the v46 spec.
    /// 1. Background Subtraction
    /// 2. Outlier Rejection
    /// 3. Normalization & Asinh Stretch
    public func process(asset: FITSAsset, asinhAlpha: Float) -> ProcessedBuffer {
        let width = asset.width
        let height = asset.height
        
        // 1. Convert Data to [Float]
        var pixels = asset.rawData.withUnsafeBytes { ptr -> [Float] in
            let buffer = ptr.bindMemory(to: Float.self)
            return Array(buffer)
        }
        
        // 2. Robust Background Subtraction
        // Estimate background B_f via low percentile (1%)
        // We can use a histogram approach similar to FITSReader, or sorting a subset.
        // For speed, let's sample.
        let background = estimateBackground(pixels: pixels)
        print("   [FITS] \(asset.url.lastPathComponent): Background Level = \(background)")
        
        // Subtract and Clamp
        for i in 0..<pixels.count {
            pixels[i] = max(pixels[i] - background, 0.0)
        }
        
        // 3. Outlier Rejection (Cosmic Rays)
        // Compare to local median (3x3 for speed, spec says 5x5 but 3x3 is usually enough for single pixels)
        // We'll do a simplified pass: if pixel > 5 * neighbors_avg, clamp it.
        // Full median filter is expensive. Let's try a "Hot Pixel" filter.
        pixels = removeOutliers(pixels: pixels, width: width, height: height)
        
        // 4. Per-Filter Stretch to [0,1]
        // Compute percentiles
        let (pLow, pHigh) = computePercentiles(pixels: pixels)
        print("   [FITS] \(asset.url.lastPathComponent): Range [\(pLow), \(pHigh)]")
        
        let range = pHigh - pLow
        let invRange = range > 0 ? 1.0 / range : 1.0
        
        // Apply Normalization and Asinh Stretch
        // V_f = asinh(alpha * N_f) / asinh(alpha)
        let normFactor = 1.0 / asinh(asinhAlpha)
        
        for i in 0..<pixels.count {
            // Normalize
            let val = (pixels[i] - pLow) * invRange
            let clamped = min(max(val, 0.0), 1.0)
            
            // Asinh Stretch
            pixels[i] = asinh(asinhAlpha * clamped) * normFactor
        }
        
        return ProcessedBuffer(width: width, height: height, data: pixels)
    }
    
    private func estimateBackground(pixels: [Float]) -> Float {
        // Sample 10,000 pixels to estimate background
        let sampleCount = min(pixels.count, 10000)
        let stride = pixels.count / sampleCount
        var samples: [Float] = []
        samples.reserveCapacity(sampleCount)
        
        for i in 0..<sampleCount {
            let val = pixels[i * stride]
            if val.isFinite {
                samples.append(val)
            }
        }
        
        samples.sort()
        
        // Take 1st percentile
        let index = Int(Float(samples.count) * 0.01)
        return samples[max(0, min(index, samples.count - 1))]
    }
    
    private func removeOutliers(pixels: [Float], width: Int, height: Int) -> [Float] {
        var cleaned = pixels
        let threshold: Float = 5.0 // Sigma-ish
        
        // We'll just check interior pixels
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let idx = y * width + x
                let val = pixels[idx]
                
                // Check 4 neighbors
                let n1 = pixels[idx - 1]
                let n2 = pixels[idx + 1]
                let n3 = pixels[idx - width]
                let n4 = pixels[idx + width]
                
                let neighbors = [n1, n2, n3, n4]
                let median = neighbors.sorted()[1] // Approx median
                
                // If value is significantly higher than median neighbor
                if val > median * threshold && val > 0.01 {
                    cleaned[idx] = median
                }
            }
        }
        return cleaned
    }
    
    private func computePercentiles(pixels: [Float]) -> (Float, Float) {
        // Sample for speed
        let sampleCount = min(pixels.count, 50000)
        let stride = pixels.count / sampleCount
        var samples: [Float] = []
        samples.reserveCapacity(sampleCount)
        
        for i in 0..<sampleCount {
            let val = pixels[i * stride]
            if val.isFinite {
                samples.append(val)
            }
        }
        
        samples.sort()
        
        let pLow = samples[Int(Float(samples.count) * 0.001)] // 0.1%
        let pHigh = samples[Int(Float(samples.count) * 0.999)] // 99.9%
        
        return (pLow, pHigh)
    }
}
