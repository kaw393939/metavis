import Foundation
import Metal
import simd
import Logging
import Yams

/// Validates Bokeh / Defocus Blur
/// Checks for circularity of the impulse response (Bokeh Shape)
@available(macOS 14.0, *)
public struct BokehValidator: EffectValidator {
    public let effectName = "bokeh"
    public let tolerances: [String: Float]
    
    private let device: MTLDevice
    private let visionAnalyzer: VisionAnalyzer
    private let logger = Logger(label: "com.metalvis.validation.bokeh")
    
    public init(device: MTLDevice, tolerances: [String: Float] = [:]) {
        self.device = device
        self.visionAnalyzer = VisionAnalyzer(device: device)
        
        var defaultTolerances: [String: Float] = [
            "circularity_min": 0.90,       // Bokeh should be circular (> 0.9)
            "energy_preservation": 0.95,   // Blur should preserve energy
            "radius_accuracy": 0.10        // Measured radius vs expected
        ]
        
        // Load from YAML
        if let yamlContent = try? String(contentsOfFile: "assets/config/validation_math/optical_effects_math.yaml", encoding: .utf8),
           let yaml = try? Yams.load(yaml: yamlContent) as? [String: Any],
           let scenarios = yaml["scenarios"] as? [String: Any],
           let scenario = scenarios["bokeh_quality"] as? [String: Any],
           let expectations = scenario["expectations"] as? [String: Double] {
            for (key, value) in expectations {
                defaultTolerances[key] = Float(value)
            }
        }
        
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
        logger.info("Validating bokeh at frame \(context.frameIndex)")
        
        var metrics: [String: Float] = [:]
        var diagnostics: [Diagnostic] = []
        var suggestedFixes: [String] = []
        
        // 1. Saliency / Hotspot Analysis
        // We assume the test frame contains bright spots (impulses) to measure bokeh shape
        let saliency = try await visionAnalyzer.analyzeSaliency(data: frameData)
        
        if let hotspot = saliency.hotspots.first {
            // 2. Circularity Analysis
            // Measure how circular the brightest spot is
            let circularity = try await visionAnalyzer.analyzeHotspotCircularity(data: frameData, center: hotspot.center, radius: 100)
            metrics["circularity"] = circularity
            
            let minCircularity = tolerances["circularity_min"] ?? 0.90
            if circularity < minCircularity {
                diagnostics.append(Diagnostic(
                    severity: .error,
                    code: "BOKEH_SHAPE_INVALID",
                    message: "Bokeh shape is not circular (Circularity: \(String(format: "%.2f", circularity)), min: \(minCircularity)). Likely using separable blur instead of disk blur.",
                    context: [
                        "circularity": "\(circularity)",
                        "hotspot": "\(hotspot.center)"
                    ]
                ))
                suggestedFixes.append("Ensure BokehPass uses 'fx_bokeh_blur' (Golden Angle Disk) instead of 'fx_blur_h/v'")
            }
            
            // 3. Radius Measurement (Approximate)
            // Estimate radius from salient area
            let estimatedRadius = sqrt(hotspot.area / Float.pi)
            metrics["measured_radius"] = estimatedRadius
        } else {
            diagnostics.append(Diagnostic(
                severity: .warning,
                code: "BOKEH_NO_HOTSPOTS",
                message: "No hotspots found to validate bokeh shape",
                context: [:]
            ))
        }
        
        // 4. Energy Preservation
        if let baseline = baselineData {
            let baselineEnergy = try await visionAnalyzer.calculateEnergy(data: baseline)
            let blurredEnergy = try await visionAnalyzer.calculateEnergy(data: frameData)
            
            let preservation = blurredEnergy / max(baselineEnergy, 0.001)
            metrics["energy_preservation"] = preservation
            
            let minPreservation = tolerances["energy_preservation"] ?? 0.95
            if preservation < minPreservation {
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    code: "BOKEH_ENERGY_LOSS",
                    message: "Bokeh blur lost energy (preserved: \(String(format: "%.1f", preservation * 100))%)",
                    context: [
                        "preservation": "\(preservation)"
                    ]
                ))
            }
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
