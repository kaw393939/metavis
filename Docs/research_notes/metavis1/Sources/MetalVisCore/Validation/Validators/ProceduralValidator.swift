import Foundation
import Metal
import simd
import Logging

/// Validates procedural field outputs for mathematical correctness
/// Checks: Codomain range, Distribution (Histogram), Continuity (Gradient magnitude)
@available(macOS 14.0, *)
public struct ProceduralValidator: EffectValidator {
    public let effectName = "procedural_field"
    public let tolerances: [String: Float]
    
    private let device: MTLDevice
    private let logger = Logger(label: "com.metalvis.validation.procedural")
    
    public init(device: MTLDevice, tolerances: [String: Float] = [:]) {
        self.device = device
        
        // Default tolerances
        var defaultTolerances: [String: Float] = [
            "range_min": 0.0,      // Expected minimum value
            "range_max": 1.0,      // Expected maximum value
            "out_of_bounds_max": 0.0, // Max % of pixels allowed out of bounds
            "discontinuity_max": 0.05 // Max % of pixels with extreme gradients (discontinuities)
        ]
        
        for (key, value) in tolerances {
            defaultTolerances[key] = value
        }
        self.tolerances = defaultTolerances
    }
    
    public enum ValidationError: Error {
        case invalidDataSize
    }
    
    public func validate(
        frameData: Data,
        baselineData: Data?,
        parameters: EffectParameters,
        context: ValidationContext
    ) async throws -> EffectValidationResult {
        logger.info("Validating procedural field at frame \(context.frameIndex)")
        
        var metrics: [String: Double] = [:]
        var diagnostics: [Diagnostic] = []
        var suggestedFixes: [String] = []
        
        // 1. Parse Texture Data (RGBA16Float)
        // Assuming frameData contains raw texture bytes
        let width = context.width
        let height = context.height
        let pixelCount = width * height
        
        // Convert Data to Float array (R channel only for scalar fields)
        // RGBA16Float = 8 bytes per pixel
        let bytesPerPixel = 8
        
        guard frameData.count >= pixelCount * bytesPerPixel else {
            throw ValidationError.invalidDataSize
        }
        
        // 2. Statistical Analysis
        var minVal: Float = .greatestFiniteMagnitude
        var maxVal: Float = -.greatestFiniteMagnitude
        var sum: Float = 0.0
        var sumSq: Float = 0.0
        var outOfBoundsCount = 0
        var discontinuityCount = 0
        
        let expectedMin = tolerances["range_min"] ?? 0.0
        let expectedMax = tolerances["range_max"] ?? 1.0
        let discontinuityThreshold: Float = 0.5 // Threshold for "extreme" gradient
        
        // Unsafe access for speed
        frameData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            if let baseAddress = ptr.baseAddress {
                let float16Ptr = baseAddress.bindMemory(to: Float16.self, capacity: pixelCount * 4)
                
                for y in 0..<height {
                    for x in 0..<width {
                        let i = y * width + x
                        // Read Red channel (index i*4)
                        let val = Float(float16Ptr[i * 4])
                        
                        if val < minVal { minVal = val }
                        if val > maxVal { maxVal = val }
                        sum += val
                        sumSq += val * val
                        
                        if val < expectedMin || val > expectedMax {
                            outOfBoundsCount += 1
                        }
                        
                        // Gradient Continuity Check
                        if x < width - 1 {
                            let rightVal = Float(float16Ptr[(i + 1) * 4])
                            if abs(rightVal - val) > discontinuityThreshold {
                                discontinuityCount += 1
                                continue // Count pixel only once
                            }
                        }
                        if y < height - 1 {
                            let downVal = Float(float16Ptr[(i + width) * 4])
                            if abs(downVal - val) > discontinuityThreshold {
                                discontinuityCount += 1
                            }
                        }
                    }
                }
            }
        }
        
        let mean = sum / Float(pixelCount)
        let variance = (sumSq / Float(pixelCount)) - (mean * mean)
        let outOfBoundsPct = Float(outOfBoundsCount) / Float(pixelCount)
        let discontinuityPct = Float(discontinuityCount) / Float(pixelCount)
        
        metrics["min_value"] = Double(minVal)
        metrics["max_value"] = Double(maxVal)
        metrics["mean_value"] = Double(mean)
        metrics["variance"] = Double(variance)
        metrics["out_of_bounds_pct"] = Double(outOfBoundsPct)
        metrics["discontinuity_pct"] = Double(discontinuityPct)
        
        // 3. Validation Logic
        var passed = true
        
        // Check Range
        if outOfBoundsPct > (tolerances["out_of_bounds_max"] ?? 0.0) {
            passed = false
            diagnostics.append(Diagnostic(
                severity: .error,
                code: "RANGE_ERROR",
                message: "Field values out of bounds. Found \(String(format: "%.2f", outOfBoundsPct * 100))% pixels outside [\(expectedMin), \(expectedMax)]. Range: [\(minVal), \(maxVal)]",
                location: .center
            ))
            suggestedFixes.append("Check normalization logic in shader. Ensure noise is remapped correctly.")
        }
        
        // Check Distribution (Variance)
        if variance < 0.0001 {
             // Warning only, as solid color might be intended in some cases (e.g. constant node)
             // But for "procedural_texture" effect which implies noise, it's likely a bug.
             diagnostics.append(Diagnostic(
                severity: .warning,
                code: "LOW_VARIANCE",
                message: "Field has near-zero variance (\(String(format: "%.6f", variance))). Output appears to be a solid color.",
                location: .center
            ))
            suggestedFixes.append("Verify noise frequency is not 0. Check if shader is compiling correctly.")
        }
        
        // Check Continuity
        if discontinuityPct > (tolerances["discontinuity_max"] ?? 0.05) {
            // Warning, as Worley noise naturally has discontinuities
            diagnostics.append(Diagnostic(
                severity: .warning,
                code: "DISCONTINUITY",
                message: "High gradient discontinuity detected (\(String(format: "%.2f", discontinuityPct * 100))%).",
                location: .center
            ))
            suggestedFixes.append("If using Perlin/Simplex, check for coordinate wrapping issues or float precision errors.")
        }
        
        return EffectValidationResult(
            effectName: effectName,
            passed: passed,
            metrics: metrics,
            thresholds: tolerances.mapValues { Double($0) },
            diagnostics: diagnostics,
            suggestedFixes: suggestedFixes,
            timestamp: Date(),
            frameIndex: context.frameIndex
        )
    }
}
