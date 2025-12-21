import Foundation
import Metal
import simd

// MARK: - Effect Validator Protocol

/// Protocol for all effect validators
/// Each validator implements quantitative tests for a specific post-processing effect
public protocol EffectValidator: Sendable {
    /// Name of the effect being validated (e.g., "bloom", "halation")
    var effectName: String { get }
    
    /// Validates the effect and returns quantitative metrics
    /// - Parameters:
    ///   - frame: The rendered frame with the effect applied
    ///   - baseline: Optional baseline frame without the effect (for comparison)
    ///   - parameters: Effect-specific parameters used during rendering
    /// - Returns: Validation result with metrics and diagnostics
    func validate(
        frameData: Data,
        baselineData: Data?,
        parameters: EffectParameters,
        context: ValidationContext
    ) async throws -> EffectValidationResult
}

// MARK: - Effect Parameters

/// Parameters used when rendering an effect
public struct EffectParameters: Codable, Sendable {
    public let effectName: String
    public let enabled: Bool
    public let intensity: Float?
    public let threshold: Float?
    public let radius: Float?
    public let additionalParams: [String: Float]
    public let textParams: [String: String]
    
    public init(
        effectName: String,
        enabled: Bool = true,
        intensity: Float? = nil,
        threshold: Float? = nil,
        radius: Float? = nil,
        additionalParams: [String: Float] = [:],
        textParams: [String: String] = [:]
    ) {
        self.effectName = effectName
        self.enabled = enabled
        self.intensity = intensity
        self.threshold = threshold
        self.radius = radius
        self.additionalParams = additionalParams
        self.textParams = textParams
    }
}

// MARK: - Validation Context

/// Context information for validation operations
public struct ValidationContext: Sendable {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let width: Int
    public let height: Int
    public let timestamp: Double
    public let frameIndex: Int
    
    public init(
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        width: Int,
        height: Int,
        timestamp: Double,
        frameIndex: Int
    ) {
        self.device = device
        self.commandQueue = commandQueue
        self.width = width
        self.height = height
        self.timestamp = timestamp
        self.frameIndex = frameIndex
    }
}

// MARK: - Validation Result

/// Complete validation result for an effect
public struct EffectValidationResult: Codable, Sendable {
    public let effectName: String
    public let passed: Bool
    public let metrics: [String: Double]
    public let thresholds: [String: Double]
    public let diagnostics: [Diagnostic]
    public let suggestedFixes: [String]
    public let debugArtifacts: [String: Data] // New: Map of artifact name to PNG data
    public let timestamp: Date
    public let frameIndex: Int
    
    public init(
        effectName: String,
        passed: Bool,
        metrics: [String: Double],
        thresholds: [String: Double],
        diagnostics: [Diagnostic],
        suggestedFixes: [String],
        debugArtifacts: [String: Data] = [:],
        timestamp: Date = Date(),
        frameIndex: Int = 0
    ) {
        self.effectName = effectName
        self.passed = passed
        self.metrics = metrics
        self.thresholds = thresholds
        self.diagnostics = diagnostics
        self.suggestedFixes = suggestedFixes
        self.debugArtifacts = debugArtifacts
        self.timestamp = timestamp
        self.frameIndex = frameIndex
    }
    
    public var hasErrors: Bool {
        diagnostics.contains { $0.severity == .error }
    }
    
    public var errorCount: Int {
        diagnostics.filter { $0.severity == .error }.count
    }
    
    public var warningCount: Int {
        diagnostics.filter { $0.severity == .warning }.count
    }
}

// MARK: - Diagnostic

/// A single diagnostic issue detected during validation
public struct Diagnostic: Codable, Sendable {
    public enum Severity: String, Codable, Sendable {
        case info
        case warning
        case error
    }
    
    public let severity: Severity
    public let code: String
    public let message: String
    public let location: FrameRegion?
    public let measuredValue: Double?
    public let expectedMin: Double?
    public let expectedMax: Double?
    public let context: [String: String]?
    
    public init(
        severity: Severity,
        code: String,
        message: String,
        location: FrameRegion? = nil,
        measuredValue: Double? = nil,
        expectedMin: Double? = nil,
        expectedMax: Double? = nil,
        context: [String: String]? = nil
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.location = location
        self.measuredValue = measuredValue
        self.expectedMin = expectedMin
        self.expectedMax = expectedMax
        self.context = context
    }
}

// MARK: - Frame Region

/// A region within a frame for localized diagnostics
public struct FrameRegion: Codable, Sendable {
    public enum RegionType: String, Codable, Sendable {
        case center
        case corners
        case edges
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
        case custom
    }
    
    public let type: RegionType
    public let x: Double?
    public let y: Double?
    public let width: Double?
    public let height: Double?
    
    public init(type: RegionType, x: Double? = nil, y: Double? = nil, width: Double? = nil, height: Double? = nil) {
        self.type = type
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
    
    public static let center = FrameRegion(type: .center)
    public static let corners = FrameRegion(type: .corners)
    public static let edges = FrameRegion(type: .edges)
}

// MARK: - Validation Report

/// Complete validation report for all effects in a video
public struct ValidationReport: Codable, Sendable {
    public struct RunMetadata: Codable, Sendable {
        public let timestamp: Date
        public let videoPath: String
        public let manifestPath: String
        public let hardwareInfo: HardwareInfo
    }
    
    public struct HardwareInfo: Codable, Sendable {
        public let deviceName: String
        public let gpuFamily: String
        public let recommendedWorkingSet: UInt64
    }
    
    public struct Summary: Codable, Sendable {
        public let totalEffects: Int
        public let passed: Int
        public let failed: Int
        public let warnings: Int
    }
    
    public struct ActionableIssue: Codable, Sendable {
        public let priority: String
        public let effect: String
        public let issue: String
        public let file: String?
        public let function: String?
        public let description: String
        public let fixSteps: [String]
    }
    
    public let metadata: RunMetadata
    public let summary: Summary
    public let effects: [EffectValidationResult]
    public let actionableIssues: [ActionableIssue]
    
    public init(
        metadata: RunMetadata,
        summary: Summary,
        effects: [EffectValidationResult],
        actionableIssues: [ActionableIssue]
    ) {
        self.metadata = metadata
        self.summary = summary
        self.effects = effects
        self.actionableIssues = actionableIssues
    }
    
    public var hasErrors: Bool {
        effects.contains { $0.hasErrors }
    }
    
    /// Generate a report suitable for AI agent consumption
    public func generateAIReport() -> String {
        var lines: [String] = []
        lines.append("# Effect Validation Report")
        lines.append("Generated: \(metadata.timestamp)")
        lines.append("")
        lines.append("## Summary")
        lines.append("- Total Effects: \(summary.totalEffects)")
        lines.append("- Passed: \(summary.passed)")
        lines.append("- Failed: \(summary.failed)")
        lines.append("- Warnings: \(summary.warnings)")
        lines.append("")
        
        if !actionableIssues.isEmpty {
            lines.append("## Actionable Issues")
            for issue in actionableIssues {
                lines.append("")
                lines.append("### [\(issue.priority)] \(issue.effect): \(issue.issue)")
                lines.append(issue.description)
                if let file = issue.file {
                    lines.append("**File**: `\(file)`")
                }
                if let function = issue.function {
                    lines.append("**Function**: `\(function)`")
                }
                lines.append("**Fix Steps**:")
                for (i, step) in issue.fixSteps.enumerated() {
                    lines.append("\(i + 1). \(step)")
                }
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Write report to JSON file
    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
}

// MARK: - Validation Checkpoint

/// A checkpoint in the validation video where frames should be extracted
public struct ValidationCheckpoint: Codable, Sendable {
    public let timestamp: Double
    public let effect: String
    public let checkpoint: String?
    public let expectedText: String?
    
    public init(timestamp: Double, effect: String, checkpoint: String? = nil, expectedText: String? = nil) {
        self.timestamp = timestamp
        self.effect = effect
        self.checkpoint = checkpoint
        self.expectedText = expectedText
    }
}

// MARK: - Color Analysis Types

/// RGB color values for analysis
public struct RGBColor: Codable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    
    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
    
    public var luminance: Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}

/// LAB color values for perceptual analysis
public struct LABColor: Codable, Sendable {
    public let L: Double
    public let a: Double
    public let b: Double
    
    public init(L: Double, a: Double, b: Double) {
        self.L = L
        self.a = a
        self.b = b
    }
}

// MARK: - Texture Utilities Extension

extension MTLTexture {
    /// Read pixel data from texture at specific coordinates
    /// Returns RGBA Float values
    public func readPixel(x: Int, y: Int) -> (r: Float, g: Float, b: Float, a: Float)? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        
        // For 16-bit float textures
        if pixelFormat == .rgba16Float {
            var pixel = [UInt16](repeating: 0, count: 4)
            let region = MTLRegion(origin: MTLOrigin(x: x, y: y, z: 0),
                                   size: MTLSize(width: 1, height: 1, depth: 1))
            getBytes(&pixel, bytesPerRow: 8, from: region, mipmapLevel: 0)
            
            // Convert half to float
            let r = Float16(bitPattern: pixel[0])
            let g = Float16(bitPattern: pixel[1])
            let b = Float16(bitPattern: pixel[2])
            let a = Float16(bitPattern: pixel[3])
            
            return (Float(r), Float(g), Float(b), Float(a))
        }
        
        // For 8-bit RGBA textures
        if pixelFormat == .rgba8Unorm {
            var pixel = [UInt8](repeating: 0, count: 4)
            let region = MTLRegion(origin: MTLOrigin(x: x, y: y, z: 0),
                                   size: MTLSize(width: 1, height: 1, depth: 1))
            getBytes(&pixel, bytesPerRow: 4, from: region, mipmapLevel: 0)
            
            return (Float(pixel[0]) / 255.0,
                    Float(pixel[1]) / 255.0,
                    Float(pixel[2]) / 255.0,
                    Float(pixel[3]) / 255.0)
        }
        
        return nil
    }
    
    /// Sample a region and return average color
    public func sampleRegion(x: Int, y: Int, width: Int, height: Int) -> RGBColor? {
        var totalR: Double = 0
        var totalG: Double = 0
        var totalB: Double = 0
        var count: Double = 0
        
        for py in y..<min(y + height, self.height) {
            for px in x..<min(x + width, self.width) {
                if let pixel = readPixel(x: px, y: py) {
                    totalR += Double(pixel.r)
                    totalG += Double(pixel.g)
                    totalB += Double(pixel.b)
                    count += 1
                }
            }
        }
        
        guard count > 0 else { return nil }
        return RGBColor(red: totalR / count, green: totalG / count, blue: totalB / count)
    }
    
    /// Calculate total energy (sum of all pixel luminance)
    public func calculateTotalEnergy() -> Double {
        var totalEnergy: Double = 0
        
        for y in 0..<height {
            for x in 0..<width {
                if let pixel = readPixel(x: x, y: y) {
                    let luminance = 0.2126 * Double(pixel.r) + 0.7152 * Double(pixel.g) + 0.0722 * Double(pixel.b)
                    totalEnergy += luminance
                }
            }
        }
        
        return totalEnergy
    }
}
