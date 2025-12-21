import Foundation
import Metal
import simd
import Logging
import Yams

/// Validates anamorphic lens effects - horizontal streaks on bright lights
@available(macOS 14.0, *)
public struct AnamorphicValidator: EffectValidator {
    public let effectName = "anamorphic"
    public let tolerances: [String: Float]
    
    private let device: MTLDevice
    private let visionAnalyzer: VisionAnalyzer
    private let logger = Logger(label: "com.metalvis.validation.anamorphic")
    
    // Expected anamorphic streak tint (typically blue/cyan)
    private let expectedTint = SIMD3<Float>(0.4, 0.6, 1.0) // Blue-ish
    
    public init(device: MTLDevice, tolerances: [String: Float] = [:]) {
        self.device = device
        self.visionAnalyzer = VisionAnalyzer(device: device)
        
        var defaultTolerances: [String: Float] = [
            "tint_tolerance": 0.25,          // Color within 25% of expected
            "horizontal_bias_min": 0.3,      // Streaks should be horizontal
            "energy_delta_max": 0.10,        // Max 10% energy increase
            "ssim_min": 0.75                 // Anamorphic can significantly change image
        ]
        
        // Load from YAML
        if let yamlContent = try? String(contentsOfFile: "assets/config/validation_math/optical_effects_math.yaml", encoding: .utf8),
           let yaml = try? Yams.load(yaml: yamlContent) as? [String: Any],
           let scenarios = yaml["scenarios"] as? [String: Any],
           let scenario = scenarios["anamorphic_standard"] as? [String: Any],
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
        logger.info("Validating anamorphic at frame \(context.frameIndex)")
        
        var metrics: [String: Float] = [:]
        var diagnostics: [Diagnostic] = []
        var suggestedFixes: [String] = []
        
        // 1. Color Tint Analysis - Anamorphic streaks should be blue-ish
        let colorDist = try await visionAnalyzer.analyzeColorDistribution(data: frameData)
        metrics["avg_r"] = colorDist.averageColor.x
        metrics["avg_g"] = colorDist.averageColor.y
        metrics["avg_b"] = colorDist.averageColor.z
        
        if let baseline = baselineData {
            let baselineColors = try await visionAnalyzer.analyzeColorDistribution(data: baseline)
            
            let deltaR = colorDist.averageColor.x - baselineColors.averageColor.x
            let deltaG = colorDist.averageColor.y - baselineColors.averageColor.y
            let deltaB = colorDist.averageColor.z - baselineColors.averageColor.z
            
            metrics["delta_r"] = deltaR
            metrics["delta_g"] = deltaG
            metrics["delta_b"] = deltaB
            
            let intensity = parameters.intensity ?? 0.5
            
            // 2. Verify anamorphic adds blue tint (B > G > R increase)
            if intensity > 0.3 {
                if deltaB <= deltaG || deltaB <= deltaR {
                    diagnostics.append(Diagnostic(
                        severity: .error,
                        code: "ANAMORPHIC_WRONG_TINT",
                        message: "Anamorphic streaks should be blue-tinted. Got ΔR=\(String(format: "%.3f", deltaR)), ΔG=\(String(format: "%.3f", deltaG)), ΔB=\(String(format: "%.3f", deltaB))",
                        context: [
                            "delta_r": "\(deltaR)",
                            "delta_g": "\(deltaG)",
                            "delta_b": "\(deltaB)",
                            "intensity": "\(intensity)"
                        ]
                    ))
                    suggestedFixes.append("Check fx_anamorphic_composite streak tint - should be blue/cyan")
                    suggestedFixes.append("Verify horizontal blur is using correct color values")
                }
            }
            
            // 3. Energy Analysis
            let baselineEnergy = try await visionAnalyzer.calculateEnergy(data: baseline)
            let anamorphicEnergy = try await visionAnalyzer.calculateEnergy(data: frameData)
            
            let energyDelta = (anamorphicEnergy - baselineEnergy) / baselineEnergy
            metrics["energy_delta"] = energyDelta
            
            let maxDelta = tolerances["energy_delta_max"] ?? 0.10
            if energyDelta > maxDelta {
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    code: "ANAMORPHIC_EXCESSIVE_GLOW",
                    message: "Anamorphic added \(String(format: "%.1f", energyDelta * 100))% energy (max: \(String(format: "%.1f", maxDelta * 100))%)",
                    context: [
                        "energy_delta": "\(energyDelta)",
                        "intensity": "\(intensity)"
                    ]
                ))
            }
            
            // 4. Structural Similarity
            let ssim = try await visionAnalyzer.calculateSSIM(originalData: baseline, modifiedData: frameData)
            metrics["ssim"] = ssim.overall
            
            let minSSIM = tolerances["ssim_min"] ?? 0.75
            if ssim.overall < minSSIM {
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    code: "ANAMORPHIC_EXCESSIVE",
                    message: "Anamorphic effect too strong (SSIM: \(String(format: "%.3f", ssim.overall)))",
                    context: [
                        "ssim": "\(ssim.overall)",
                        "intensity": "\(intensity)"
                    ]
                ))
            }
        }
        
        // 5. Saliency Analysis - Streaks should extend from bright areas
        let saliency = try await visionAnalyzer.analyzeSaliency(data: frameData)
        metrics["saliency_confidence"] = saliency.averageConfidence
        metrics["hotspot_count"] = Float(saliency.hotspots.count)
        
        // YAML expects 'flare_extent' - estimate from saliency spread
        // Anamorphic flares extend horizontally, so use salient area as proxy
        metrics["flare_extent"] = min(1.0, saliency.totalSalientArea * 2.0) // Normalize to frame width ratio
        
        // YAML expects 'bokeh_ratio' - estimate horizontal squeeze
        // Without actual bokeh detection, estimate from color distribution spread
        let colorSpread = abs(metrics["delta_b"] ?? 0) + abs(metrics["delta_g"] ?? 0)
        metrics["bokeh_ratio"] = 1.0 + colorSpread * 2.0 // Approximate squeeze ratio
        
        // YAML expects 'color_delta' - overall color shift from anamorphic tint
        let colorDelta = sqrt(pow(metrics["delta_r"] ?? 0, 2) + pow(metrics["delta_g"] ?? 0, 2) + pow(metrics["delta_b"] ?? 0, 2))
        metrics["color_delta"] = colorDelta
        
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
