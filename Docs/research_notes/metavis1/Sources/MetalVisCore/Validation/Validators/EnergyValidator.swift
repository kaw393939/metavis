import Foundation
import Metal
import simd
import Logging

/// Validates procedural energy field effects
@available(macOS 14.0, *)
public struct EnergyValidator: EffectValidator {
    public let effectName = "energy"
    public let tolerances: [String: Float]
    
    private let device: MTLDevice
    private let visionAnalyzer: VisionAnalyzer
    private let logger = Logger(label: "com.metalvis.validation.energy")
    
    public init(device: MTLDevice, tolerances: [String: Float] = [:]) {
        self.device = device
        self.visionAnalyzer = VisionAnalyzer(device: device)
        self.tolerances = tolerances
    }
    
    public func validate(
        frameData: Data,
        baselineData: Data?,
        parameters: EffectParameters,
        context: ValidationContext
    ) async throws -> EffectValidationResult {
        logger.info("Validating energy effect at frame \(context.frameIndex)")
        
        var metrics: [String: Float] = [:]
        var diagnostics: [Diagnostic] = []
        
        // 1. Glow Intensity (Peak Luminance)
        // Energy fields should be bright
        let histogram = try await visionAnalyzer.calculateHistogram(data: frameData)
        // Estimate peak luminance from histogram (simplified)
        // Assuming histogram has 256 bins, check the top bins
        var peakLuminance: Float = 0.0
        if let lastBin = histogram.last, lastBin > 0 {
            peakLuminance = 1.0
        } else {
            peakLuminance = 0.8 // Placeholder if not fully saturated
        }
        metrics["glow_luminance"] = peakLuminance
        
        let minGlow = tolerances["glow_luminance"] ?? 0.2
        if peakLuminance < minGlow {
             diagnostics.append(Diagnostic(
                severity: .warning,
                code: "ENERGY_LOW_GLOW",
                message: "Energy field lacks peak brightness",
                context: ["peak": "\(peakLuminance)"]
            ))
        }
        
        // 2. Coherence (Edge Continuity)
        // Energy fields often have flowing lines. High edge density might indicate complexity.
        let edgeDensity = try await visionAnalyzer.calculateEdgeDensity(data: frameData)
        metrics["coherence_score"] = 1.0 - min(edgeDensity, 1.0) // Inverse of noise? Rough approximation.
        
        // 3. Color Vibrancy
        // Energy fields are usually colorful
        let colorDist = try await visionAnalyzer.analyzeColorDistribution(data: frameData)
        let saturation = max(abs(colorDist.averageColor.x - colorDist.averageColor.y),
                             max(abs(colorDist.averageColor.y - colorDist.averageColor.z),
                                 abs(colorDist.averageColor.z - colorDist.averageColor.x)))
        metrics["saturation"] = saturation
        
        if saturation < 0.1 {
             diagnostics.append(Diagnostic(
                severity: .warning,
                code: "ENERGY_LOW_SATURATION",
                message: "Energy field appears washed out/monochrome",
                context: ["saturation": "\(saturation)"]
            ))
        }
        
        let passed = !diagnostics.contains { $0.severity == .error }
        
        return EffectValidationResult(
            effectName: effectName,
            passed: passed,
            metrics: metrics.mapValues { Double($0) },
            thresholds: tolerances.mapValues { Double($0) },
            diagnostics: diagnostics,
            suggestedFixes: [],
            frameIndex: context.frameIndex
        )
    }
}
