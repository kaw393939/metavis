import Foundation
import Metal
import simd
import Logging
import Yams

/// Validates halation effect - the red/orange glow around bright areas caused by film emulsion
@available(macOS 14.0, *)
public struct HalationValidator: EffectValidator {
    public let effectName = "halation"
    public let tolerances: [String: Float]
    
    private let device: MTLDevice
    private let visionAnalyzer: VisionAnalyzer
    private let logger = Logger(label: "com.metalvis.validation.halation")
    
    // Expected halation tint (warm red/orange from film backing)
    private let expectedTint = SIMD3<Float>(1.0, 0.4, 0.2) // Reddish-orange
    
    // MARK: - Math Config Structures
    private struct MathConfig: Decodable {
        let scenarios: [String: Scenario]
    }
    
    private struct Scenario: Decodable {
        let description: String?
        let parameters: [String: Double]
        let expectations: [String: Double]
    }
    
    public init(device: MTLDevice, tolerances: [String: Float] = [:]) {
        self.device = device
        self.visionAnalyzer = VisionAnalyzer(device: device)
        
        var defaultTolerances: [String: Float] = [
            "tint_tolerance": 0.2,          // Color should be within 20% of expected
            "energy_delta_max": 0.15,       // Max 15% energy increase (halation adds light)
            "red_channel_boost_min": 0.05,  // Red should increase more than other channels
            "ssim_min": 0.80                // Should maintain 80% structural similarity
        ]
        
        for (key, value) in tolerances {
            defaultTolerances[key] = value
        }
        self.tolerances = defaultTolerances
    }
    
    // MARK: - Config Loading
    
    private func loadMathConfig() -> MathConfig? {
        let path = "assets/config/validation_math/optical_effects_math.yaml"
        let fullPath = FileManager.default.currentDirectoryPath + "/" + path
        
        guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else {
            let absPath = "/Users/kwilliams/Projects/metavis_studio/" + path
            guard let absContent = try? String(contentsOfFile: absPath, encoding: .utf8) else {
                logger.warning("Failed to load math config from \(path)")
                return nil
            }
            let decoder = YAMLDecoder()
            return try? decoder.decode(MathConfig.self, from: absContent)
        }
        
        let decoder = YAMLDecoder()
        return try? decoder.decode(MathConfig.self, from: content)
    }
    
    private func findMatchingScenario(config: MathConfig, intensity: Float, radius: Float) -> Scenario? {
        for (_, scenario) in config.scenarios {
            let p = scenario.parameters
            
            // Check mandatory params
            if let r = p["radius"], abs(Float(r) - radius) > 0.1 { continue }
            if let i = p["intensity"], abs(Float(i) - intensity) > 0.1 { continue }
            
            return scenario
        }
        return nil
    }
    
    public func validate(
        frameData: Data,
        baselineData: Data?,
        parameters: EffectParameters,
        context: ValidationContext
    ) async throws -> EffectValidationResult {
        logger.info("Validating halation at frame \(context.frameIndex)")
        
        var metrics: [String: Float] = [:]
        var diagnostics: [Diagnostic] = []
        var suggestedFixes: [String] = []
        
        // Load expectations from config
        var currentTolerances = self.tolerances
        if let config = loadMathConfig(),
           let scenario = findMatchingScenario(config: config, intensity: parameters.intensity ?? 0.5, radius: parameters.radius ?? 20.0) {
            
            if let energyTol = scenario.expectations["energy_preservation_tolerance"] {
                currentTolerances["energy_delta_max"] = Float(energyTol)
            }
            if let rSquared = scenario.expectations["falloff_r_squared_min"] {
                currentTolerances["falloff_r_squared_min"] = Float(rSquared)
            }
            logger.info("Using math expectations from scenario: \(scenario.description ?? "unknown")")
        }
        
        // 1. Color Analysis - Halation should add warm tint
        let colorDist = try await visionAnalyzer.analyzeColorDistribution(data: frameData)
        metrics["avg_r"] = colorDist.averageColor.x
        metrics["avg_g"] = colorDist.averageColor.y
        metrics["avg_b"] = colorDist.averageColor.z
        
        if let baseline = baselineData {
            let baselineColors = try await visionAnalyzer.analyzeColorDistribution(data: baseline)
            
            // Calculate channel-specific changes
            let deltaR = colorDist.averageColor.x - baselineColors.averageColor.x
            let deltaG = colorDist.averageColor.y - baselineColors.averageColor.y
            let deltaB = colorDist.averageColor.z - baselineColors.averageColor.z
            
            metrics["delta_r"] = deltaR
            metrics["delta_g"] = deltaG
            metrics["delta_b"] = deltaB
            
            // Emit warm_ratio as R/B ratio to match YAML threshold key
            // warm_ratio > 1.0 means red exceeds blue (warm tint present)
            let warmRatio = colorDist.averageColor.x / max(colorDist.averageColor.z, 0.001)
            metrics["warm_ratio"] = warmRatio
            
            // 2. Verify halation adds warmth (red > green > blue increase)
            let redBoostMin = currentTolerances["red_channel_boost_min"] ?? 0.05
            let intensity = parameters.intensity ?? 0.5
            
            if intensity > 0.3 {
                // Red should increase most
                if deltaR <= deltaG || deltaR <= deltaB {
                    diagnostics.append(Diagnostic(
                        severity: .error,
                        code: "HALATION_WRONG_TINT",
                        message: "Halation should increase red channel more than green/blue. Got ΔR=\(String(format: "%.3f", deltaR)), ΔG=\(String(format: "%.3f", deltaG)), ΔB=\(String(format: "%.3f", deltaB))",
                        context: [
                            "delta_r": "\(deltaR)",
                            "delta_g": "\(deltaG)", 
                            "delta_b": "\(deltaB)",
                            "intensity": "\(intensity)"
                        ]
                    ))
                    suggestedFixes.append("Check fx_halation_composite tint color - should be warm (R > G > B)")
                    suggestedFixes.append("Verify halation blur is applied to correct color channels")
                }
                
                // Red should have meaningful increase
                if deltaR < redBoostMin {
                    diagnostics.append(Diagnostic(
                        severity: .warning,
                        code: "HALATION_WEAK_WARMTH",
                        message: "Halation red boost is weak (\(String(format: "%.3f", deltaR)), expected > \(redBoostMin))",
                        context: [
                            "delta_r": "\(deltaR)",
                            "intensity": "\(intensity)"
                        ]
                    ))
                }
            }
            
            // 3. Energy Conservation (halation adds light, should be controlled)
            let baselineEnergy = try await visionAnalyzer.calculateEnergy(data: baseline)
            let halationEnergy = try await visionAnalyzer.calculateEnergy(data: frameData)
            
            let energyDelta = (halationEnergy - baselineEnergy) / baselineEnergy
            metrics["energy_delta"] = energyDelta
            
            let maxDelta = currentTolerances["energy_delta_max"] ?? 0.08
            if energyDelta > maxDelta {
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    code: "HALATION_EXCESSIVE_GLOW",
                    message: "Halation added \(String(format: "%.1f", energyDelta * 100))% energy (max: \(String(format: "%.1f", maxDelta * 100))%)",
                    context: [
                        "energy_delta": "\(energyDelta)",
                        "intensity": "\(intensity)"
                    ]
                ))
            }
            
            // 4. Structural Similarity
            let ssim = try await visionAnalyzer.calculateSSIM(originalData: baseline, modifiedData: frameData)
            // Emit as ssim_minimum to match YAML threshold key
            metrics["ssim_minimum"] = ssim.overall
            
            let minSSIM = currentTolerances["ssim_min"] ?? 0.80
            if ssim.overall < minSSIM {
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    code: "HALATION_EXCESSIVE_BLUR",
                    message: "Halation caused excessive structural change (SSIM: \(String(format: "%.3f", ssim.overall)))",
                    context: [
                        "ssim": "\(ssim.overall)",
                        "intensity": "\(intensity)"
                    ]
                ))
            }
        }
        
        // 5. Saliency Check - Halation should enhance bright area visibility
        let saliency = try await visionAnalyzer.analyzeSaliency(data: frameData)
        metrics["saliency_confidence"] = saliency.averageConfidence
        metrics["saliency_area"] = saliency.totalSalientArea
        
        // 6. Radial Falloff Analysis
        // Halation should have smooth exponential falloff from bright areas
        // Use more regions (50) to get better resolution for R² fit
        let luminanceProfile = try await visionAnalyzer.analyzeLuminanceProfile(data: frameData, regions: 50)
        let falloffRSquared = calculateExponentialFalloffFit(luminanceProfile.ringLuminance)
        metrics["falloff_r_squared"] = falloffRSquared
        
        let minRSquared = currentTolerances["falloff_r_squared_min"] ?? 0.9
        if falloffRSquared < minRSquared {
            diagnostics.append(Diagnostic(
                severity: .warning,
                code: "HALATION_ROUGH_FALLOFF",
                message: "Halation falloff is not smooth (R²=\(String(format: "%.3f", falloffRSquared)), expected > \(minRSquared))",
                context: [
                    "falloff_r_squared": "\(falloffRSquared)"
                ]
            ))
            suggestedFixes.append("Check halation blur kernel for smooth exponential decay")
        }
        
        // Determine pass/fail
        let hasErrors = diagnostics.contains { $0.severity == .error }
        let passed = !hasErrors
        
        return EffectValidationResult(
            effectName: effectName,
            passed: passed,
            metrics: metrics.mapValues { Double($0) },
            thresholds: currentTolerances.mapValues { Double($0) },
            diagnostics: diagnostics,
            suggestedFixes: suggestedFixes,
            frameIndex: context.frameIndex
        )
    }
    
    /// Calculate R² fit for exponential falloff: L(r) = L0 * exp(-r/σ)
    /// Returns 1.0 for perfect exponential decay, lower for irregular falloff
    private func calculateExponentialFalloffFit(_ ringLuminance: [Float]) -> Float {
        // Skip the first few rings to avoid the source object itself
        // We only want to measure the "glow" falloff, not the source shape
        let skipRings = 3
        guard ringLuminance.count > skipRings + 3 else { return 1.0 }
        
        let validRings = Array(ringLuminance.dropFirst(skipRings))
        
        // Take log of luminance values to linearize exponential decay
        // log(L) = log(L0) - r/σ  (linear in r)
        var logLuminance: [Float] = []
        var indices: [Float] = []
        
        for (i, lum) in validRings.enumerated() {
            if lum > 0.001 {
                logLuminance.append(log(lum))
                indices.append(Float(i + skipRings))
            }
        }
        
        guard logLuminance.count >= 3 else { return 1.0 }
        
        // Linear regression on log values: y = mx + b
        let n = Float(logLuminance.count)
        var sumX: Float = 0
        var sumY: Float = 0
        var sumXY: Float = 0
        var sumX2: Float = 0
        
        for i in 0..<logLuminance.count {
            let x = indices[i]
            let logL = logLuminance[i]
            sumX += x
            sumY += logL
            sumXY += x * logL
            sumX2 += x * x
        }
        
        let denominator = n * sumX2 - sumX * sumX
        guard abs(denominator) > 0.0001 else { return 1.0 }
        
        let m = (n * sumXY - sumX * sumY) / denominator
        let b = (sumY - m * sumX) / n
        
        // Calculate R² = 1 - SS_res / SS_tot
        var ssRes: Float = 0
        var ssTot: Float = 0
        let yMean = sumY / n
        
        for i in 0..<logLuminance.count {
            let x = indices[i]
            let logL = logLuminance[i]
            let predicted = m * x + b
            ssRes += (logL - predicted) * (logL - predicted)
            ssTot += (logL - yMean) * (logL - yMean)
        }
        
        guard ssTot > 0.0001 else { return 1.0 }
        
        let rSquared = 1.0 - (ssRes / ssTot)
        
        if rSquared < 0.8 {
            logger.info("Poor falloff fit (R²=\(rSquared)). Log-Luminance profile: \(logLuminance)")
        }
        
        return max(0, min(1, rSquared))
    }
}


