import Foundation
import Metal
import simd
import Logging

/// Validates shimmer effect - high frequency luminance oscillation
@available(macOS 14.0, *)
public struct ShimmerValidator: EffectValidator {
    public let effectName = "shimmer"
    public let tolerances: [String: Float]
    
    private let device: MTLDevice
    private let visionAnalyzer: VisionAnalyzer
    private let logger = Logger(label: "com.metalvis.validation.shimmer")
    
    public init(device: MTLDevice, tolerances: [String: Float] = [:]) {
        self.device = device
        self.visionAnalyzer = VisionAnalyzer(device: device)
        
        var defaultTolerances: [String: Float] = [
            "luminance_variance_min": 0.05, // Minimum variance to be considered "shimmering"
            "frequency_match_tolerance": 0.2 // 20% tolerance on frequency
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
        logger.info("Validating shimmer at frame \(context.frameIndex)")
        
        var metrics: [String: Float] = [:]
        var diagnostics: [Diagnostic] = []
        var suggestedFixes: [String] = []
        
        // Shimmer is primarily a temporal effect, but we can check for spatial noise patterns
        // that are characteristic of shimmer in a single frame.
        
        // 1. High Frequency Noise Analysis (Spatial Variance)
        // Shimmer adds high frequency noise to highlights
        let edges = try await visionAnalyzer.analyzeEdges(data: frameData)
        metrics["edge_density"] = edges.edgeDensity
        
        if let baseline = baselineData {
            let baselineEdges = try await visionAnalyzer.analyzeEdges(data: baseline)
            let edgeIncrease = edges.edgeDensity - baselineEdges.edgeDensity
            metrics["spatial_variance"] = edgeIncrease // Map to config key
            
            // Shimmer should increase "perceived" edges due to micro-contrast
            if edgeIncrease < 0.0001 && (parameters.intensity ?? 0) > 0.5 {
                 diagnostics.append(Diagnostic(
                    severity: .warning,
                    code: "SHIMMER_WEAK",
                    message: "Shimmer effect not detecting significant micro-contrast increase",
                    context: [
                        "edge_increase": "\(edgeIncrease)",
                        "intensity": "\(parameters.intensity ?? 0)"
                    ]
                ))
            }
            
            // 2. Luminance Preservation
            let baselineEnergy = try await visionAnalyzer.calculateEnergy(data: baseline)
            let testEnergy = try await visionAnalyzer.calculateEnergy(data: frameData)
            
            if baselineEnergy > 0 {
                let ratio = testEnergy / baselineEnergy
                metrics["luminance_preservation"] = ratio
            } else {
                metrics["luminance_preservation"] = 1.0 // Avoid div by zero
            }
            
            // 3. Hotspot Stability (Preservation)
            let baselineSaliency = try await visionAnalyzer.analyzeSaliency(data: baseline)
            let testSaliency = try await visionAnalyzer.analyzeSaliency(data: frameData)
            
            if let baseSpot = baselineSaliency.hotspots.first,
               let testSpot = testSaliency.hotspots.first {
                
                let dx = baseSpot.center.x - testSpot.center.x
                let dy = baseSpot.center.y - testSpot.center.y
                let distance = sqrt(dx*dx + dy*dy)
                
                // Stability score: 1.0 = perfect match, 0.0 = far away
                // We use a soft falloff
                let stability = max(0, 1.0 - distance * 5.0) 
                metrics["hotspot_stability"] = Float(stability)
            } else {
                // If no hotspots found in either, assume stable (dark image)
                // If found in one but not other, unstable
                if baselineSaliency.hotspots.isEmpty && testSaliency.hotspots.isEmpty {
                    metrics["hotspot_stability"] = 1.0
                } else {
                    metrics["hotspot_stability"] = 0.0
                }
            }
        }
        
        // 4. Parameter Consistency
        if let speed = parameters.additionalParams["speed"] {
            metrics["configured_speed"] = Float(speed)
        }
        
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
