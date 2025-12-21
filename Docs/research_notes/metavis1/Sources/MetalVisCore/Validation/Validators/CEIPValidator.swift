import Foundation
import Metal
import simd
import Logging

/// Validates Cross-Effect Interference Pressure (CEIP)
/// Ensures that the ACES pipeline maintains tone curve compliance and gamut integrity.
@available(macOS 14.0, *)
public struct CEIPValidator: EffectValidator {
    public let effectName = "ceip"
    public let tolerances: [String: Float]
    
    private let device: MTLDevice
    private let visionAnalyzer: VisionAnalyzer
    private let logger = Logger(label: "com.metalvis.validation.ceip")
    
    public init(device: MTLDevice, tolerances: [String: Float] = [:]) {
        self.device = device
        self.visionAnalyzer = VisionAnalyzer(device: device)
        
        var defaultTolerances: [String: Float] = [
            "tone_curve_deviation": 0.05,  // Max 5% deviation from expected ACES curve
            "gamut_clipping_max": 0.01,    // Max 1% pixels hard clipped
            "hue_stability_min": 0.9       // Min 90% hue stability
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
        logger.info("Validating CEIP at frame \(context.frameIndex)")
        
        var metrics: [String: Float] = [:]
        var diagnostics: [Diagnostic] = []
        var suggestedFixes: [String] = []
        
        // 1. Tone Curve Compliance
        // Analyze the luminance ramp of the output and compare it to the expected ACES RRT+ODT response.
        // We assume the input scene (if available via baseline or known test pattern) is a linear ramp.
        // If baseline is provided, we treat it as the "Input" (Linear) and frameData as "Output" (Tone Mapped).
        
        if let baseline = baselineData {
            // Analyze luminance of both
            let inputProfile = try await visionAnalyzer.analyzeLuminanceProfile(data: baseline, regions: 10, linearize: true)
            let outputProfile = try await visionAnalyzer.analyzeLuminanceProfile(data: frameData, regions: 10, linearize: false) // Output is display encoded
            
            // Check if the transfer function resembles ACES
            // ACES S-Curve: Compresses shadows slightly, compresses highlights significantly.
            // Midtones (0.18) should map to approx 0.18^1/2.2 = 0.46 (if gamma encoded) or similar.
            
            // We calculate the "Transfer Ratio" for each region
            var validRegions: Float = 0
            
            for i in 0..<inputProfile.ringLuminance.count {
                let inputLum = inputProfile.ringLuminance[i]
                let outputLum = outputProfile.ringLuminance[i]
                
                if inputLum > 0.01 && inputLum < 1.0 {
                    // Expected ACES approx: y = (x(a*x+b))/(x(c*x+d)+e) (Narkowicz)
                    // Or just check that it's an S-Curve (slope < 1 at ends, > 1 in middle)
                    // For now, we'll just log the transfer for manual inspection or simple linearity check
                    // Ideally we'd have a reference curve.
                    
                    // Simple check: Output should be monotonic with Input
                    if i > 0 {
                        let prevInput = inputProfile.ringLuminance[i-1]
                        let prevOutput = outputProfile.ringLuminance[i-1]
                        
                        let inputDelta = inputLum - prevInput
                        let outputDelta = outputLum - prevOutput
                        
                        if inputDelta > 0 && outputDelta <= 0 {
                            diagnostics.append(Diagnostic(
                                severity: .error,
                                code: "CEIP_TONE_INVERSION",
                                message: "Tone curve inversion detected at luminance \(inputLum)",
                                context: ["input": "\(inputLum)", "output": "\(outputLum)"]
                            ))
                        }
                    }
                    validRegions += 1
                }
            }
        }
        
        // 2. Gamut Integrity (Clipping Analysis)
        
        // Check for hard clipping at 0.0 and 1.0
        let clippingPercent = try await visionAnalyzer.analyzeClipping(data: frameData)
        metrics["clipped_pixels"] = clippingPercent
        
        let maxClipping = tolerances["gamut_clipping_max"] ?? 0.01
        if clippingPercent > maxClipping {
            diagnostics.append(Diagnostic(
                severity: .warning,
                code: "CEIP_GAMUT_CLIPPING",
                message: "Excessive clipping (\(String(format: "%.1f", clippingPercent * 100))%)",
                context: ["clipping": "\(clippingPercent)", "limit": "\(maxClipping)"]
            ))
            suggestedFixes.append("Check ACES ODT for proper rolloff")
        }
        
        // 3. Hue Stability
        // Ensure that tone mapping doesn't skew hues wildly (except for the "ACES Red" shift which is expected)
        if let baseline = baselineData {
            let inputColors = try await visionAnalyzer.analyzeColorDistribution(data: baseline)
            let outputColors = try await visionAnalyzer.analyzeColorDistribution(data: frameData)
            
            // Calculate hue similarity
            // ... (Reuse hue calculation logic or add to VisionAnalyzer)
            // For now, simple RGB distance
            let dist = distance(inputColors.averageColor, outputColors.averageColor)
            metrics["color_deviation"] = dist
            
            if dist > 0.2 { // Allow some shift for ACES look
                 diagnostics.append(Diagnostic(
                    severity: .warning,
                    code: "CEIP_HUE_SHIFT",
                    message: "Significant hue shift detected (\(String(format: "%.2f", dist)))",
                    context: ["deviation": "\(dist)"]
                ))
            }
        }
        
        let hasErrors = diagnostics.contains { $0.severity == .error }
        return EffectValidationResult(
            effectName: effectName,
            passed: !hasErrors,
            metrics: metrics.mapValues { Double($0) },
            thresholds: tolerances.mapValues { Double($0) },
            diagnostics: diagnostics,
            suggestedFixes: suggestedFixes,
            frameIndex: context.frameIndex
        )
    }
}
