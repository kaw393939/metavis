import Foundation
import Metal
import Logging

/// Validates occlusion and depth separation
@available(macOS 14.0, *)
public struct OcclusionValidator: EffectValidator {
    public let effectName = "occlusion"
    
    private let device: MTLDevice
    private let visionAnalyzer: VisionAnalyzer
    private let logger = Logger(label: "com.metalvis.validation.occlusion")
    
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
        logger.info("Validating occlusion at frame \(context.frameIndex)")
        
        var metrics: [String: Double] = [:]
        var diagnostics: [Diagnostic] = []
        var suggestedFixes: [String] = []
        
        // 1. Depth Separation Analysis
        let depthResult = try await visionAnalyzer.analyzeDepthSeparation(data: frameData)
        
        metrics["foreground_percentage"] = Double(depthResult.foregroundPercentage)
        metrics["background_percentage"] = Double(depthResult.backgroundPercentage)
        metrics["separation_confidence"] = Double(depthResult.separationConfidence)
        metrics["layer_count"] = Double(depthResult.layerCount)
        
        // Check if we have clear separation (confidence > 0.5)
        if depthResult.separationConfidence < 0.5 {
            diagnostics.append(Diagnostic(
                severity: .warning,
                code: "POOR_DEPTH_SEPARATION",
                message: "Could not clearly separate foreground from background (confidence: \(String(format: "%.2f", depthResult.separationConfidence)))",
                context: ["confidence": "\(depthResult.separationConfidence)"]
            ))
            suggestedFixes.append("Increase contrast between foreground and background or adjust depth of field")
        }
        
        // 2. Occlusion Integrity (Placeholder)
        // In a real implementation, we would project 3D bounds and check if pixels match expected visibility
        // For now, we assume if we have > 1 layer, occlusion is happening
        let hasOcclusion = depthResult.layerCount > 1
        metrics["occlusion_detected"] = hasOcclusion ? 1.0 : 0.0
        
        if !hasOcclusion {
             diagnostics.append(Diagnostic(
                severity: .info,
                code: "NO_OCCLUSION",
                message: "No occlusion detected (single layer)",
                context: ["layer_count": "\(depthResult.layerCount)"]
            ))
        }
        
        // Determine pass/fail
        // For occlusion validation, we generally expect to see separation if that was the intent
        // But without specific intent parameters, we can't fail strictly.
        // We'll fail if confidence is extremely low (< 0.1) implying a noisy mess
        
        let passed = depthResult.separationConfidence > 0.1
        
        return EffectValidationResult(
            effectName: effectName,
            passed: passed,
            metrics: metrics,
            thresholds: ["separation_confidence": 0.1],
            diagnostics: diagnostics,
            suggestedFixes: suggestedFixes,
            frameIndex: context.frameIndex
        )
    }
}
