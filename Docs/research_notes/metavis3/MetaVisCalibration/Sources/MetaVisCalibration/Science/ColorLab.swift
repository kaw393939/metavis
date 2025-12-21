import Foundation
import simd

/// High-precision Color Science Lab.
/// Uses Double precision for all calculations to ensure sub-0.06 Delta E.
public struct ColorLab {
    
    public init() {}
    
    public struct LabColor: Sendable {
        public let L: Double
        public let a: Double
        public let b: Double
        
        public init(L: Double, a: Double, b: Double) {
            self.L = L
            self.a = a
            self.b = b
        }
    }
    
    /// Converts Linear sRGB (0-1) to Lab (D65)
    public func linearSRGBToLab(_ rgb: SIMD3<Double>) -> LabColor {
        // 1. Linear sRGB to XYZ (D65)
        // Using ACES.Rec709_to_XYZ (which is D65)
        let X = ACES.Rec709_to_XYZ.columns.0.x * rgb.x + ACES.Rec709_to_XYZ.columns.1.x * rgb.y + ACES.Rec709_to_XYZ.columns.2.x * rgb.z
        let Y = ACES.Rec709_to_XYZ.columns.0.y * rgb.x + ACES.Rec709_to_XYZ.columns.1.y * rgb.y + ACES.Rec709_to_XYZ.columns.2.y * rgb.z
        let Z = ACES.Rec709_to_XYZ.columns.0.z * rgb.x + ACES.Rec709_to_XYZ.columns.1.z * rgb.y + ACES.Rec709_to_XYZ.columns.2.z * rgb.z
        
        // 2. XYZ to Lab
        // Reference White D65 (2 degree observer)
        let Xn = 0.95047
        let Yn = 1.00000
        let Zn = 1.08883
        
        let x = X / Xn
        let y = Y / Yn
        let z = Z / Zn
        
        func f(_ t: Double) -> Double {
            return t > 0.008856 ? pow(t, 1.0/3.0) : (7.787 * t + 16.0/116.0)
        }
        
        let L = 116.0 * f(y) - 16.0
        let a = 500.0 * (f(x) - f(y))
        let b = 200.0 * (f(y) - f(z))
        
        return LabColor(L: L, a: a, b: b)
    }
    
    /// Calculates Delta E 2000 (CIEDE2000) with Double precision.
    public func deltaE2000(_ lab1: LabColor, _ lab2: LabColor) -> Double {
        let kL = 1.0
        let kC = 1.0
        let kH = 1.0
        
        let L1 = lab1.L; let a1 = lab1.a; let b1 = lab1.b
        let L2 = lab2.L; let a2 = lab2.a; let b2 = lab2.b
        
        let C1 = sqrt(a1 * a1 + b1 * b1)
        let C2 = sqrt(a2 * a2 + b2 * b2)
        let C_bar = (C1 + C2) / 2.0
        
        let G = 0.5 * (1.0 - sqrt(pow(C_bar, 7) / (pow(C_bar, 7) + pow(25.0, 7))))
        
        let a1_prime = (1.0 + G) * a1
        let a2_prime = (1.0 + G) * a2
        
        let C1_prime = sqrt(a1_prime * a1_prime + b1 * b1)
        let C2_prime = sqrt(a2_prime * a2_prime + b2 * b2)
        
        let h1_prime = (b1 == 0 && a1_prime == 0) ? 0 : atan2(b1, a1_prime) * 180.0 / .pi
        let h2_prime = (b2 == 0 && a2_prime == 0) ? 0 : atan2(b2, a2_prime) * 180.0 / .pi
        
        let h1 = h1_prime >= 0 ? h1_prime : h1_prime + 360
        let h2 = h2_prime >= 0 ? h2_prime : h2_prime + 360
        
        let delta_L_prime = L2 - L1
        let delta_C_prime = C2_prime - C1_prime
        
        var delta_h_prime = 0.0
        if (C1_prime * C2_prime) != 0 {
            if abs(h2 - h1) <= 180 {
                delta_h_prime = h2 - h1
            } else if (h2 - h1) > 180 {
                delta_h_prime = h2 - h1 - 360
            } else {
                delta_h_prime = h2 - h1 + 360
            }
        }
        
        let delta_H_prime = 2.0 * sqrt(C1_prime * C2_prime) * sin((delta_h_prime / 2.0) * .pi / 180.0)
        
        let L_bar_prime = (L1 + L2) / 2.0
        let C_bar_prime = (C1_prime + C2_prime) / 2.0
        
        var h_bar_prime = 0.0
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
        
        let T = 1.0 - 0.17 * cos((h_bar_prime - 30) * .pi / 180.0) +
                0.24 * cos((2 * h_bar_prime) * .pi / 180.0) +
                0.32 * cos((3 * h_bar_prime + 6) * .pi / 180.0) -
                0.20 * cos((4 * h_bar_prime - 63) * .pi / 180.0)
        
        let delta_theta = 30 * exp(-pow((h_bar_prime - 275) / 25, 2))
        let R_C = 2 * sqrt(pow(C_bar_prime, 7) / (pow(C_bar_prime, 7) + pow(25.0, 7)))
        let S_L = 1 + (0.015 * pow(L_bar_prime - 50, 2)) / sqrt(20 + pow(L_bar_prime - 50, 2))
        let S_C = 1 + 0.045 * C_bar_prime
        let S_H = 1 + 0.015 * C_bar_prime * T
        let R_T = -sin(2 * delta_theta * .pi / 180.0) * R_C
        
        let term1 = delta_L_prime / (kL * S_L)
        let term2 = delta_C_prime / (kC * S_C)
        let term3 = delta_H_prime / (kH * S_H)
        
        return sqrt(term1 * term1 + term2 * term2 + term3 * term3 + R_T * term2 * term3)
    }
}
