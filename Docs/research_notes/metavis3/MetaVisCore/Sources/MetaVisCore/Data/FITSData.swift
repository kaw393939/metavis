import Foundation

/// Statistics computed from the raw FITS data buffer.
/// Used for auto-stretching and data analysis.
public struct FITSStatistics: Codable, Sendable {
    public let min: Float
    public let max: Float
    public let mean: Float
    public let median: Float?
    public let stdDev: Float?
    public let percentiles: [Int: Float] // e.g., 1: val, 99: val
    
    public init(min: Float, max: Float, mean: Float, median: Float? = nil, stdDev: Float? = nil, percentiles: [Int: Float] = [:]) {
        self.min = min
        self.max = max
        self.mean = mean
        self.median = median
        self.stdDev = stdDev
        self.percentiles = percentiles
    }
}

/// Represents a loaded FITS image asset (likely from JWST or similar).
/// This structure holds metadata and a reference to the raw data (which might be large).
/// Note: The actual heavy buffer might be managed separately or via URL to avoid copying.
public struct FITSAsset: Identifiable, Sendable {
    public let id: UUID
    public let url: URL
    
    // Geometry
    public let width: Int
    public let height: Int
    public var pixelCount: Int { width * height }
    
    // FITS Specifics
    public let bitpix: Int // Expected -32 for float
    public let metadata: [String: String] // FILTER, INSTRUME, TELESCOP
    
    // Stats
    public let statistics: FITSStatistics
    
    // The raw data. 
    // In a real system, we might use a Data provider or mapped memory.
    // For now, we assume it's loaded into a Float array.
    // Using UnsafeBufferPointer is tricky for Sendable unless we manager ownership carefully.
    // We will use `Data` for the storage backing, which is Sendable.
    public let rawData: Data 
    
    public init(
        id: UUID = UUID(),
        url: URL,
        width: Int,
        height: Int,
        bitpix: Int,
        metadata: [String: String],
        statistics: FITSStatistics,
        rawData: Data
    ) {
        self.id = id
        self.url = url
        self.width = width
        self.height = height
        self.bitpix = bitpix
        self.metadata = metadata
        self.statistics = statistics
        self.rawData = rawData
    }
}

// MARK: - Configuration Structures

public enum StretchOperator: String, Codable, Sendable {
    case linear
    case log
    case asinh
    case sigmoid
    case custom
}

public struct StretchParams: Codable, Sendable {
    public var gain: Float
    public var offset: Float
    public var softKnee: Float // For sigmoid
    public var epsilon: Float  // Stability
    
    public init(gain: Float = 1.0, offset: Float = 0.0, softKnee: Float = 0.5, epsilon: Float = 1e-5) {
        self.gain = gain
        self.offset = offset
        self.softKnee = softKnee
        self.epsilon = epsilon
    }
}

/// Configuration for processing a single monochromatic FITS channel.
public struct FITSChannelConfig: Identifiable, Codable, Sendable {
    public var id: UUID { assetID }
    public let assetID: UUID
    
    // Pre-stretch
    public var exposureScale: Float
    public var blackPoint: Float
    public var whitePoint: Float
    
    // Stretch
    public var stretchOperator: StretchOperator
    public var stretchParams: StretchParams
    
    // Post-stretch
    public var gamma: Float
    public var enabled: Bool
    
    public init(
        assetID: UUID,
        exposureScale: Float = 1.0,
        blackPoint: Float = 0.0,
        whitePoint: Float = 1.0,
        stretchOperator: StretchOperator = .linear,
        stretchParams: StretchParams = StretchParams(),
        gamma: Float = 1.0,
        enabled: Bool = true
    ) {
        self.assetID = assetID
        self.exposureScale = exposureScale
        self.blackPoint = blackPoint
        self.whitePoint = whitePoint
        self.stretchOperator = stretchOperator
        self.stretchParams = stretchParams
        self.gamma = gamma
        self.enabled = enabled
    }
}

public struct StarMaskConfig: Codable, Sendable {
    public var threshold: Float
    public var softThreshold: Float
    public var dilationRadius: Int
    public var psfIntensityClamp: Float
    public var haloSuppressionStrength: Float
    public var enable: Bool
    
    public init(
        threshold: Float = 0.8,
        softThreshold: Float = 0.6,
        dilationRadius: Int = 2,
        psfIntensityClamp: Float = 5.0,
        haloSuppressionStrength: Float = 0.5,
        enable: Bool = false
    ) {
        self.threshold = threshold
        self.softThreshold = softThreshold
        self.dilationRadius = dilationRadius
        self.psfIntensityClamp = psfIntensityClamp
        self.haloSuppressionStrength = haloSuppressionStrength
        self.enable = enable
    }
}

public struct EdgeEnhanceConfig: Codable, Sendable {
    public var amount: Float
    public var radius: Float
    public var preserveEnergy: Bool
    public var enable: Bool
    
    public init(amount: Float = 0.5, radius: Float = 1.0, preserveEnergy: Bool = true, enable: Bool = false) {
        self.amount = amount
        self.radius = radius
        self.preserveEnergy = preserveEnergy
        self.enable = enable
    }
}

/// Master configuration for compositing up to 3 channels into an ACEScg image.
public struct FITSCompositeConfig: Codable, Sendable {
    // Channels
    public var red: FITSChannelConfig
    public var green: FITSChannelConfig
    public var blue: FITSChannelConfig
    
    // Global Effects
    public var starMaskConfig: StarMaskConfig
    public var edgeEnhanceConfig: EdgeEnhanceConfig
    
    // Global Grading
    public var outputExposure: Float
    public var outputContrast: Float
    public var outputSaturation: Float
    public var outputGamma: Float
    
    public init(
        red: FITSChannelConfig,
        green: FITSChannelConfig,
        blue: FITSChannelConfig,
        starMaskConfig: StarMaskConfig = StarMaskConfig(),
        edgeEnhanceConfig: EdgeEnhanceConfig = EdgeEnhanceConfig(),
        outputExposure: Float = 1.0,
        outputContrast: Float = 1.0,
        outputSaturation: Float = 1.0,
        outputGamma: Float = 1.0
    ) {
        self.red = red
        self.green = green
        self.blue = blue
        self.starMaskConfig = starMaskConfig
        self.edgeEnhanceConfig = edgeEnhanceConfig
        self.outputExposure = outputExposure
        self.outputContrast = outputContrast
        self.outputSaturation = outputSaturation
        self.outputGamma = outputGamma
    }
}
