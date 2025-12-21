import Foundation
import Metal
import simd
import Logging

/// Validates Lens System (Distortion + Chromatic Aberration)
/// Checks for physical correctness of optical effects.
@available(macOS 14.0, *)
public struct LensSystemValidator: EffectValidator {
    public let effectName = "lens"
    public let tolerances: [String: Float]
    
    private let device: MTLDevice
    private let visionAnalyzer: VisionAnalyzer
    private let logger = Logger(label: "com.metalvis.validation.lens")
    
    public init(device: MTLDevice, tolerances: [String: Float] = [:]) {
        self.device = device
        self.visionAnalyzer = VisionAnalyzer(device: device)
        
        var defaultTolerances: [String: Float] = [
            "fringing_min": 2.0,           // Min 2 pixels fringing at edges (if CA enabled)
            "distortion_symmetry": 0.05    // Max 5% asymmetry
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
        logger.info("Validating Lens System at frame \(context.frameIndex)")
        
        var metrics: [String: Float] = [:]
        var diagnostics: [Diagnostic] = []
        var suggestedFixes: [String] = []
        
        // 1. Chromatic Aberration (Fringing) Analysis
        // If CA is enabled, we expect color channels to separate at the edges.
        // We can detect this by measuring the "width" of edges in R, G, B channels separately?
        // Or simpler: Compare the centroid of R, G, B channels in quadrants.
        
        // Analyze color distribution in outer regions
        // We'll define a region at the top-left corner
        let cornerRegion = CGRect(x: 0.05, y: 0.05, width: 0.1, height: 0.1)
        let cornerColor = try await visionAnalyzer.analyzeRegionColor(data: frameData, region: cornerRegion)
        
        // If we have a high contrast edge (white on black), CA will make the edge colorful.
        // R, G, B values will differ.
        let channelVariance = variance([cornerColor.x, cornerColor.y, cornerColor.z])
        metrics["corner_channel_variance"] = channelVariance
        
        // If CA intensity > 0, we expect variance > 0
        if let caIntensity = parameters.additionalParams["ca_intensity"], caIntensity > 0.0 {
            let minVariance: Float = 0.001
            if channelVariance < minVariance {
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    code: "LENS_NO_FRINGING",
                    message: "Chromatic Aberration enabled but no fringing detected",
                    context: ["variance": "\(channelVariance)", "intensity": "\(caIntensity)"]
                ))
                suggestedFixes.append("Verify fx_lens_system applies channel offset based on radius")
            }
        }
        
        // 2. Distortion Analysis
        // Check if the image center is preserved (Distortion should be radial around center)
        // We can check the center pixel vs baseline
        if let baseline = baselineData {
            let centerRegion = CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1)
            let baseCenter = try await visionAnalyzer.analyzeRegionColor(data: baseline, region: centerRegion)
            let frameCenter = try await visionAnalyzer.analyzeRegionColor(data: frameData, region: centerRegion)
            
            let centerShift = distance(baseCenter, frameCenter)
            metrics["center_shift"] = centerShift
            
            if centerShift > 0.05 {
                diagnostics.append(Diagnostic(
                    severity: .error,
                    code: "LENS_CENTER_SHIFT",
                    message: "Lens distortion shifted the optical center",
                    context: ["shift": "\(centerShift)"]
                ))
                suggestedFixes.append("Ensure distortion formula uses (uv - 0.5)")
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
    
    private func variance(_ values: [Float]) -> Float {
        let mean = values.reduce(0, +) / Float(values.count)
        let sumSqDiff = values.map { pow($0 - mean, 2) }.reduce(0, +)
        return sumSqDiff / Float(values.count)
    }
}
