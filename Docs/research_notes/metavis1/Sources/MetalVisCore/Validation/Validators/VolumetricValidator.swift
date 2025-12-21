import Foundation
import Metal
import simd
import Logging

/// Validates volumetric lighting effects (God Rays, Fog)
@available(macOS 14.0, *)
public struct VolumetricValidator: EffectValidator {
    public let effectName = "volumetric"
    public let tolerances: [String: Float]
    
    private let device: MTLDevice
    private let visionAnalyzer: VisionAnalyzer
    private let logger = Logger(label: "com.metalvis.validation.volumetric")
    
    public init(device: MTLDevice, tolerances: [String: Float] = [:]) {
        self.device = device
        self.visionAnalyzer = VisionAnalyzer(device: device)
        self.tolerances = tolerances
    }
    
    public func validate(
        frameData: Data,
        baselineData: Data?,
        parameters: EffectParameters,
        context: ValidationContext
    ) async throws -> EffectValidationResult {
        logger.info("Validating volumetric effect at frame \(context.frameIndex)")
        
        var metrics: [String: Float] = [:]
        var diagnostics: [Diagnostic] = []
        
        // 1. Scattering Intensity (Luminance Increase)
        let luminance = try await visionAnalyzer.calculateAverageLuminance(data: frameData)
        metrics["scattering_intensity"] = luminance
        
        if let baseline = baselineData {
            let baselineLum = try await visionAnalyzer.calculateAverageLuminance(data: baseline)
            let increase = luminance - baselineLum
            metrics["scattering_increase"] = increase
            
            if increase < 0.01 {
                 diagnostics.append(Diagnostic(
                    severity: .warning,
                    code: "VOLUMETRIC_LOW_INTENSITY",
                    message: "Volumetric effect added very little luminance (\(String(format: "%.4f", increase)))",
                    context: ["increase": "\(increase)"]
                ))
            }
        }
        
        // 2. Ray Definition (Contrast)
        // Volumetric rays should create high contrast in specific regions
        let contrast = try await visionAnalyzer.calculateContrast(data: frameData)
        metrics["ray_contrast"] = contrast
        
        let minContrast = tolerances["ray_contrast"] ?? 0.2
        if contrast < minContrast {
            diagnostics.append(Diagnostic(
                severity: .warning,
                code: "VOLUMETRIC_LOW_CONTRAST",
                message: "Volumetric rays lack definition/contrast (Contrast: \(String(format: "%.2f", contrast)), min: \(minContrast))",
                context: ["contrast": "\(contrast)"]
            ))
        }
        
        // 3. Density Variance (Uniformity check)
        // Fog should be somewhat uniform, but rays should vary.
        // This is a bit ambiguous without a specific scene.
        // We'll measure variance of the luminance.
        let variance = try await visionAnalyzer.calculateLuminanceVariance(data: frameData)
        metrics["density_variance"] = variance
        
        let passed = !diagnostics.contains { $0.severity == .error }
        
        return EffectValidationResult(
            effectName: effectName,
            passed: passed,
            metrics: metrics.mapValues { Double($0) },
            thresholds: tolerances.mapValues { Double($0) },
            diagnostics: diagnostics,
            suggestedFixes: [],
            frameIndex: context.frameIndex
        )
    }
}
