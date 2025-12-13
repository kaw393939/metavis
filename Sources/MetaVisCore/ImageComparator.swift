import Foundation
import CoreGraphics
import Accelerate

/// Utility for comparing image buffers (Deep Color).
public struct ImageComparator {
    
    public enum ComparisonResult {
        case match
        case different(maxDelta: Float, avgDelta: Float)
    }
    
    /// Compares two floating point buffers.
    /// - Parameters:
    ///   - bufferA: 32-bit float array (projected from texture)
    ///   - bufferB: 32-bit float array (golden reference)
    ///   - tolerance: Max allowable difference per channel
    public static func compare(bufferA: [Float], bufferB: [Float], tolerance: Float = 0.001) -> ComparisonResult {
        guard bufferA.count == bufferB.count else {
            return .different(maxDelta: 999.0, avgDelta: 999.0)
        }
        
        var maxDelta: Float = 0.0
        var totalDelta: Float = 0.0
        
        for i in 0..<bufferA.count {
            let diff = abs(bufferA[i] - bufferB[i])
            if diff > maxDelta { maxDelta = diff }
            totalDelta += diff
        }
        
        let avgDelta = totalDelta / Float(bufferA.count)
        
        if maxDelta > tolerance {
            return .different(maxDelta: maxDelta, avgDelta: avgDelta)
        }
        
        return .match
    }
}
