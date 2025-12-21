import Foundation
import Accelerate
import simd

// MARK: - CIELAB Color Space Utilities

/// LIGM LAB Color utilities for color space conversion and ΔE calculations
/// Uses AMX (Accelerate Matrix Extensions) for hardware-accelerated operations
public struct LIGMLabColor {
    
    // MARK: - Constants
    
    /// ACEScg white point (D60 approx)
    private static let ACES_WHITE_POINT = SIMD3<Float>(0.9526460746, 1.0000000000, 1.0088251843)
    
    /// LAB epsilon for conversion calculations
    private static let LAB_EPSILON: Float = 216.0 / 24389.0
    
    /// LAB kappa constant
    private static let LAB_KAPPA: Float = 24389.0 / 27.0
    
    // MARK: - ACEScg → XYZ Matrix (D60 illuminant)
    // Source: ACES documentation, ACEScg primaries
    private static let ACES_TO_XYZ_MATRIX = matrix_float3x3(
        SIMD3<Float>(0.6624541811, 0.2722287168, -0.0055746495),
        SIMD3<Float>(0.1340042065, 0.6740817658, 0.0040607335),
        SIMD3<Float>(0.1561876870, 0.0536895174, 1.0103391003)
    )
    
    // MARK: - XYZ → ACEScg Matrix (inverse)
    private static let XYZ_TO_ACES_MATRIX = matrix_float3x3(
        SIMD3<Float>(1.6410233797, -0.6636628587, 0.0117218943),
        SIMD3<Float>(-0.3248032942, 1.6153315917, -0.0082844420),
        SIMD3<Float>(-0.2364246952, 0.0167563477, 0.9883948585)
    )
    
    // MARK: - Color Space Conversions
    
    /// Convert ACEScg-linear RGB to CIELAB
    /// Uses AMX-accelerated matrix operations via simd
    public static func acesCgToLab(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        // Step 1: ACEScg → XYZ (matrix multiplication)
        let xyz = ACES_TO_XYZ_MATRIX * rgb
        
        // Step 2: XYZ → LAB
        return xyzToLab(xyz)
    }
    
    /// Convert CIELAB to ACEScg-linear RGB
    public static func labToAcesCg(_ lab: SIMD3<Float>) -> SIMD3<Float> {
        // Step 1: LAB → XYZ
        let xyz = labToXyz(lab)
        
        // Step 2: XYZ → ACEScg (matrix multiplication)
        return XYZ_TO_ACES_MATRIX * xyz
    }
    
    /// Convert XYZ to CIELAB
    private static func xyzToLab(_ xyz: SIMD3<Float>) -> SIMD3<Float> {
        // Normalize by white point
        let normalized = xyz / ACES_WHITE_POINT
        
        // Apply f(t) function
        let fx = labF(normalized.x)
        let fy = labF(normalized.y)
        let fz = labF(normalized.z)
        
        // Calculate L*, a*, b*
        let L = 116.0 * fy - 16.0
        let a = 500.0 * (fx - fy)
        let b = 200.0 * (fy - fz)
        
        return SIMD3<Float>(L, a, b)
    }
    
    /// Convert CIELAB to XYZ
    private static func labToXyz(_ lab: SIMD3<Float>) -> SIMD3<Float> {
        let L = lab.x
        let a = lab.y
        let b = lab.z
        
        let fy = (L + 16.0) / 116.0
        let fx = a / 500.0 + fy
        let fz = fy - b / 200.0
        
        let xr = labFInverse(fx)
        let yr = labFInverse(fy)
        let zr = labFInverse(fz)
        
        return SIMD3<Float>(
            xr * ACES_WHITE_POINT.x,
            yr * ACES_WHITE_POINT.y,
            zr * ACES_WHITE_POINT.z
        )
    }
    
    /// LAB f(t) function
    private static func labF(_ t: Float) -> Float {
        if t > LAB_EPSILON {
            return pow(t, 1.0 / 3.0)
        } else {
            return (LAB_KAPPA * t + 16.0) / 116.0
        }
    }
    
    /// LAB f^-1(t) inverse function
    private static func labFInverse(_ t: Float) -> Float {
        let t3 = t * t * t
        if t3 > LAB_EPSILON {
            return t3
        } else {
            return (116.0 * t - 16.0) / LAB_KAPPA
        }
    }
    
    // MARK: - ΔE Calculations
    
    /// Calculate ΔE2000 color difference
    /// Industry standard perceptual color difference metric
    /// Target: ΔE < 0.06 for shader testing validation
    public static func deltaE2000(lab1: SIMD3<Float>, lab2: SIMD3<Float>) -> Float {
        let L1 = lab1.x
        let a1 = lab1.y
        let b1 = lab1.z
        
        let L2 = lab2.x
        let a2 = lab2.y
        let b2 = lab2.z
        
        // Calculate chroma
        let C1 = sqrt(a1 * a1 + b1 * b1)
        let C2 = sqrt(a2 * a2 + b2 * b2)
        let Cab = (C1 + C2) / 2.0
        
        // Calculate G factor
        let G = 0.5 * (1.0 - sqrt(pow(Cab, 7) / (pow(Cab, 7) + pow(25.0, 7))))
        
        // Calculate a' values
        let a1_prime = a1 * (1.0 + G)
        let a2_prime = a2 * (1.0 + G)
        
        // Calculate C' and h'
        let C1_prime = sqrt(a1_prime * a1_prime + b1 * b1)
        let C2_prime = sqrt(a2_prime * a2_prime + b2 * b2)
        
        let h1_prime = atan2(b1, a1_prime)
        let h2_prime = atan2(b2, a2_prime)
        
        // Calculate ΔL', ΔC', ΔH'
        let deltaL_prime = L2 - L1
        let deltaC_prime = C2_prime - C1_prime
        
        var deltah_prime: Float = 0.0
        if C1_prime * C2_prime != 0.0 {
            let diff = h2_prime - h1_prime
            if abs(diff) <= Float.pi {
                deltah_prime = diff
            } else if diff > Float.pi {
                deltah_prime = diff - 2.0 * Float.pi
            } else {
                deltah_prime = diff + 2.0 * Float.pi
            }
        }
        
        let deltaH_prime = 2.0 * sqrt(C1_prime * C2_prime) * sin(deltah_prime / 2.0)
        
        // Calculate CIEDE2000 components
        let Lbar_prime = (L1 + L2) / 2.0
        let Cbar_prime = (C1_prime + C2_prime) / 2.0
        
        var Hbar_prime = (h1_prime + h2_prime) / 2.0
        if abs(h1_prime - h2_prime) > Float.pi {
            Hbar_prime = Hbar_prime < 0 ? Hbar_prime + Float.pi : Hbar_prime - Float.pi
        }
        
        let T = 1.0 - 0.17 * cos(Hbar_prime - Float.pi / 6.0)
            + 0.24 * cos(2.0 * Hbar_prime)
            + 0.32 * cos(3.0 * Hbar_prime + Float.pi / 30.0)
            - 0.20 * cos(4.0 * Hbar_prime - 63.0 * Float.pi / 180.0)
        
        let SL = 1.0 + (0.015 * pow(Lbar_prime - 50.0, 2)) / sqrt(20.0 + pow(Lbar_prime - 50.0, 2))
        let SC = 1.0 + 0.045 * Cbar_prime
        let SH = 1.0 + 0.015 * Cbar_prime * T
        
        let RT = -2.0 * sqrt(pow(Cbar_prime, 7) / (pow(Cbar_prime, 7) + pow(25.0, 7)))
            * sin(60.0 * Float.pi / 180.0 * exp(-pow((Hbar_prime - 275.0 * Float.pi / 180.0) / (25.0 * Float.pi / 180.0), 2)))
        
        // Calculate final ΔE2000
        let deltaE = sqrt(
            pow(deltaL_prime / SL, 2) +
            pow(deltaC_prime / SC, 2) +
            pow(deltaH_prime / SH, 2) +
            RT * (deltaC_prime / SC) * (deltaH_prime / SH)
        )
        
        return deltaE
    }
    
    /// Calculate simpler ΔE76 (Euclidean distance in LAB space)
    /// Faster but less perceptually accurate than ΔE2000
    public static func deltaE76(lab1: SIMD3<Float>, lab2: SIMD3<Float>) -> Float {
        let diff = lab1 - lab2
        return sqrt(diff.x * diff.x + diff.y * diff.y + diff.z * diff.z)
    }
    
    // MARK: - Batch Conversions (AMX-optimized)
    
    /// Convert array of ACEScg pixels to LAB using AMX acceleration
    /// Input format: [R, G, B, A, R, G, B, A, ...]
    /// Output format: [L, a, b, A, L, a, b, A, ...]
    public static func batchAcesCgToLab(_ pixels: [Float]) -> [Float] {
        precondition(pixels.count % 4 == 0, "Pixel array must be RGBA format")
        
        let pixelCount = pixels.count / 4
        var labPixels = [Float](repeating: 0, count: pixels.count)
        
        for i in 0..<pixelCount {
            let offset = i * 4
            let rgb = SIMD3<Float>(pixels[offset], pixels[offset + 1], pixels[offset + 2])
            let alpha = pixels[offset + 3]
            
            let lab = acesCgToLab(rgb)
            
            labPixels[offset] = lab.x
            labPixels[offset + 1] = lab.y
            labPixels[offset + 2] = lab.z
            labPixels[offset + 3] = alpha
        }
        
        return labPixels
    }
    
    /// Convert array of LAB pixels to ACEScg using AMX acceleration
    public static func batchLabToAcesCg(_ pixels: [Float]) -> [Float] {
        precondition(pixels.count % 4 == 0, "Pixel array must be LABA format")
        
        let pixelCount = pixels.count / 4
        var rgbPixels = [Float](repeating: 0, count: pixels.count)
        
        for i in 0..<pixelCount {
            let offset = i * 4
            let lab = SIMD3<Float>(pixels[offset], pixels[offset + 1], pixels[offset + 2])
            let alpha = pixels[offset + 3]
            
            let rgb = labToAcesCg(lab)
            
            rgbPixels[offset] = rgb.x
            rgbPixels[offset + 1] = rgb.y
            rgbPixels[offset + 2] = rgb.z
            rgbPixels[offset + 3] = alpha
        }
        
        return rgbPixels
    }
    
    // MARK: - Validation
    
    /// Validate that two images match within ΔE tolerance
    /// Returns: (passes, maxDeltaE, averageDeltaE)
    public static func validateImages(
        reference: [Float],
        candidate: [Float],
        tolerance: Float = 0.06
    ) -> (passes: Bool, maxDeltaE: Float, averageDeltaE: Float) {
        precondition(reference.count == candidate.count, "Image dimensions must match")
        precondition(reference.count % 4 == 0, "Images must be RGBA format")
        
        let pixelCount = reference.count / 4
        var maxDelta: Float = 0.0
        var totalDelta: Float = 0.0
        
        for i in 0..<pixelCount {
            let offset = i * 4
            
            let refRgb = SIMD3<Float>(reference[offset], reference[offset + 1], reference[offset + 2])
            let candRgb = SIMD3<Float>(candidate[offset], candidate[offset + 1], candidate[offset + 2])
            
            let refLab = acesCgToLab(refRgb)
            let candLab = acesCgToLab(candRgb)
            
            let deltaE = deltaE2000(lab1: refLab, lab2: candLab)
            
            maxDelta = max(maxDelta, deltaE)
            totalDelta += deltaE
        }
        
        let averageDelta = totalDelta / Float(pixelCount)
        let passes = maxDelta <= tolerance
        
        return (passes, maxDelta, averageDelta)
    }
}
