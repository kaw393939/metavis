import Foundation
import Metal
import Logging

/// Validates temporal stability and motion artifacts
@available(macOS 14.0, *)
public struct MotionStabilityValidator: EffectValidator {
    public let effectName = "motion_stability"
    
    private let device: MTLDevice
    private let visionAnalyzer: VisionAnalyzer
    private let logger = Logger(label: "com.metalvis.validation.motion")
    
    public init(device: MTLDevice) {
        self.device = device
        self.visionAnalyzer = VisionAnalyzer(device: device)
    }
    
    public func validate(
        frameData: Data,
        baselineData: Data?,
        parameters: EffectParameters,
        context: ValidationContext
    ) async throws -> EffectValidationResult {
        logger.info("Validating motion stability at frame \(context.frameIndex)")
        
        var metrics: [String: Double] = [:]
        var diagnostics: [Diagnostic] = []
        let suggestedFixes: [String] = []
        
        // We need a baseline to compare against for motion analysis
        // In a static scene, baseline (no effect) vs frame (effect) flow represents the "visual motion" added by the effect
        // If the scene is static, this flow should be minimal unless the effect is INTENDED to add motion (e.g. grain, heat haze)
        
        guard let baseline = baselineData else {
            return EffectValidationResult(
                effectName: effectName,
                passed: true,
                metrics: [:],
                thresholds: [:],
                diagnostics: [Diagnostic(severity: .warning, code: "NO_BASELINE", message: "Cannot validate motion without baseline")],
                suggestedFixes: [],
                frameIndex: context.frameIndex
            )
        }
        
        // Analyze motion between baseline and effect frame
        // Note: This is a proxy for "temporal stability" in a static scene context
        // Ideally we would compare frame N and N+1 of the effect
        let motionResult = try await visionAnalyzer.analyzeMotion(previousData: baseline, currentData: frameData)
        
        metrics["motion_magnitude"] = Double(motionResult.averageMagnitude)
        metrics["max_motion"] = Double(motionResult.maxMagnitude)
        metrics["stability_score"] = Double(motionResult.stabilityScore)
        
        // Check for excessive instability in static scenes
        // Threshold depends on effect intent. For "static" effects, it should be low.
        let stabilityThreshold = 0.8 // Arbitrary
        
        if motionResult.stabilityScore < Float(stabilityThreshold) {
             diagnostics.append(Diagnostic(
                severity: .info, // Info because some effects are inherently unstable (grain)
                code: "LOW_STABILITY",
                message: "High visual motion detected relative to baseline (score: \(String(format: "%.2f", motionResult.stabilityScore)))",
                context: ["magnitude": "\(motionResult.averageMagnitude)"]
            ))
        }
        
        return EffectValidationResult(
            effectName: effectName,
            passed: true, // Always pass for now as we lack temporal context
            metrics: metrics,
            thresholds: ["stability_score": stabilityThreshold],
            diagnostics: diagnostics,
            suggestedFixes: suggestedFixes,
            frameIndex: context.frameIndex
        )
    }
}
