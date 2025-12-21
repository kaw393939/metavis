import Foundation

/// Statistics computed from a FITS raster.
/// Primarily used for auto-stretching and analysis.
public struct FITSStatistics: Codable, Sendable, Equatable {
    public let min: Float
    public let max: Float
    public let mean: Float
    public let median: Float?
    public let stdDev: Float?
    public let percentiles: [Int: Float]

    public init(
        min: Float,
        max: Float,
        mean: Float,
        median: Float? = nil,
        stdDev: Float? = nil,
        percentiles: [Int: Float] = [:]
    ) {
        self.min = min
        self.max = max
        self.mean = mean
        self.median = median
        self.stdDev = stdDev
        self.percentiles = percentiles
    }
}

/// Represents a loaded FITS image asset (e.g. JWST products).
/// Holds parsed header metadata and the converted little-endian pixel buffer.
public struct FITSAsset: Identifiable, Sendable {
    public let id: UUID
    public let url: URL

    public let width: Int
    public let height: Int
    public var pixelCount: Int { width * height }

    /// FITS BITPIX value (e.g. -32 for Float32, 16 for Int16).
    public let bitpix: Int

    /// Header keyword/value pairs from the chosen image HDU.
    public let metadata: [String: String]

    public let statistics: FITSStatistics

    /// Pixel payload after endianness conversion.
    /// For BITPIX = -32, this is little-endian Float32.
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

// MARK: - Optional processing configuration (ported foundation)

public enum StretchOperator: String, Codable, Sendable {
    case linear
    case log
    case asinh
    case sigmoid
    case custom
}

public struct StretchParams: Codable, Sendable, Equatable {
    public var gain: Float
    public var offset: Float
    public var softKnee: Float
    public var epsilon: Float

    public init(gain: Float = 1.0, offset: Float = 0.0, softKnee: Float = 0.5, epsilon: Float = 1e-5) {
        self.gain = gain
        self.offset = offset
        self.softKnee = softKnee
        self.epsilon = epsilon
    }
}

public struct FITSChannelConfig: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID { assetID }
    public let assetID: UUID

    public var exposureScale: Float
    public var blackPoint: Float
    public var whitePoint: Float

    public var stretchOperator: StretchOperator
    public var stretchParams: StretchParams

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

public struct StarMaskConfig: Codable, Sendable, Equatable {
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

public struct EdgeEnhanceConfig: Codable, Sendable, Equatable {
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

public struct FITSCompositeConfig: Codable, Sendable, Equatable {
    public var red: FITSChannelConfig
    public var green: FITSChannelConfig
    public var blue: FITSChannelConfig

    public var starMaskConfig: StarMaskConfig
    public var edgeEnhanceConfig: EdgeEnhanceConfig

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
