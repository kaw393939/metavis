import Foundation
import Metal
import simd
import Logging
import Vision
import Yams

/// Validates chromatic aberration - color fringing at edges
@available(macOS 14.0, *)
public struct ChromaticAberrationValidator: EffectValidator {
    public let effectName = "chromatic_aberration"
    public let tolerances: [String: Float]
    
    private let device: MTLDevice
    private let visionAnalyzer: VisionAnalyzer
    private let logger = Logger(label: "com.metalvis.validation.ca")
    
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
            "spectral_order_correct": 1.0,  // Must have correct R-G-B order
            "edge_fringing_min": 0.02,      // Minimum color separation at edges
            "center_preservation": 0.98,    // Center should be nearly unaffected
            "ssim_min": 0.85                // Should maintain structure
        ]
        
        for (key, value) in tolerances {
            defaultTolerances[key] = value
        }
        self.tolerances = defaultTolerances
    }
    
    private func loadMathConfig() -> MathConfig? {
        let path = "assets/config/validation_math/camera_lens_math.yaml"
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
        logger.info("Validating chromatic aberration at frame \(context.frameIndex)")
        
        var metrics: [String: Float] = [:]
        var diagnostics: [Diagnostic] = []
        var suggestedFixes: [String] = []
        
        // Load math config
        let mathConfig = loadMathConfig()
        var edgeSeparationMin = tolerances["edge_fringing_min"] ?? 0.02
        var centerSeparationMax: Float = 0.05 // Default
        
        if let config = mathConfig,
           let scenario = config.scenarios["chromatic_aberration_lateral"] {
            if let es = scenario.expectations["edge_separation_min"] {
                edgeSeparationMin = Float(es)
                logger.info("Using edge separation min from config: \(edgeSeparationMin)")
            }
            if let cs = scenario.expectations["center_separation_max"] {
                centerSeparationMax = Float(cs)
            }
        }
        
        // 1. Edge Analysis - CA should create color fringing at edges
        let edges = try await visionAnalyzer.analyzeEdges(data: frameData)
        metrics["edge_count"] = Float(edges.edgeCount)
        metrics["edge_density"] = edges.edgeDensity
        
        // 2. Color Distribution Analysis
        let colorDist = try await visionAnalyzer.analyzeColorDistribution(data: frameData)
        
        if let baseline = baselineData {
            let baselineColors = try await visionAnalyzer.analyzeColorDistribution(data: baseline)
            
            // Calculate histogram spread changes
            // CA should increase color variance at edges
            let redSpread = calculateHistogramSpread(colorDist.redHistogram)
            let greenSpread = calculateHistogramSpread(colorDist.greenHistogram)
            let blueSpread = calculateHistogramSpread(colorDist.blueHistogram)
            
            let baseRedSpread = calculateHistogramSpread(baselineColors.redHistogram)
            let baseGreenSpread = calculateHistogramSpread(baselineColors.greenHistogram)
            let baseBlueSpread = calculateHistogramSpread(baselineColors.blueHistogram)
            
            metrics["red_spread_delta"] = redSpread - baseRedSpread
            metrics["green_spread_delta"] = greenSpread - baseGreenSpread
            metrics["blue_spread_delta"] = blueSpread - baseBlueSpread
            
            // YAML expects 'edge_separation' - calculate from spread deltas
            let avgSpreadDelta = (abs(redSpread - baseRedSpread) + abs(blueSpread - baseBlueSpread)) / 2.0
            metrics["edge_separation"] = min(1.0, avgSpreadDelta * 10.0) // Normalize to 0-1 range
            
            // YAML expects 'neutral_deviation' - calculate CENTER region color neutrality
            // CA should not affect the center of the image, so sample a small center region
            let centerColorResult = try await visionAnalyzer.analyzeCenterRegionColor(data: frameData, regionRadius: 0.1)
            let centerR = centerColorResult.x
            let centerG = centerColorResult.y
            let centerB = centerColorResult.z
            let neutralDeviation = max(abs(centerR - centerG), abs(centerG - centerB), abs(centerR - centerB))
            metrics["neutral_deviation"] = neutralDeviation
            
            // YAML expects 'center_separation' - should be minimal at center
            metrics["center_separation"] = neutralDeviation
            
            // 3. Verify spectral order (R outside, then G, then B inside)
            // This requires analyzing radial color distribution
            // For physical CA, red should be displaced outward most
            // We check if the radial color distribution matches physics
            let spectralOrderCorrect = await verifySpectralOrder(frameData: frameData, baselineData: baseline)
            metrics["spectral_order_correct"] = spectralOrderCorrect ? 1.0 : 0.0
            
            if !spectralOrderCorrect {
                diagnostics.append(Diagnostic(
                    severity: .error,
                    code: "CA_WRONG_SPECTRAL_ORDER",
                    message: "Chromatic aberration has incorrect spectral order. Expected: Red displaced outward most, Blue least",
                    context: [
                        "intensity": "\(parameters.intensity ?? 0)"
                    ]
                ))
                suggestedFixes.append("Check fx_spectral_ca in MetaVisFXShaders.metal - verify wavelength-based displacement")
                suggestedFixes.append("Ensure red channel gets largest radial offset, blue smallest")
            }
            
            // 4. Center Preservation
            // CA should not affect the optical center
            let ssim = try await visionAnalyzer.calculateSSIM(originalData: baseline, modifiedData: frameData)
            metrics["ssim"] = ssim.overall
            
            // 5. Structural Similarity 
            let minSSIM = tolerances["ssim_min"] ?? 0.85
            if ssim.overall < minSSIM {
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    code: "CA_EXCESSIVE_DISTORTION",
                    message: "Chromatic aberration caused excessive distortion (SSIM: \(String(format: "%.3f", ssim.overall)))",
                    context: [
                        "ssim": "\(ssim.overall)",
                        "intensity": "\(parameters.intensity ?? 0)"
                    ]
                ))
            }
            
            // Check thresholds
            if metrics["edge_separation"]! < edgeSeparationMin {
                 diagnostics.append(Diagnostic(
                    severity: .error,
                    code: "CA_WEAK_EFFECT",
                    message: "Channel Separation at Edges failed threshold check",
                    context: [
                        "edge_separation": "\(metrics["edge_separation"]!)",
                        "expected": "> \(edgeSeparationMin)"
                    ]
                ))
            }
            
            if metrics["center_separation"]! > centerSeparationMax {
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    code: "CA_CENTER_AFFECTED",
                    message: "Chromatic aberration is affecting center (separation: \(String(format: "%.3f", metrics["center_separation"]!)))",
                    context: [
                        "center_separation": "\(metrics["center_separation"]!)",
                        "expected": "< \(centerSeparationMax)"
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
    
    private func calculateHistogramSpread(_ histogram: [Int]) -> Float {
        let total = histogram.reduce(0, +)
        guard total > 0 else { return 0 }
        
        // Calculate standard deviation of histogram
        var mean: Float = 0
        for (i, count) in histogram.enumerated() {
            mean += Float(i) * Float(count)
        }
        mean /= Float(total)
        
        var variance: Float = 0
        for (i, count) in histogram.enumerated() {
            let diff = Float(i) - mean
            variance += diff * diff * Float(count)
        }
        variance /= Float(total)
        
        return sqrt(variance)
    }
    
    private func verifySpectralOrder(frameData: Data, baselineData: Data) async -> Bool {
        do {
            // Analyze radial profiles to detect channel displacement
            let profiles = try await visionAnalyzer.analyzeRadialChannelProfiles(data: frameData, regions: 20)
            
            // Calculate "center of mass" (centroid) for each channel's radial distribution
            // This tells us the average distance of that color from the center
            func calculateCentroid(_ profile: [Float]) -> Float {
                var weightedSum: Float = 0
                var totalWeight: Float = 0
                for (i, val) in profile.enumerated() {
                    let radius = Float(i)
                    weightedSum += radius * val
                    totalWeight += val
                }
                return totalWeight > 0 ? weightedSum / totalWeight : 0
            }
            
            let rCentroid = calculateCentroid(profiles.red)
            let gCentroid = calculateCentroid(profiles.green)
            let bCentroid = calculateCentroid(profiles.blue)
            
            // For typical CA (red fringing outside), Red should be furthest out, Blue furthest in
            // R > G > B
            let isCorrectOrder = rCentroid > gCentroid && gCentroid > bCentroid
            
            // Also check if there is actual separation (if they are equal, no CA is applied)
            let separation = (rCentroid - bCentroid)
            let hasSeparation = separation > 0.1 // Minimum threshold
            
            return isCorrectOrder && hasSeparation
        } catch {
            return false
        }
    }
}
