import Foundation
import Metal

// MARK: - Data Schemas for Local Image Generation Module (LIGM)

/// Color space specification for generated images
/// Default: ACEScg (ACES Color Space for Computer Graphics)
public enum LIGMColorSpace: String, Codable {
    case acesCg = "ACEScg"
    case sRGB = "sRGB"
    case rec2020 = "Rec.2020"
    case lab = "CIELAB"
}

/// Backend type for image generation
public enum LIGMBackendType: String, Codable {
    case procedural = "procedural"
    case coreml = "coreml"
    case mlx = "mlx"
}

/// Generation mode specifying the type of content to generate
public enum LIGMMode: String, Codable {
    case noise = "noise"
    case texture = "texture"
    case ml = "ml"
    case sdf = "sdf"
    case hubblePreprocess = "hubblePreprocess"
    case gradient = "gradient"
    case fbm = "fbm"
    case domainWarp = "domainWarp"
}

/// Request structure for LIGM image generation
public struct LIGMRequest: Codable {
    /// Unique identifier for this generation request
    public let id: String
    
    /// Output image width in pixels
    public let width: Int
    
    /// Output image height in pixels
    public let height: Int
    
    /// Random seed for deterministic generation
    public let seed: UInt64
    
    /// Generation mode
    public let mode: LIGMMode
    
    /// Backend-specific parameters (e.g., octaves, lacunarity, frequency)
    public let parameters: [String: Float]
    
    /// Optional text prompt for ML backend
    public let prompt: String?
    
    /// Target color space (default: ACEScg)
    public let colorSpace: LIGMColorSpace
    
    /// Optional backend override (default: auto-select)
    public let forceBackend: LIGMBackendType?
    
    /// Optional output path for saving result
    public let outputPath: String?
    
    public init(
        id: String,
        width: Int,
        height: Int,
        seed: UInt64,
        mode: LIGMMode,
        parameters: [String: Float] = [:],
        prompt: String? = nil,
        colorSpace: LIGMColorSpace = .acesCg,
        forceBackend: LIGMBackendType? = nil,
        outputPath: String? = nil
    ) {
        self.id = id
        self.width = width
        self.height = height
        self.seed = seed
        self.mode = mode
        self.parameters = parameters
        self.prompt = prompt
        self.colorSpace = colorSpace
        self.forceBackend = forceBackend
        self.outputPath = outputPath
    }
}

/// Metadata about the generation process
public struct LIGMMetadata: Codable {
    /// Backend that was used for generation
    public let backendUsed: LIGMBackendType
    
    /// Generation time in milliseconds
    public let generationTimeMS: Double
    
    /// Random seed used
    public let seed: UInt64
    
    /// Output color space
    public let colorSpace: String
    
    /// Hardware accelerator used (ANE, AMX, GPU, CPU)
    public let hardwareAccelerator: String
    
    /// Whether generation was deterministic
    public let isDeterministic: Bool
    
    /// Optional model name/version for ML backends
    public let modelName: String?
    
    /// Generation parameters used
    public let parameters: [String: Float]
    
    public init(
        backendUsed: LIGMBackendType,
        generationTimeMS: Double,
        seed: UInt64,
        colorSpace: String,
        hardwareAccelerator: String,
        isDeterministic: Bool,
        modelName: String? = nil,
        parameters: [String: Float] = [:]
    ) {
        self.backendUsed = backendUsed
        self.generationTimeMS = generationTimeMS
        self.seed = seed
        self.colorSpace = colorSpace
        self.hardwareAccelerator = hardwareAccelerator
        self.isDeterministic = isDeterministic
        self.modelName = modelName
        self.parameters = parameters
    }
}

/// Response structure containing generated image and metadata
public struct LIGMResponse {
    /// Request ID that this response corresponds to
    public let id: String
    
    /// Generated Metal texture (RGBA16Float in ACEScg-linear)
    public let texture: MTLTexture
    
    /// Generation metadata
    public let metadata: LIGMMetadata
    
    /// Optional pixel data for CPU access
    public let pixelData: [Float]?
    
    public init(
        id: String,
        texture: MTLTexture,
        metadata: LIGMMetadata,
        pixelData: [Float]? = nil
    ) {
        self.id = id
        self.texture = texture
        self.metadata = metadata
        self.pixelData = pixelData
    }
}

/// Error types for LIGM operations
public enum LIGMError: Error {
    case invalidDimensions(width: Int, height: Int)
    case backendUnavailable(LIGMBackendType)
    case modelNotFound(String)
    case colorSpaceConversionFailed
    case textureCreationFailed
    case deterministicGenerationFailed
    case invalidParameters([String: Float])
    case hardwareAcceleratorUnavailable(String)
    case outputPathInvalid(String)
    
    public var localizedDescription: String {
        switch self {
        case .invalidDimensions(let w, let h):
            return "Invalid dimensions: \(w)x\(h). Must be > 0 and < 16384."
        case .backendUnavailable(let backend):
            return "Backend '\(backend.rawValue)' is not available on this system."
        case .modelNotFound(let name):
            return "ML model '\(name)' not found in bundle or local storage."
        case .colorSpaceConversionFailed:
            return "Failed to convert between color spaces. Check AMX availability."
        case .textureCreationFailed:
            return "Failed to create Metal texture. Check GPU availability."
        case .deterministicGenerationFailed:
            return "Generation produced non-deterministic output. This violates LIGM requirements."
        case .invalidParameters(let params):
            return "Invalid parameters for generation mode: \(params)"
        case .hardwareAcceleratorUnavailable(let hw):
            return "Required hardware accelerator '\(hw)' is unavailable."
        case .outputPathInvalid(let path):
            return "Output path is invalid or not writable: \(path)"
        }
    }
}

/// Backend protocol that all LIGM backends must implement
public protocol LIGMBackend {
    /// Backend identifier
    var backendType: LIGMBackendType { get }
    
    /// Check if this backend is available on current hardware
    var isAvailable: Bool { get }
    
    /// Check if this backend can handle the requested mode
    func canHandle(mode: LIGMMode) -> Bool
    
    /// Generate image according to request
    /// - Parameter request: Generation request
    /// - Parameter device: Metal device for texture creation
    /// - Returns: Generated response with texture and metadata
    func generate(request: LIGMRequest, device: MTLDevice) async throws -> LIGMResponse
}

/// Manifest integration structure for dynamic asset generation
public struct LIGMManifestAsset: Codable {
    public let id: String
    public let generate: LIGMGenerateSpec
    
    public struct LIGMGenerateSpec: Codable {
        public let backend: String?
        public let prompt: String?
        public let size: [Int]
        public let seed: UInt64
        public let mode: String?
        public let parameters: [String: Float]?
        
        public init(
            backend: String? = nil,
            prompt: String? = nil,
            size: [Int],
            seed: UInt64,
            mode: String? = nil,
            parameters: [String: Float]? = nil
        ) {
            self.backend = backend
            self.prompt = prompt
            self.size = size
            self.seed = seed
            self.mode = mode
            self.parameters = parameters
        }
    }
    
    public init(id: String, generate: LIGMGenerateSpec) {
        self.id = id
        self.generate = generate
    }
}
