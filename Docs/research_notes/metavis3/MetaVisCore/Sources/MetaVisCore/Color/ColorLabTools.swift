import Foundation
import simd

/// Tools for comparing images and calculating color differences.
/// Essential for the "MetaVis Lab" QA module.
public struct ColorLabTools: Sendable {
    
    public init() {}
    
    /// Calculates the Delta E 76 (Euclidean distance in Lab space) between two colors.
    public func deltaE76(_ c1: SIMD3<Float>, _ c2: SIMD3<Float>) -> Float {
        return distance(c1, c2)
    }
    
    /// Calculates the Delta E 2000 (CIEDE2000) between two Lab colors.
    /// This is the industry standard for color difference.
    /// Inputs are expected to be in Lab color space (L: 0-100, a: -128..127, b: -128..127).
    public func deltaE2000(lab1: SIMD3<Float>, lab2: SIMD3<Float>) -> Float {
        let kL: Float = 1.0
        let kC: Float = 1.0
        let kH: Float = 1.0
        
        let L1 = lab1.x; let a1 = lab1.y; let b1 = lab1.z
        let L2 = lab2.x; let a2 = lab2.y; let b2 = lab2.z
        
        let C1 = sqrt(a1 * a1 + b1 * b1)
        let C2 = sqrt(a2 * a2 + b2 * b2)
        let C_bar = (C1 + C2) / 2.0
        
        let G = 0.5 * (1.0 - sqrt(pow(C_bar, 7) / (pow(C_bar, 7) + pow(25.0, 7))))
        
        let a1_prime = (1.0 + G) * a1
        let a2_prime = (1.0 + G) * a2
        
        let C1_prime = sqrt(a1_prime * a1_prime + b1 * b1)
        let C2_prime = sqrt(a2_prime * a2_prime + b2 * b2)
        
        let h1_prime = (b1 == 0 && a1_prime == 0) ? 0 : atan2(b1, a1_prime) * 180 / .pi
        let h2_prime = (b2 == 0 && a2_prime == 0) ? 0 : atan2(b2, a2_prime) * 180 / .pi
        
        let h1 = h1_prime >= 0 ? h1_prime : h1_prime + 360
        let h2 = h2_prime >= 0 ? h2_prime : h2_prime + 360
        
        let delta_L_prime = L2 - L1
        let delta_C_prime = C2_prime - C1_prime
        
        var delta_h_prime: Float = 0.0
        if (C1_prime * C2_prime) != 0 {
            if abs(h2 - h1) <= 180 {
                delta_h_prime = h2 - h1
            } else if (h2 - h1) > 180 {
                delta_h_prime = h2 - h1 - 360
            } else {
                delta_h_prime = h2 - h1 + 360
            }
        }
        
        let delta_H_prime = 2.0 * sqrt(C1_prime * C2_prime) * sin((delta_h_prime / 2.0) * .pi / 180)
        
        let L_bar_prime = (L1 + L2) / 2.0
        let C_bar_prime = (C1_prime + C2_prime) / 2.0
        
        var h_bar_prime: Float = 0.0
        if (C1_prime * C2_prime) != 0 {
            if abs(h1 - h2) <= 180 {
                h_bar_prime = (h1 + h2) / 2.0
            } else if (h1 + h2) < 360 {
                h_bar_prime = (h1 + h2 + 360) / 2.0
            } else {
                h_bar_prime = (h1 + h2 - 360) / 2.0
            }
        } else {
            h_bar_prime = h1 + h2
        }
        
        let T = 1.0 - 0.17 * cos((h_bar_prime - 30) * .pi / 180) +
                0.24 * cos((2 * h_bar_prime) * .pi / 180) +
                0.32 * cos((3 * h_bar_prime + 6) * .pi / 180) -
                0.20 * cos((4 * h_bar_prime - 63) * .pi / 180)
        
        let delta_theta = 30 * exp(-pow((h_bar_prime - 275) / 25, 2))
        let R_C = 2 * sqrt(pow(C_bar_prime, 7) / (pow(C_bar_prime, 7) + pow(25.0, 7)))
        let S_L = 1 + (0.015 * pow(L_bar_prime - 50, 2)) / sqrt(20 + pow(L_bar_prime - 50, 2))
        let S_C = 1 + 0.045 * C_bar_prime
        let S_H = 1 + 0.015 * C_bar_prime * T
        let R_T = -sin(2 * delta_theta * .pi / 180) * R_C
        
        let term1 = delta_L_prime / (kL * S_L)
        let term2 = delta_C_prime / (kC * S_C)
        let term3 = delta_H_prime / (kH * S_H)
        
        return sqrt(term1 * term1 + term2 * term2 + term3 * term3 + R_T * term2 * term3)
    }
    
    /// Calculates the Mean Squared Error (MSE) between two buffers.
    /// Useful for "Difference Mode" visualization.
    public func calculateMSE(reference: [Float], test: [Float]) -> Float {
        guard reference.count == test.count else { return -1.0 }
        
        var sum: Float = 0
        for i in 0..<reference.count {
            let diff = reference[i] - test[i]
            sum += diff * diff
        }
        
        return sum / Float(reference.count)
    }
    
    /// Generates a "Heatmap" buffer showing where the differences are.
    /// Returns a buffer of the same size where each pixel is the delta.
    public func generateDifferenceMap(reference: [SIMD3<Float>], test: [SIMD3<Float>]) -> [SIMD3<Float>] {
        guard reference.count == test.count else { return [] }
        
        return zip(reference, test).map { ref, t in
            let diff = abs(ref - t)
            // Boost the difference for visibility (e.g. x10)
            return diff * 10.0
        }
    }
}
