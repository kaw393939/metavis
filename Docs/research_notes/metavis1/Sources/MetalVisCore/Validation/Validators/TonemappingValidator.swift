import Foundation
import Metal
import simd
import Logging
import Yams

/// Validates tone mapping effect - HDR to SDR compression
@available(macOS 14.0, *)
public struct TonemappingValidator: EffectValidator {
    public let effectName = "tonemapping"
    public let tolerances: [String: Float]
    
    private let device: MTLDevice
    private let visionAnalyzer: VisionAnalyzer
    private let logger = Logger(label: "com.metalvis.validation.tonemapping")
    
    public init(device: MTLDevice, tolerances: [String: Float] = [:]) {
        self.device = device
        self.visionAnalyzer = VisionAnalyzer(device: device)
        
        var defaultTolerances: [String: Float] = [
            "black_level_max": 0.001,       // Black should stay black
            "monotonic_violations": 0,       // No tonal inversions allowed
            "clipping_max": 0.01,           // Max 1% clipping
            "ssim_min": 0.70                // Some structure change expected
        ]
        
        for (key, value) in tolerances {
            defaultTolerances[key] = value
        }
        self.tolerances = defaultTolerances
    }
    
    public func validate(
        frameData: Data,
        baselineData: Data?,
        parameters: EffectParameters,
        context: ValidationContext
    ) async throws -> EffectValidationResult {
        logger.info("Validating tonemapping at frame \(context.frameIndex)")
        
        var metrics: [String: Float] = [:]
        var diagnostics: [Diagnostic] = []
        var suggestedFixes: [String] = []
        
        // 1. Luminance Profile Analysis (for monotonicity)
        let luminanceProfile = try await visionAnalyzer.analyzeLuminanceProfile(data: frameData, regions: 10)
        
        // 2. Min/Max Analysis (for accurate black level)
        let (minLum, maxLum) = try await visionAnalyzer.getMinMaxLuminance(data: frameData)
        
        metrics["min_luminance"] = minLum
        metrics["max_luminance"] = maxLum
        metrics["dynamic_range"] = maxLum - minLum
        metrics["black_level"] = minLum
        
        // Black Level Test
        let maxBlack = tolerances["black_level_max"] ?? 0.001
        if minLum > maxBlack {
            diagnostics.append(Diagnostic(
                severity: .warning,
                code: "TONEMAP_BLACK_LIFTED",
                message: "Tonemapping lifted black level to \(String(format: "%.4f", minLum))",
                context: [
                    "black_level": "\(minLum)",
                    "max_allowed": "\(maxBlack)"
                ]
            ))
            suggestedFixes.append("Check fx_tonemap_aces for correct black point handling")
        }
        
        // 3. Monotonicity Test
        // Output should never decrease as input increases
        let rings = luminanceProfile.ringLuminance
        var monotonicViolations = 0
        for i in 1..<rings.count {
            // In a properly tonemapped gradient, each ring should be <= the next inner ring
            // (assuming center is brightest)
            if i > 1 && rings[i] > rings[i-1] + 0.01 {
                // Allow small increases due to noise/gradient
                // But large increases indicate tonal inversion
                if rings[i] > rings[i-1] + 0.05 {
                    monotonicViolations += 1
                }
            }
        }
        metrics["monotonic_violations"] = Float(monotonicViolations)
        
        if monotonicViolations > 0 {
            diagnostics.append(Diagnostic(
                severity: .error,
                code: "TONEMAP_NON_MONOTONIC",
                message: "Tonemapping has \(monotonicViolations) monotonicity violation(s)",
                context: [
                    "violations": "\(monotonicViolations)"
                ]
            ))
            suggestedFixes.append("Verify ACES fit curve is correctly implemented")
        }
        
        // 4. Clipping Analysis
        let clippingPercentage = try await visionAnalyzer.analyzeClipping(data: frameData, threshold: 0.99)
        metrics["clipping_percentage"] = clippingPercentage
        
        let maxClipping = tolerances["clipping_max"] ?? 0.01
        if clippingPercentage > maxClipping {
            diagnostics.append(Diagnostic(
                severity: .warning,
                code: "TONEMAP_CLIPPING",
                message: "Tonemapping shows \(String(format: "%.1f", clippingPercentage * 100))% clipping",
                context: [
                    "clipping": "\(clippingPercentage)"
                ]
            ))
            suggestedFixes.append("Adjust exposure or whitePoint parameter")
        }
        
        // 5. Structural Comparison
        if let baseline = baselineData {
            let ssim = try await visionAnalyzer.calculateSSIM(originalData: baseline, modifiedData: frameData)
            metrics["ssim"] = ssim.overall
            
            // Tonemapping changes contrast significantly, so lower SSIM is expected
            let minSSIM = tolerances["ssim_min"] ?? 0.70
            if ssim.overall < minSSIM {
                diagnostics.append(Diagnostic(
                    severity: .info,
                    code: "TONEMAP_HIGH_CONTRAST",
                    message: "Tonemapping produced significant contrast change (SSIM: \(String(format: "%.3f", ssim.overall)))",
                    context: [
                        "ssim": "\(ssim.overall)"
                    ]
                ))
            }
        }
        
        // 6. Color Distribution Analysis
        let colorDist = try await visionAnalyzer.analyzeColorDistribution(data: frameData)
        metrics["avg_r"] = colorDist.averageColor.x
        metrics["avg_g"] = colorDist.averageColor.y
        metrics["avg_b"] = colorDist.averageColor.z
        
        // Determine pass/fail
        let hasErrors = diagnostics.contains { $0.severity == .error }
        let passed = !hasErrors
        
        return EffectValidationResult(
            effectName: effectName,
            passed: passed,
            metrics: metrics.mapValues { Double($0) },
            thresholds: tolerances.mapValues { Double($0) },
            diagnostics: diagnostics,
            suggestedFixes: suggestedFixes,
            frameIndex: context.frameIndex
        )
    }
}
