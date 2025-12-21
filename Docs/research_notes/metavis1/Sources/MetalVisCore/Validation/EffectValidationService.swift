import Foundation
import ImageIO
import UniformTypeIdentifiers
import Metal
import CoreImage
import Vision
import Logging
import AVFoundation

// MARK: - Validation-Specific Types

// Note: `ValidationCheckpoint` is defined in `EffectValidator.swift` and reused here.
// Avoid redefining it to prevent conflicts.

/// Validation configuration embedded in manifest
public struct ValidationConfig: Codable, Sendable {
    public let checkpoints: [ManifestValidationCheckpoint]
    
    public init(checkpoints: [ManifestValidationCheckpoint]) {
        self.checkpoints = checkpoints
    }
}

/// Extended manifest that includes validation checkpoints
/// Uses validation-specific types to avoid collision with SemanticManifest types
public struct ValidationManifest: Codable, Sendable {
    public let manifestId: String?
    public let version: String?
    public let metadata: ValidationManifestMeta
    public let scene: ValidationSceneDefinition
    public let postProcessing: ValidationPostProcessDefinition
    public let elements: [ValidationElement]
    
    enum CodingKeys: String, CodingKey {
        case manifestId
        case version
        case metadata
        case scene
        case postProcessing = "post_processing"
        case elements
    }
}

/// Simplified meta for validation
public struct ValidationManifestMeta: Codable, Sendable {
    public let title: String
    public let durationSeconds: Double
    public let targetAspectRatio: String
    public let intendedQualityProfile: String
    
    enum CodingKeys: String, CodingKey {
        case title
        case durationSeconds = "duration_seconds"
        case targetAspectRatio = "target_aspect_ratio"
        case intendedQualityProfile = "intended_quality_profile"
    }
}

public struct ValidationSceneDefinition: Codable, Sendable {
    // We only care about what affects validation
}

public struct ValidationPostProcessDefinition: Codable, Sendable {
    public let bloom: ValidationEffectConfig?
    public let halation: ValidationEffectConfig?
    public let filmGrain: ValidationEffectConfig?
    public let vignette: ValidationEffectConfig?
    public let anamorphic: ValidationEffectConfig?
    public let lensDistortion: ValidationEffectConfig?
    public let chromaticAberration: ValidationEffectConfig?
    public let shimmer: ValidationEffectConfig?
    public let volumetric: ValidationEffectConfig?
    public let energy: ValidationEffectConfig?
    public let bokeh: ValidationEffectConfig?
    public let pbr: ValidationEffectConfig?
    
    enum CodingKeys: String, CodingKey {
        case bloom
        case halation
        case filmGrain = "film_grain"
        case vignette
        case anamorphic
        case lensDistortion = "lens_distortion"
        case chromaticAberration = "chromatic_aberration"
        case shimmer
        case volumetric
        case energy
        case bokeh
        case pbr
    }
}

public struct ValidationElement: Codable, Sendable {
    public let type: String
    public let id: String
    public let content: String?
    public let animation: ValidationAnimation?
    // Validation checkpoints might be attached to elements in the future, 
    // but for now the spec doesn't show them in the elements list in the example.
    // Wait, the old manifest had `validation` in `VisualEvent`.
    // The new manifest example doesn't show explicit validation checkpoints in the JSON.
    // But the `manifest_dictionary.md` implies validation is done against the manifest specs.
    // For now, I will assume we might add a `validation` field to `ManifestElement` later.
    // Or maybe validation is external now?
    // The user provided `validation/logo_intro_tests.yaml` in the brief.
    // But `EffectValidationService` expects them in the manifest or a separate file.
    // Let's add an optional validation field here just in case.
    public let validation: ManifestValidationCheckpoint?
}

public struct ValidationAnimation: Codable, Sendable {
    public let start: Double
    public let end: Double
}

public struct ValidationEffectConfig: Codable, Sendable {
    public let enabled: Bool?
    public let intensity: Float?
    public let threshold: Float?
    public let magnitude: Float? // For halation
}


// MARK: - Validation Errors

public enum ValidationError: Error, LocalizedError {
    case deviceInitFailed(String)
    case frameExtractionFailed(String)
    case validatorNotFound(String)
    case invalidManifest(String)
    
    public var errorDescription: String? {
        switch self {
        case .deviceInitFailed(let msg):
            return "Device initialization failed: \(msg)"
        case .frameExtractionFailed(let msg):
            return "Frame extraction failed: \(msg)"
        case .validatorNotFound(let effect):
            return "No validator found for effect: \(effect)"
        case .invalidManifest(let msg):
            return "Invalid manifest: \(msg)"
        }
    }
}

// MARK: - Effect Validation Service

/// Main service that orchestrates validation of all post-processing effects
/// Designed to output actionable data for AI coding agents
@available(macOS 14.0, *)
public actor EffectValidationService {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext
    private let logger = Logger(label: "com.metalvis.validation")
    
    // Registered validators (populated via registerValidator)
    private var validators: [String: any EffectValidator] = [:]
    
    public init(device: MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw ValidationError.deviceInitFailed("Failed to create command queue")
        }
        self.commandQueue = queue
        self.ciContext = CIContext(mtlDevice: device)
    }
    
    /// Register a validator for an effect
    public func registerValidator(_ validator: any EffectValidator) {
        validators[validator.effectName] = validator
    }
    
    /// Register multiple validators at once
    public func registerValidators(_ newValidators: [any EffectValidator]) {
        for validator in newValidators {
            validators[validator.effectName] = validator
        }
    }
    
    /// Validate a rendered video against expected effect behavior
    /// - Parameters:
    ///   - videoURL: Path to the rendered video
    ///   - manifestURL: Path to the validation manifest
    /// - Returns: Complete validation report
    public func validate(
        videoURL: URL,
        manifestURL: URL
    ) async throws -> ValidationReport {
        logger.info("Starting validation: \(videoURL.lastPathComponent)")
        
        // Load manifest
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(ValidationManifest.self, from: manifestData)
        
        // Extract checkpoints from manifest
        var checkpoints: [ValidationCheckpoint] = []
        
        // Also extract checkpoints from elements
        for element in manifest.elements {
            if let validation = element.validation {
                // Use animation start time + half duration
                let start = element.animation?.start ?? 0.0
                let end = element.animation?.end ?? manifest.metadata.durationSeconds
                let duration = end - start
                let sampleTime = start + (duration / 2.0)
                
                checkpoints.append(ValidationCheckpoint(
                    timestamp: sampleTime,
                    effect: validation.effect,
                    checkpoint: validation.checkpoint,
                    expectedText: element.content
                ))
            }
        }
        
        // Sort by timestamp
        checkpoints.sort { $0.timestamp < $1.timestamp }
        
        logger.info("Found \(checkpoints.count) validation checkpoints")
        
        // Extract frames at checkpoint timestamps
        let frames = try await extractFrames(from: videoURL, at: checkpoints.map { $0.timestamp })
        
        // Run validation for each checkpoint
        var results: [EffectValidationResult] = []
        var baselineFrame: (data: Data, width: Int, height: Int)?
        
        for (index, checkpoint) in checkpoints.enumerated() {
            guard index < frames.count else { continue }
            let frame = frames[index]
            
            // Store baseline frame (first frame with no effects)
            if checkpoint.effect == "none" && baselineFrame == nil {
                baselineFrame = frame
                logger.info("Stored baseline frame at \(checkpoint.timestamp)s")
                continue
            }
            
            // Skip if no validator for this effect
            guard checkpoint.effect != "none",
                  checkpoint.effect != "combined",
                  let validator = validators[checkpoint.effect] else {
                continue
            }
            
            // Get effect parameters from manifest
            var parameters = extractParameters(for: checkpoint.effect, from: manifest, at: checkpoint.timestamp)
            
            // Inject expected text if available
            if let expectedText = checkpoint.expectedText {
                var textParams = parameters.textParams
                textParams["content"] = expectedText
                parameters = EffectParameters(
                    effectName: parameters.effectName,
                    enabled: parameters.enabled,
                    intensity: parameters.intensity,
                    threshold: parameters.threshold,
                    radius: parameters.radius,
                    additionalParams: parameters.additionalParams,
                    textParams: textParams
                )
            }
            
            // Create validation context
            let context = ValidationContext(
                device: device,
                commandQueue: commandQueue,
                width: frame.width,
                height: frame.height,
                timestamp: checkpoint.timestamp,
                frameIndex: index
            )
            
            // Run validation
            do {
                let result = try await validator.validate(
                    frameData: frame.data,
                    baselineData: baselineFrame?.data,
                    parameters: parameters,
                    context: context
                )
                results.append(result)
                
                let status = result.passed ? "✅" : "❌"
                logger.info("\(status) \(checkpoint.effect) @ \(checkpoint.timestamp)s")
                
                // Save debug artifacts if failed
                if !result.passed && !result.debugArtifacts.isEmpty {
                    let debugDir = videoURL.deletingLastPathComponent().appendingPathComponent("debug_artifacts")
                    try? FileManager.default.createDirectory(at: debugDir, withIntermediateDirectories: true)
                    
                    for (name, data) in result.debugArtifacts {
                        let filename = "\(checkpoint.effect)_\(index)_\(name).png"
                        let fileURL = debugDir.appendingPathComponent(filename)
                        try? data.write(to: fileURL)
                        logger.info("   Saved debug artifact: \(filename)")
                    }
                }
                
            } catch {
                logger.error("Validation failed for \(checkpoint.effect): \(error)")
                results.append(EffectValidationResult(
                    effectName: checkpoint.effect,
                    passed: false,
                    metrics: [:],
                    thresholds: [:],
                    diagnostics: [Diagnostic(
                        severity: .error,
                        code: "VALIDATION_EXCEPTION",
                        message: "Validation threw exception: \(error.localizedDescription)"
                    )],
                    suggestedFixes: ["Check validator implementation for \(checkpoint.effect)"],
                    frameIndex: index
                ))
            }
        }
        
        // Build report
        let report = buildReport(
            results: results,
            videoURL: videoURL,
            manifestURL: manifestURL
        )
        
        logger.info("Validation complete: \(report.summary.passed)/\(report.summary.totalEffects) passed")
        
        return report
    }
    
    /// Extract frames from video at specific timestamps
    public func extractFrames(from videoURL: URL, at timestamps: [Double]) async throws -> [(data: Data, width: Int, height: Int)] {
        var frames: [(data: Data, width: Int, height: Int)] = []
        
        // Use AVFoundation to extract frames
        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.01, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.01, preferredTimescale: 600)
        
        for timestamp in timestamps {
            let time = CMTime(seconds: timestamp, preferredTimescale: 600)

            do {
                let cgImage = try generator.copyCGImage(at: time, actualTime: nil)

                // Encode CGImage to PNG data for Sendable transfer across actor boundary
                let mutableData = CFDataCreateMutable(nil, 0)
                guard let destination = CGImageDestinationCreateWithData(mutableData!, UTType.png.identifier as CFString, 1, nil) else {
                    logger.warning("Failed to create image destination for frame at \(timestamp)s")
                    continue
                }
                CGImageDestinationAddImage(destination, cgImage, nil)
                if CGImageDestinationFinalize(destination) {
                    let data = mutableData! as Data
                    frames.append((data: data, width: cgImage.width, height: cgImage.height))
                } else {
                    logger.warning("Failed to finalize image destination for frame at \(timestamp)s")
                }
            } catch {
                logger.warning("Failed to extract frame at \(timestamp)s: \(error)")
            }
        }

        return frames
    }
    
    /// Convert CGImage to MTLTexture
    
    
    /// Extract effect parameters from manifest
    private func extractParameters(for effectName: String, from manifest: ValidationManifest, at timestamp: Double) -> EffectParameters {
        // Check for text content first if needed
        if effectName == "text_layout" {
            for element in manifest.elements {
                if element.type == "text" {
                    let start = element.animation?.start ?? 0.0
                    let end = element.animation?.end ?? manifest.metadata.durationSeconds
                    if timestamp >= start && timestamp <= end {
                        if let text = element.content {
                            return EffectParameters(
                                effectName: "text_layout",
                                enabled: true,
                                textParams: ["content": text]
                            )
                        }
                    }
                }
            }
            return EffectParameters(effectName: "text_layout", enabled: true)
        }

        // Check global post-processing settings
        let pp = manifest.postProcessing
        
        switch effectName {
        case "bloom":
            if let bloom = pp.bloom, bloom.enabled == true {
                return EffectParameters(
                    effectName: "bloom",
                    enabled: true,
                    intensity: bloom.intensity,
                    threshold: bloom.threshold
                )
            }
        case "halation":
            if let halation = pp.halation, halation.enabled == true {
                return EffectParameters(
                    effectName: "halation",
                    enabled: true,
                    intensity: halation.magnitude ?? halation.intensity, // Handle both naming conventions
                    threshold: halation.threshold
                )
            }
        case "film_grain":
            if let grain = pp.filmGrain, grain.enabled == true {
                return EffectParameters(
                    effectName: "film_grain",
                    enabled: true,
                    intensity: grain.intensity
                )
            }
        case "aces":
            return EffectParameters(
                effectName: "aces",
                enabled: true
            )
        case "vignette":
            if let vignette = pp.vignette, vignette.enabled == true {
                return EffectParameters(
                    effectName: "vignette",
                    enabled: true,
                    intensity: vignette.intensity
                )
            }
        case "anamorphic":
            if let anamorphic = pp.anamorphic, anamorphic.enabled == true {
                return EffectParameters(
                    effectName: "anamorphic",
                    enabled: true,
                    intensity: anamorphic.intensity
                )
            }
        case "lens_distortion":
            if let ld = pp.lensDistortion, ld.enabled == true {
                return EffectParameters(
                    effectName: "lens_distortion",
                    enabled: true,
                    intensity: ld.intensity
                )
            }
        case "chromatic_aberration":
            if let ca = pp.chromaticAberration, ca.enabled == true {
                return EffectParameters(
                    effectName: "chromatic_aberration",
                    enabled: true,
                    intensity: ca.intensity
                )
            }
        case "shimmer":
            if let shimmer = pp.shimmer, shimmer.enabled == true {
                return EffectParameters(
                    effectName: "shimmer",
                    enabled: true,
                    intensity: shimmer.intensity
                )
            }
        case "volumetric":
            if let vol = pp.volumetric, vol.enabled == true {
                return EffectParameters(
                    effectName: "volumetric",
                    enabled: true,
                    intensity: vol.intensity
                )
            }
        case "energy":
            if let energy = pp.energy, energy.enabled == true {
                return EffectParameters(
                    effectName: "energy",
                    enabled: true,
                    intensity: energy.intensity
                )
            }
        case "bokeh":
            if let bokeh = pp.bokeh, bokeh.enabled == true {
                return EffectParameters(
                    effectName: "bokeh",
                    enabled: true,
                    intensity: bokeh.intensity,
                    radius: Float(bokeh.magnitude ?? 0)
                )
            }
        case "pbr":
            if let pbr = pp.pbr, pbr.enabled == true {
                return EffectParameters(
                    effectName: "pbr",
                    enabled: true
                )
            }
        default:
            break
        }
        
        return EffectParameters(effectName: effectName, enabled: false)
    }
    
    /// Build the final validation report
    private func buildReport(
        results: [EffectValidationResult],
        videoURL: URL,
        manifestURL: URL
    ) -> ValidationReport {
        let passed = results.filter { $0.passed }.count
        let failed = results.filter { !$0.passed }.count
        let warnings = results.reduce(0) { $0 + $1.warningCount }
        
        // Generate actionable issues from failed validations
        var actionableIssues: [ValidationReport.ActionableIssue] = []
        
        for result in results where !result.passed {
            for diagnostic in result.diagnostics where diagnostic.severity == .error {
                let issue = ValidationReport.ActionableIssue(
                    priority: "P0",
                    effect: result.effectName,
                    issue: diagnostic.code,
                    file: getFileForEffect(result.effectName),
                    function: getFunctionForDiagnostic(diagnostic.code),
                    description: diagnostic.message,
                    fixSteps: result.suggestedFixes
                )
                actionableIssues.append(issue)
            }
        }
        
        return ValidationReport(
            metadata: ValidationReport.RunMetadata(
                timestamp: Date(),
                videoPath: videoURL.path,
                manifestPath: manifestURL.path,
                hardwareInfo: ValidationReport.HardwareInfo(
                    deviceName: device.name,
                    gpuFamily: "Apple Silicon",
                    recommendedWorkingSet: device.recommendedMaxWorkingSetSize
                )
            ),
            summary: ValidationReport.Summary(
                totalEffects: results.count,
                passed: passed,
                failed: failed,
                warnings: warnings
            ),
            effects: results,
            actionableIssues: actionableIssues
        )
    }
    
    /// Get source file for an effect
    private func getFileForEffect(_ effect: String) -> String? {
        switch effect {
        case "bloom":
            return "Sources/MetalVisCore/Engine/Passes/BloomPass.swift"
        case "halation":
            return "Sources/MetalVisCore/Engine/Passes/HalationPass.swift"
        case "vignette":
            return "Sources/MetalVisCore/Engine/Passes/VignettePass.swift"
        case "film_grain":
            return "Sources/MetalVisCore/Engine/Passes/FilmGrainPass.swift"
        case "chromatic_aberration":
            return "Sources/MetalVisCore/Shaders/MetaVisFXShaders.metal"
        case "anamorphic":
            return "Sources/MetalVisCore/Shaders/MetaVisFXShaders.metal"
        default:
            return nil
        }
    }
    
    /// Get function name for a diagnostic code
    private func getFunctionForDiagnostic(_ code: String) -> String? {
        switch code {
        case "BLOOM_ENERGY_GAIN", "BLOOM_ENERGY_LOSS":
            return "fx_bloom_composite"
        case "HALATION_WRONG_TINT":
            return "fx_halation_composite"
        case "VIGNETTE_COS4_MISMATCH":
            return "fx_vignette_physical"
        case "CA_WRONG_SPECTRAL_ORDER":
            return "fx_spectral_ca"
        case "ANAMORPHIC_WRONG_TINT":
            return "fx_anamorphic_composite"
        default:
            return nil
        }
    }
    
    /// Parse timestamp string (e.g., "1:23.456s") to Double seconds
    private func parseTimestamp(_ timestamp: String) -> Double {
        var s = timestamp.trimmingCharacters(in: .whitespaces)
        if s.hasSuffix("s") { s = String(s.dropLast()) }
        if s.contains(":") {
            let parts = s.split(separator: ":")
            if parts.count == 2 {
                let minutes = Double(parts[0]) ?? 0
                let seconds = Double(parts[1]) ?? 0
                return minutes * 60 + seconds
            }
        }
        return Double(s) ?? 0
    }
}
