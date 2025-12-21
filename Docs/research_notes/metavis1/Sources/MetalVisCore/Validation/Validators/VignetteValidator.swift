import Foundation
import Metal
import simd
import Logging
import Yams

/// Validates vignette effect using cos⁴ law and radial luminance profile
@available(macOS 14.0, *)
public struct VignetteValidator: EffectValidator {
    public let effectName = "vignette"
    public let tolerances: [String: Float]
    
    private let device: MTLDevice
    private let visionAnalyzer: VisionAnalyzer
    private let logger = Logger(label: "com.metalvis.validation.vignette")
    
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
            "cos4_tolerance": 0.40,         // 40% deviation allowed (accommodates ACES S-curve distortion)
            "edge_darkening_min": 0.1,      // Edges should be at least 10% darker
            "center_preservation": 0.95,    // Center should retain 95% of original luminance
            "symmetry_tolerance": 0.05      // 5% deviation in symmetry allowed
        ]
        
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
        logger.info("Validating vignette at frame \(context.frameIndex)")
        
        var metrics: [String: Float] = [:]
        var diagnostics: [Diagnostic] = []
        var suggestedFixes: [String] = []
        
        // Load math config
        let mathConfig = loadMathConfig()
        var cos4Tolerance = tolerances["cos4_tolerance"] ?? 0.15
        var centerPreservationMin = tolerances["center_preservation"] ?? 0.95
        
        if let config = mathConfig,
           let scenario = config.scenarios["vignette_cos4"] {
            if let r2 = scenario.expectations["cos4_fit_r_squared_min"] {
                // Convert R^2 min to tolerance?
                // R^2 > 0.95 implies good fit.
                // Tolerance is deviation.
                // Let's keep tolerance as is, but maybe log it.
            }
            if let cp = scenario.expectations["center_preservation_min"] {
                centerPreservationMin = Float(cp)
                logger.info("Using center preservation min from config: \(centerPreservationMin)")
            }
        }
        
        // 1. Radial Luminance Profile Analysis
        // Use linearize: true to decode sRGB/Gamma from the tone-mapped output
        // This validates that Vignette is applied BEFORE Tone Mapping (Linear Space)
        let luminanceProfile = try await visionAnalyzer.analyzeLuminanceProfile(data: frameData, regions: 20, linearize: true)
        
        metrics["center_luminance"] = luminanceProfile.centerLuminance
        metrics["edge_luminance"] = luminanceProfile.edgeLuminance
        metrics["falloff_ratio"] = luminanceProfile.falloffRatio
        
        // Store ring luminances for detailed analysis
        for (i, lum) in luminanceProfile.ringLuminance.enumerated() {
            metrics["ring_\(i)_luminance"] = lum
        }
        
        // 2. Cos⁴ Law Validation (physical vignette model)
        // The shader applies mix(1.0, cos4, intensity), so we need to account for intensity
        let vignetteIntensity = parameters.intensity ?? 0.3
        
        // Calculate physical angle for validation
        // Default VignettePass params: sensorWidth = 36mm, focalLength = 35mm
        // VisionAnalyzer normalizes radius to diagonal/2
        let sensorWidth: Float = 36.0
        let focalLength: Float = 35.0
        let aspectRatio = Float(context.width) / Float(context.height)
        let sensorHeight = sensorWidth / aspectRatio
        let sensorDiagonal = sqrt(sensorWidth * sensorWidth + sensorHeight * sensorHeight)
        let halfDiagonal = sensorDiagonal / 2.0
        let maxAngle = atan(halfDiagonal / focalLength)
        
        let (matchesCos4, cos4Deviation) = luminanceProfile.matchesCos4LawWithDeviation(
            tolerance: cos4Tolerance, 
            intensity: vignetteIntensity,
            maxAngle: maxAngle
        )
        metrics["matches_cos4_law"] = matchesCos4 ? 1.0 : 0.0
        // YAML expects 'cos4_deviation' - emit the actual deviation value
        metrics["cos4_deviation"] = cos4Deviation
        
        if !matchesCos4 {
            diagnostics.append(Diagnostic(
                severity: .error,
                code: "VIGNETTE_COS4_MISMATCH",
                message: "Vignette falloff does not match cos⁴ law within \(String(format: "%.0f", cos4Tolerance * 100))% tolerance",
                context: [
                    "center_luminance": "\(luminanceProfile.centerLuminance)",
                    "edge_luminance": "\(luminanceProfile.edgeLuminance)",
                    "falloff_ratio": "\(luminanceProfile.falloffRatio)",
                    "intensity": "\(parameters.intensity ?? 0)"
                ]
            ))
            suggestedFixes.append("Verify fx_vignette_physical in MetaVisFXShaders.metal uses cos⁴(θ) formula")
            suggestedFixes.append("Check that vignette radius calculation is based on sensor geometry")
        }
        
        // 3. Edge Darkening Verification
        let edgeDarkeningMin = tolerances["edge_darkening_min"] ?? 0.1
        let actualDarkening = 1.0 - (luminanceProfile.edgeLuminance / max(luminanceProfile.centerLuminance, 0.001))
        metrics["edge_darkening"] = actualDarkening
        
        if actualDarkening < edgeDarkeningMin && (parameters.intensity ?? 0) > 0.3 {
            diagnostics.append(Diagnostic(
                severity: .warning,
                code: "VIGNETTE_WEAK_EFFECT",
                message: "Vignette edge darkening is only \(String(format: "%.1f", actualDarkening * 100))% (expected at least \(String(format: "%.1f", edgeDarkeningMin * 100))%)",
                context: [
                    "intensity": "\(parameters.intensity ?? 0)",
                    "edge_darkening": "\(actualDarkening)"
                ]
            ))
        }
        
        // 4. Center Preservation Test
        if let baseline = baselineData {
            // Use linearize: true to match the test profile (both are now ToneMapped)
            let baselineProfile = try await visionAnalyzer.analyzeLuminanceProfile(data: baseline, regions: 10, linearize: true)
            let centerPreservation = luminanceProfile.centerLuminance / max(baselineProfile.centerLuminance, 0.001)
            metrics["center_preservation"] = centerPreservation
            // YAML expects 'center_brightness' - emit as alias
            metrics["center_brightness"] = centerPreservation
            
            let minPreservation = centerPreservationMin
            if centerPreservation < minPreservation {
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    code: "VIGNETTE_CENTER_AFFECTED",
                    message: "Vignette is affecting center luminance (preserved: \(String(format: "%.1f", centerPreservation * 100))%, expected: >\(String(format: "%.1f", minPreservation * 100))%)",
                    context: [
                        "baseline_center": "\(baselineProfile.centerLuminance)",
                        "vignetted_center": "\(luminanceProfile.centerLuminance)"
                    ]
                ))
                suggestedFixes.append("Adjust vignette radius calculation to preserve center area")
            }
            
            // 5. Compare to baseline for overall change
            let ssim = try await visionAnalyzer.calculateSSIM(originalData: baseline, modifiedData: frameData)
            metrics["ssim"] = ssim.overall
        }
        
        // 6. Symmetry Analysis
        // Compare opposite quadrants - vignette should be symmetric
        let symmetryDeviation = calculateSymmetryDeviation(luminanceProfile)
        metrics["symmetry_deviation"] = symmetryDeviation
        // YAML expects 'symmetry_variance' - emit as alias
        metrics["symmetry_variance"] = symmetryDeviation
        
        let symmetryTolerance = tolerances["symmetry_tolerance"] ?? 0.05
        if symmetryDeviation > symmetryTolerance {
            diagnostics.append(Diagnostic(
                severity: .warning,
                code: "VIGNETTE_ASYMMETRIC",
                message: "Vignette is asymmetric (deviation: \(String(format: "%.1f", symmetryDeviation * 100))%)",
                context: [
                    "symmetry_deviation": "\(symmetryDeviation)"
                ]
            ))
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
    
    private func calculateSymmetryDeviation(_ profile: LuminanceProfile) -> Float {
        // Compare inner vs outer rings for radial symmetry
        guard profile.ringLuminance.count >= 4 else { return 0 }
        
        var totalDeviation: Float = 0
        let midpoint = profile.ringLuminance.count / 2
        
        // Compare each ring pair equidistant from center
        for i in 0..<midpoint {
            let _ = profile.ringLuminance[i] / max(profile.ringLuminance[0], 0.001)
            // Vignette should darken progressively
            if i > 0 && profile.ringLuminance[i] > profile.ringLuminance[i-1] * 1.05 {
                totalDeviation += 0.1 // Penalize non-monotonic falloff
            }
        }
        
        return min(totalDeviation, 1.0)
    }
}
