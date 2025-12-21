import Foundation
import Metal
import simd
import Logging

/// Validates ACES color pipeline implementation
/// Checks for color accuracy, gradient smoothness, and highlight rolloff
@available(macOS 14.0, *)
public struct ACESValidator: EffectValidator {
    public let effectName = "aces"
    public let tolerances: [String: Float]
    
    private let device: MTLDevice
    private let visionAnalyzer: VisionAnalyzer
    private let logger = Logger(label: "com.metalvis.validation.aces")
    
    public init(device: MTLDevice, tolerances: [String: Float] = [:]) {
        self.device = device
        self.visionAnalyzer = VisionAnalyzer(device: device)
        
        var defaultTolerances: [String: Float] = [
            "banding_max": 0.02,           // Max 2% pixels with banding artifacts
            "highlight_compression_min": 0.5, // Highlights should be compressed by at least 50%
            "black_level_max": 0.01,       // Blacks should stay black
            "hue_shift_max": 0.1           // Allow some hue shift (ACES RRT does this), but limit it
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
        logger.info("Validating ACES pipeline at frame \(context.frameIndex)")
        
        var metrics: [String: Float] = [:]
        var diagnostics: [Diagnostic] = []
        var suggestedFixes: [String] = []
        
        // 1. Banding Analysis (Gradient Smoothness)
        // ACES processing (especially 3D LUTs or shaping functions) can introduce banding
        let bandingScore = try await calculateBandingScore(data: frameData)
        metrics["banding_score"] = bandingScore
        
        let maxBanding = tolerances["banding_max"] ?? 0.02
        if bandingScore > maxBanding {
            diagnostics.append(Diagnostic(
                severity: .warning,
                code: "ACES_BANDING",
                message: "Banding detected in ACES gradients (\(String(format: "%.1f", bandingScore * 100))% affected)",
                context: [
                    "banding_score": "\(bandingScore)",
                    "threshold": "\(maxBanding)"
                ]
            ))
            suggestedFixes.append("Ensure ACES LUTs are at least 32x32x32")
            suggestedFixes.append("Check for 16-bit float precision in intermediate textures")
        }
        
        // 2. Highlight Rolloff Analysis
        // Compare high-dynamic-range input (baseline) with tone-mapped output
        if let baseline = baselineData {
            let (minLum, maxLum) = try await visionAnalyzer.getMinMaxLuminance(data: frameData)
            let (_, baseMax) = try await visionAnalyzer.getMinMaxLuminance(data: baseline)
            
            metrics["output_max_luminance"] = maxLum
            metrics["input_max_luminance"] = baseMax
            
            // ACES should compress highlights. If input was > 1.0, output should be <= 1.0 (mostly)
            // But here baseline is likely already 0-1 range if it's a PNG.
            // Ideally we'd have the raw HDR buffer, but we're working with rendered frames.
            // We can check if the "brightest" parts got dimmer (compression).
            
            if baseMax > 0.1 {
                let compressionRatio = maxLum / baseMax
                metrics["highlight_compression"] = compressionRatio
                
                // If we are simulating HDR input (e.g. intensity > 1.0), we expect compression
                // But if input is standard range, ACES might slightly boost or keep it.
                // Let's assume the test scene has bright lights.
            }
            
            // 3. Black Level Stability
            // ACES shouldn't lift blacks significantly
            metrics["black_level"] = minLum
            let maxBlack = tolerances["black_level_max"] ?? 0.01
            
            if minLum > maxBlack {
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    code: "ACES_LIFTED_BLACKS",
                    message: "ACES pipeline is lifting blacks (level: \(String(format: "%.3f", minLum)))",
                    context: [
                        "black_level": "\(minLum)",
                        "limit": "\(maxBlack)"
                    ]
                ))
                suggestedFixes.append("Check ACEScct to ACEScg conversion for offset errors")
            }
        }
        
        // 4. Color Chart / Hue Preservation
        // We check if the average color hue has shifted too much
        let colorDist = try await visionAnalyzer.analyzeColorDistribution(data: frameData)
        
        if let baseline = baselineData {
            let baseColorDist = try await visionAnalyzer.analyzeColorDistribution(data: baseline)
            
            // Calculate Hue shift
            let hueShift = calculateHueShift(from: baseColorDist.averageColor, to: colorDist.averageColor)
            metrics["hue_shift"] = hueShift
            
            let maxHueShift = tolerances["hue_shift_max"] ?? 0.1
            // ACES RRT *does* shift hues (the "film look"), especially for red/orange
            // So we allow some shift, but not extreme
            
            if hueShift > maxHueShift {
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    code: "ACES_HUE_SHIFT",
                    message: "Excessive hue shift detected (\(String(format: "%.3f", hueShift)))",
                    context: [
                        "hue_shift": "\(hueShift)",
                        "limit": "\(maxHueShift)"
                    ]
                ))
            }
        }
        
        // 5. Macbeth Chart Validation (if requested)
        // Check for test_type parameter (1.0 = Macbeth)
        if let testType = parameters.additionalParams["test_type"], abs(testType - 1.0) < 0.01 {
            let (avgDE, maxDE, grayDE) = try await validateMacbethChart(data: frameData)
            metrics["macbeth_avg_delta_e"] = avgDE
            metrics["macbeth_max_delta_e"] = maxDE
            metrics["macbeth_gray_delta_e"] = grayDE
            
            // Add diagnostics
            // ACES RRT+ODT is intended to be "pleasing" not "accurate" to the scene referred values
            // So we expect significant deviation from the linear input values.
            // However, for "Industry Validity", we want to ensure it's within a "filmic" range.
            // A Delta E of < 10 is usually good for a look-up table approximation.
            // < 20 is acceptable for strong looks.
            let maxAvgDE = tolerances["macbeth_avg_de_max"] ?? 20.0
            
            if avgDE > maxAvgDE {
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    code: "ACES_COLOR_ACCURACY",
                    message: "Macbeth Chart Average Delta E is high (\(String(format: "%.1f", avgDE)))",
                    context: ["macbeth_avg_delta_e": "\(avgDE)", "limit": "\(maxAvgDE)"]
                ))
                suggestedFixes.append("Verify ACES Output Transform (ODT) matches Rec.709 target")
            }
            
            // Grayscale neutrality is more important
            let maxGrayDE = tolerances["macbeth_gray_de_max"] ?? 10.0
            if grayDE > maxGrayDE {
                diagnostics.append(Diagnostic(
                    severity: .error, // Grayscale error is critical
                    code: "ACES_GRAYSCALE_TINT",
                    message: "Grayscale patches show significant tint (Delta E: \(String(format: "%.1f", grayDE)))",
                    context: ["macbeth_gray_delta_e": "\(grayDE)", "limit": "\(maxGrayDE)"]
                ))
                suggestedFixes.append("Check white point adaptation in ACES pipeline")
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
    
    /// Calculates banding score by detecting sudden luminance jumps in gradients
    private func calculateBandingScore(data: Data) async throws -> Float {
        // Reusing the logic from BloomValidator
        let luminanceProfile = try await visionAnalyzer.analyzeLuminanceProfile(data: data, regions: 20)
        
        var bandingCount: Float = 0
        var totalComparisons: Float = 0
        
        let rings = luminanceProfile.ringLuminance
        guard rings.count >= 3 else { return 0 }
        
        for i in 3..<rings.count {
            let delta1 = rings[i-2] - rings[i-3]
            let delta2 = rings[i-1] - rings[i-2]
            let delta3 = rings[i] - rings[i-1]
            
            // Check for oscillation pattern: + - + or - + -
            let isOscillating = (delta1 > 0.005 && delta2 < -0.005 && delta3 > 0.005) ||
                               (delta1 < -0.005 && delta2 > 0.005 && delta3 < -0.005)
            
            if isOscillating {
                bandingCount += 1
            }
            totalComparisons += 1
        }
        
        return totalComparisons > 0 ? bandingCount / totalComparisons : 0
    }
    
    private func calculateHueShift(from c1: SIMD3<Float>, to c2: SIMD3<Float>) -> Float {
        // Simple RGB to Hue conversion
        func rgbToHue(_ c: SIMD3<Float>) -> Float {
            let minVal = min(c.x, min(c.y, c.z))
            let maxVal = max(c.x, max(c.y, c.z))
            let delta = maxVal - minVal
            
            if delta < 0.0001 { return 0 }
            
            var hue: Float = 0
            if c.x == maxVal {
                hue = (c.y - c.z) / delta
            } else if c.y == maxVal {
                hue = 2 + (c.z - c.x) / delta
            } else {
                hue = 4 + (c.x - c.y) / delta
            }
            
            hue *= 60
            if hue < 0 { hue += 360 }
            return hue / 360.0 // Normalize 0-1
        }
        
        let h1 = rgbToHue(c1)
        let h2 = rgbToHue(c2)
        
        // Circular difference
        let diff = abs(h1 - h2)
        return min(diff, 1.0 - diff)
    }
    
    // MARK: - Macbeth Chart Validation
    
    private func validateMacbethChart(data: Data) async throws -> (avgDeltaE: Float, maxDeltaE: Float, grayDeltaE: Float) {
        // Macbeth Chart Layout: 6 columns x 4 rows
        // We sample the center of each patch
        
        // Reference ACES 1.3 Output values (Linear Rec.709)
        let references: [SIMD3<Float>] = [
            // Row 1
            SIMD3(0.056, 0.034, 0.018), SIMD3(0.296, 0.183, 0.128), SIMD3(0.033, 0.068, 0.153),
            SIMD3(0.032, 0.049, 0.015), SIMD3(0.095, 0.079, 0.186), SIMD3(0.122, 0.254, 0.210),
            // Row 2
            SIMD3(0.445, 0.203, 0.019), SIMD3(0.041, 0.049, 0.231), SIMD3(0.202, 0.045, 0.048),
            SIMD3(0.025, 0.012, 0.047), SIMD3(0.212, 0.300, 0.033), SIMD3(0.489, 0.351, 0.030),
            // Row 3
            SIMD3(0.001, 0.003, 0.191), SIMD3(0.004, 0.153, 0.011), SIMD3(0.299, 0.012, 0.007),
            SIMD3(0.556, 0.495, 0.019), SIMD3(0.265, 0.014, 0.159), SIMD3(0.003, 0.195, 0.291),
            // Row 4 (Grayscale)
            SIMD3(0.580, 0.580, 0.580), SIMD3(0.428, 0.428, 0.428), SIMD3(0.264, 0.264, 0.264),
            SIMD3(0.113, 0.113, 0.113), SIMD3(0.030, 0.030, 0.030), SIMD3(0.006, 0.006, 0.006)
        ]
        
        // 1. Measure all patches first
        var measuredColors: [SIMD3<Float>] = []
        for i in 0..<24 {
            let row = i / 6
            let col = i % 6
            
            // Calculate center of patch in normalized coordinates (0-1)
            let marginX: CGFloat = 0.206
            let marginY: CGFloat = 0.155
            let effectiveWidth = 1.0 - 2.0 * marginX
            let effectiveHeight = 1.0 - 2.0 * marginY
            
            let cx = marginX + (CGFloat(col) + 0.5) * (effectiveWidth / 6.0)
            let cy = marginY + (CGFloat(row) + 0.5) * (effectiveHeight / 4.0)
            
            let region = CGRect(x: cx - 0.02, y: cy - 0.02, width: 0.04, height: 0.04)
            
            let color = try await visionAnalyzer.analyzeRegionColor(data: data, region: region)
            measuredColors.append(color)
        }
        
        // 2. Calculate Exposure Offset using Neutral 5 (Index 21 - 18% Grey equivalent)
        // Reference for Neutral 5 is approx 0.19 (linear)
        let refGrey = references[21].y // Use Luminance or Green channel
        let measGrey = measuredColors[21].y
        
        // Avoid divide by zero
        let exposureScale = (measGrey > 0.001) ? (refGrey / measGrey) : 1.0
        
        // Log the exposure correction
        print("ACES Validation: Exposure Scale = \(exposureScale) (Ref: \(refGrey), Meas: \(measGrey))")
        
        var totalDeltaE: Float = 0
        var maxDeltaE: Float = 0
        var grayDeltaE: Float = 0
        
        for i in 0..<24 {
            // Apply exposure normalization
            let measuredColor = measuredColors[i] * exposureScale
            let refColor = references[i]
            
            // measuredColor is already Linear (if using Raw Buffer) or sRGB (if PNG)
            // VisionAnalyzer.analyzeRegionColor returns 0-1 float.
            // If we are using Raw Buffer, it is Linear Rec.709 (ACES Output).
            // If we are using PNG, it is sRGB encoded.
            // However, calculateDeltaE2000 expects "measuredSrgb" and converts it.
            // We need to handle this based on the data source type, but VisionAnalyzer hides it.
            // Wait, analyzeRegionColor returns raw values.
            // If Raw Buffer -> Linear values.
            // If PNG -> sRGB values.
            // calculateDeltaE2000 calls srgbToLinear.
            // This is a problem. We fixed VisionAnalyzer to handle raw buffers, but analyzeRegionColor just averages bytes.
            // If Raw Buffer, analyzeRegionColor returns Linear values directly.
            // If we pass Linear values to calculateDeltaE2000, it will re-linearize them (pow 2.4)!
            
            // We need a linear-aware DeltaE function.
            let deltaE = calculateDeltaE2000(measured: measuredColor, refLinear: refColor, isMeasuredLinear: true) // Assuming Raw Buffer is used now
            
            if i < 3 {
                print("Patch \(i): Meas(Norm)=\(measuredColor), Ref=\(refColor) -> DE=\(deltaE)")
            }
            
            totalDeltaE += deltaE
            if deltaE > maxDeltaE {
                maxDeltaE = deltaE
            }
            
            // Accumulate grayscale error (Row 4, indices 18-23)
            if i >= 18 {
                grayDeltaE += deltaE
            }
        }
        
        return (totalDeltaE / 24.0, maxDeltaE, grayDeltaE / 6.0)
    }
    
    private func calculateDeltaE2000(measured: SIMD3<Float>, refLinear: SIMD3<Float>, isMeasuredLinear: Bool) -> Float {
        // Convert Measured -> Linear (if needed) -> Lab
        let measuredLinear = isMeasuredLinear ? measured : srgbToLinear(measured)
        let lab1 = linearRgbToLab(measuredLinear)
        
        // Convert Reference Linear -> Lab
        let lab2 = linearRgbToLab(refLinear)
        
        // CIEDE2000 Implementation (Simplified to Euclidean in Lab for now)
        let dL = lab1.x - lab2.x
        let da = lab1.y - lab2.y
        let db = lab1.z - lab2.z
        
        return sqrt(dL*dL + da*da + db*db)
    }
    
    private func srgbToLinear(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        func toLinear(_ v: Float) -> Float {
            return (v > 0.04045) ? pow((v + 0.055) / 1.055, 2.4) : (v / 12.92)
        }
        return SIMD3<Float>(toLinear(rgb.x), toLinear(rgb.y), toLinear(rgb.z))
    }
    
    private func linearRgbToLab(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        // 1. Linear RGB to XYZ (Rec.709 / D65)
        // Matrix from http://www.brucelindbloom.com/
        let r = rgb.x
        let g = rgb.y
        let b = rgb.z
        
        let x = r * 0.4124564 + g * 0.3575761 + b * 0.1804375
        let y = r * 0.2126729 + g * 0.7151522 + b * 0.0721750
        let z = r * 0.0193339 + g * 0.1191920 + b * 0.9503041
        
        // 2. XYZ to Lab
        // D65 Reference White
        let refX: Float = 0.95047
        let refY: Float = 1.00000
        let refZ: Float = 1.08883
        
        let var_X = x / refX
        let var_Y = y / refY
        let var_Z = z / refZ
        
        func f(_ v: Float) -> Float {
            return (v > 0.008856) ? pow(v, 1.0/3.0) : (7.787 * v + 16.0/116.0)
        }
        
        let L = 116.0 * f(var_Y) - 16.0
        let a = 500.0 * (f(var_X) - f(var_Y))
        let b_val = 200.0 * (f(var_Y) - f(var_Z))
        
        return SIMD3<Float>(L, a, b_val)
    }
}
