import Foundation
import Metal
import simd
import Logging
import Yams

/// Validates bloom effect using energy conservation and luminance analysis
@available(macOS 14.0, *)
public struct BloomValidator: EffectValidator {
    public let effectName = "bloom"
    public let tolerances: [String: Float]
    
    private let device: MTLDevice
    private let visionAnalyzer: VisionAnalyzer
    private let logger = Logger(label: "com.metalvis.validation.bloom")
    
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
        
        // Default tolerances (can be overridden)
        var defaultTolerances: [String: Float] = [
            "energy_delta_max": 0.20,      // Max 20% energy change (Additive bloom adds light)
            "ssim_min": 0.85,              // At least 85% structural similarity
            "saliency_increase_min": 0.1,  // Bloom should increase saliency on bright areas
            "threshold_accuracy": 0.1      // 10% tolerance on threshold behavior
        ]
        
        // Merge with provided tolerances
        for (key, value) in tolerances {
            defaultTolerances[key] = value
        }
        self.tolerances = defaultTolerances
    }
    
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
    
    public func validate(
        frameData: Data,
        baselineData: Data?,
        parameters: EffectParameters,
        context: ValidationContext
    ) async throws -> EffectValidationResult {
        logger.info("Validating bloom at frame \(context.frameIndex)")
        
        var metrics: [String: Float] = [:]
        var diagnostics: [Diagnostic] = []
        var suggestedFixes: [String] = []
        
        // Load math config
        let mathConfig = loadMathConfig()
        var energyTolerance = tolerances["energy_delta_max"] ?? 0.05
        var currentTolerances = tolerances
        
        if let config = mathConfig,
           let scenario = config.scenarios["bloom_energy"],
           let tol = scenario.expectations["energy_preservation_tolerance"] {
            energyTolerance = Float(tol)
            currentTolerances["energy_delta_max"] = energyTolerance
            logger.info("Using energy tolerance from config: \(energyTolerance)")
        }
        
        // 1. Energy Conservation Test
        // Bloom should not significantly increase or decrease total image energy
        // Use linearize: true to measure physical light energy (photons), not perceptual brightness
        if let baseline = baselineData {
            let baselineEnergy = try await visionAnalyzer.calculateEnergy(data: baseline, linearize: true)
            let bloomedEnergy = try await visionAnalyzer.calculateEnergy(data: frameData, linearize: true)
            
            let energyDelta = (bloomedEnergy - baselineEnergy) / max(baselineEnergy, 0.001)
            metrics["energy_delta"] = energyDelta
            metrics["baseline_energy"] = baselineEnergy
            metrics["bloomed_energy"] = bloomedEnergy
            
            let maxDelta = energyTolerance
            
            if energyDelta > maxDelta {
                diagnostics.append(Diagnostic(
                    severity: .error,
                    code: "BLOOM_ENERGY_GAIN",
                    message: "Bloom increased energy by \(String(format: "%.1f", energyDelta * 100))% (max allowed: \(String(format: "%.1f", maxDelta * 100))%)",
                    context: [
                        "baseline_energy": "\(baselineEnergy)",
                        "bloomed_energy": "\(bloomedEnergy)",
                        "intensity": "\(parameters.intensity ?? 0)"
                    ]
                ))
                suggestedFixes.append("Check fx_bloom_composite in MetaVisFXShaders.metal - ensure bloom is additive not multiplicative")
                suggestedFixes.append("Verify bloom intensity normalization in BloomPass.swift")
            } else if energyDelta < -maxDelta {
                diagnostics.append(Diagnostic(
                    severity: .error,
                    code: "BLOOM_ENERGY_LOSS",
                    message: "Bloom decreased energy by \(String(format: "%.1f", abs(energyDelta) * 100))% (max allowed: \(String(format: "%.1f", maxDelta * 100))%)",
                    context: [
                        "baseline_energy": "\(baselineEnergy)",
                        "bloomed_energy": "\(bloomedEnergy)"
                    ]
                ))
                suggestedFixes.append("Check bloom composite blending mode - should preserve original luminance")
            }
            
            // 2. Structural Similarity Test
            let ssim = try await visionAnalyzer.calculateSSIM(originalData: baseline, modifiedData: frameData)
            // Emit as ssim_minimum to match YAML threshold key
            metrics["ssim_minimum"] = ssim.overall
            metrics["ssim_luminance"] = ssim.luminanceComponent
            metrics["ssim_contrast"] = ssim.contrastComponent
            metrics["ssim_structure"] = ssim.structureComponent
            
            let minSSIM = tolerances["ssim_min"] ?? 0.85
            if ssim.overall < minSSIM {
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    code: "BLOOM_EXCESSIVE_CHANGE",
                    message: "Bloom caused excessive structural changes (SSIM: \(String(format: "%.3f", ssim.overall)), min: \(minSSIM))",
                    context: [
                        "ssim_overall": "\(ssim.overall)",
                        "ssim_luminance": "\(ssim.luminanceComponent)",
                        "intensity": "\(parameters.intensity ?? 0)"
                    ]
                ))
            }
        }
        
        // 3. Saliency Analysis
        // Bloom should increase visual attention on bright areas
        let saliency = try await visionAnalyzer.analyzeSaliency(data: frameData)
        metrics["saliency_confidence"] = saliency.averageConfidence
        metrics["saliency_area"] = saliency.totalSalientArea
        metrics["hotspot_count"] = Float(saliency.hotspots.count)
        
        if let baseline = baselineData {
            let baselineSaliency = try await visionAnalyzer.analyzeSaliency(data: baseline)
            // Emit as saliency_delta to match YAML threshold key (absolute value)
            let saliencyDelta = abs(saliency.averageConfidence - baselineSaliency.averageConfidence)
            metrics["saliency_delta"] = saliencyDelta
            
            // Also track the signed increase for diagnostic purposes
            let saliencyIncrease = saliency.averageConfidence - baselineSaliency.averageConfidence
            
            let minIncrease = tolerances["saliency_increase_min"] ?? 0.1
            if parameters.intensity ?? 0 > 0.3 && saliencyIncrease < minIncrease {
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    code: "BLOOM_LOW_VISUAL_IMPACT",
                    message: "Bloom had minimal visual impact on saliency (Δ: \(String(format: "%.3f", saliencyIncrease)))",
                    context: [
                        "intensity": "\(parameters.intensity ?? 0)",
                        "saliency_before": "\(baselineSaliency.averageConfidence)",
                        "saliency_after": "\(saliency.averageConfidence)"
                    ]
                ))
            }
        }
        
        // 4. Threshold Behavior Test
        // Only pixels above threshold should contribute to bloom
        if let threshold = parameters.threshold {
            metrics["configured_threshold"] = threshold
            // This would require access to the bloom pass output to verify
            // For now, we note the configured value
        }
        
        // 5. Color Distribution Analysis
        let colorDist = try await visionAnalyzer.analyzeColorDistribution(data: frameData)
        metrics["avg_r"] = colorDist.averageColor.x
        metrics["avg_g"] = colorDist.averageColor.y
        metrics["avg_b"] = colorDist.averageColor.z
        
        // Bloom should not shift color balance significantly
        if let baseline = baselineData {
            let baselineColors = try await visionAnalyzer.analyzeColorDistribution(data: baseline)
            let colorShift = simd_length(colorDist.averageColor - baselineColors.averageColor)
            metrics["color_shift"] = colorShift
            
            if colorShift > 0.1 {
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    code: "BLOOM_COLOR_SHIFT",
                    message: "Bloom caused color shift of \(String(format: "%.3f", colorShift))",
                    context: [
                        "baseline_color": "(\(baselineColors.averageColor.x), \(baselineColors.averageColor.y), \(baselineColors.averageColor.z))",
                        "bloomed_color": "(\(colorDist.averageColor.x), \(colorDist.averageColor.y), \(colorDist.averageColor.z))"
                    ]
                ))
            }
        }
        
        // 6. Banding Score Analysis
        // Detect gradient quantization artifacts in bloom regions
        let bandingScore = try await calculateBandingScore(data: frameData, threshold: parameters.threshold ?? 0.8)
        metrics["banding_score"] = bandingScore
        
        let maxBanding: Float = 0.02
        if bandingScore > maxBanding {
            diagnostics.append(Diagnostic(
                severity: .warning,
                code: "BLOOM_BANDING",
                message: "Banding detected in bloom gradients (\(String(format: "%.1f", bandingScore * 100))% affected pixels)",
                context: [
                    "banding_score": "\(bandingScore)",
                    "threshold": "\(maxBanding)"
                ]
            ))
            suggestedFixes.append("Add dithering to bloom blur kernel in MetaVisFXShaders.metal")
            suggestedFixes.append("Ensure intermediate textures use 16-bit or 32-bit float format")
        }
        
        // 7. Shape Circularity Analysis (New for Cinematic Quality)
        // Detects "Square" or "Diamond" artifacts from cheap upsampling filters
        // We analyze the impulse response of the brightest hotspot
        if let hotspot = saliency.hotspots.first {
            let circularity = try await visionAnalyzer.analyzeHotspotCircularity(data: frameData, center: hotspot.center, radius: 50)
            metrics["shape_circularity"] = circularity
            
            let minCircularity: Float = 0.90 // Cinematic standard
            if circularity < minCircularity {
                diagnostics.append(Diagnostic(
                    severity: .error,
                    code: "BLOOM_SHAPE_ARTIFACT",
                    message: "Bloom shape is not circular (Circularity: \(String(format: "%.2f", circularity)), min: \(minCircularity)). Likely 'Square' or 'Diamond' artifact.",
                    context: [
                        "circularity": "\(circularity)",
                        "hotspot": "\(hotspot.center)"
                    ]
                ))
                suggestedFixes.append("Replace Tent Filter upsampling with Cinematic Disk Blur (Golden Angle)")
            }
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
    
    /// Calculates banding score by detecting sudden luminance jumps in gradients
    /// Returns fraction of pixels affected by banding (0.0 = no banding, 1.0 = all banding)
    private func calculateBandingScore(data: Data, threshold: Float) async throws -> Float {
        // Banding detection: look for non-monotonic transitions in the luminance profile
        // Real banding appears as "steps" - quantization artifacts that create visible bands
        let luminanceProfile = try await visionAnalyzer.analyzeLuminanceProfile(data: data, regions: 20)
        
        var bandingCount: Float = 0
        var totalComparisons: Float = 0
        
        let rings = luminanceProfile.ringLuminance
        guard rings.count >= 3 else { return 0 }
        
        // Calculate the expected smooth delta (average of all deltas)
        var totalDelta: Float = 0
        var maxDelta: Float = 0
        for i in 1..<rings.count {
            let delta = abs(rings[i] - rings[i-1])
            totalDelta += delta
            maxDelta = max(maxDelta, delta)
        }
        let _ = totalDelta / Float(rings.count - 1)
        
        // Only flag as banding if we see oscillations (up-down-up pattern)
        // Natural gradients may have direction changes but won't oscillate rapidly
        for i in 3..<rings.count {
            let delta1 = rings[i-2] - rings[i-3]  // Two steps ago
            let delta2 = rings[i-1] - rings[i-2]  // Previous step
            let delta3 = rings[i] - rings[i-1]    // Current step
            
            // Check for oscillation pattern: + - + or - + -
            // This indicates banding/quantization steps
            let isOscillating = (delta1 > 0.005 && delta2 < -0.005 && delta3 > 0.005) ||
                               (delta1 < -0.005 && delta2 > 0.005 && delta3 < -0.005)
            
            if isOscillating {
                bandingCount += 1
            }
            totalComparisons += 1
        }
        
        return totalComparisons > 0 ? bandingCount / totalComparisons : 0
    }
}
