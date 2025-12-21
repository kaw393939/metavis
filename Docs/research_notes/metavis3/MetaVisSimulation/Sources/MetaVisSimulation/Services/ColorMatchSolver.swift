import Foundation
import simd

/// Parameters for the Color Grade Node.
/// These are the "knobs" the solver will turn.
/// Matches the Metal struct layout for direct binding.
public struct ColorGradeParams: Codable, Sendable {
    public var exposure: Float = 0
    public var temperature: Float = 0
    public var tint: Float = 0
    public var _pad0: Float = 0
    
    public var slope: SIMD3<Float> = SIMD3(1,1,1)
    public var _pad1: Float = 0 // Padding for float3 alignment
    
    public var offset: SIMD3<Float> = SIMD3(0,0,0)
    public var _pad2: Float = 0
    
    public var power: SIMD3<Float> = SIMD3(1,1,1)
    public var _pad3: Float = 0
    
    public var saturation: Float = 1
    public var contrast: Float = 1
    public var contrastPivot: Float = 0.18
    public var lutIntensity: Float = 0 // 0.0 = Off, 1.0 = Full
    
    public init(
        exposure: Float = 0,
        temperature: Float = 0,
        tint: Float = 0,
        slope: SIMD3<Float> = SIMD3(1,1,1),
        offset: SIMD3<Float> = SIMD3(0,0,0),
        power: SIMD3<Float> = SIMD3(1,1,1),
        saturation: Float = 1,
        contrast: Float = 1,
        contrastPivot: Float = 0.18,
        lutIntensity: Float = 0
    ) {
        self.exposure = exposure
        self.temperature = temperature
        self.tint = tint
        self.slope = slope
        self.offset = offset
        self.power = power
        self.saturation = saturation
        self.contrast = contrast
        self.contrastPivot = contrastPivot
        self.lutIntensity = lutIntensity
    }
    
    public init() {}

    // MARK: - Codable Implementation
    enum CodingKeys: String, CodingKey {
        case exposure, temperature, tint
        case slopeX, slopeY, slopeZ
        case offsetX, offsetY, offsetZ
        case powerX, powerY, powerZ
        case saturation, contrast, contrastPivot, lutIntensity
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        exposure = try container.decode(Float.self, forKey: .exposure)
        temperature = try container.decode(Float.self, forKey: .temperature)
        tint = try container.decode(Float.self, forKey: .tint)
        
        let sx = try container.decode(Float.self, forKey: .slopeX)
        let sy = try container.decode(Float.self, forKey: .slopeY)
        let sz = try container.decode(Float.self, forKey: .slopeZ)
        slope = SIMD3<Float>(sx, sy, sz)
        
        let ox = try container.decode(Float.self, forKey: .offsetX)
        let oy = try container.decode(Float.self, forKey: .offsetY)
        let oz = try container.decode(Float.self, forKey: .offsetZ)
        offset = SIMD3<Float>(ox, oy, oz)
        
        let px = try container.decode(Float.self, forKey: .powerX)
        let py = try container.decode(Float.self, forKey: .powerY)
        let pz = try container.decode(Float.self, forKey: .powerZ)
        power = SIMD3<Float>(px, py, pz)
        
        saturation = try container.decode(Float.self, forKey: .saturation)
        contrast = try container.decode(Float.self, forKey: .contrast)
        contrastPivot = try container.decode(Float.self, forKey: .contrastPivot)
        lutIntensity = try container.decodeIfPresent(Float.self, forKey: .lutIntensity) ?? 0
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(exposure, forKey: .exposure)
        try container.encode(temperature, forKey: .temperature)
        try container.encode(tint, forKey: .tint)
        
        try container.encode(slope.x, forKey: .slopeX)
        try container.encode(slope.y, forKey: .slopeY)
        try container.encode(slope.z, forKey: .slopeZ)
        
        try container.encode(offset.x, forKey: .offsetX)
        try container.encode(offset.y, forKey: .offsetY)
        try container.encode(offset.z, forKey: .offsetZ)
        
        try container.encode(power.x, forKey: .powerX)
        try container.encode(power.y, forKey: .powerY)
        try container.encode(power.z, forKey: .powerZ)
        
        try container.encode(saturation, forKey: .saturation)
        try container.encode(contrast, forKey: .contrast)
        try container.encode(contrastPivot, forKey: .contrastPivot)
        try container.encode(lutIntensity, forKey: .lutIntensity)
    }
}

/// Statistical representation of a frame's color distribution.
public struct ColorStats: Sendable {
    public let averageLuma: Float
    public let averageRGB: SIMD3<Float>
    public let contrast: Float
    public let saturation: Float
    public let histogram: [Float] // Normalized 256-bin histogram
    
    public init(averageLuma: Float, averageRGB: SIMD3<Float>, contrast: Float, saturation: Float, histogram: [Float]) {
        self.averageLuma = averageLuma
        self.averageRGB = averageRGB
        self.contrast = contrast
        self.saturation = saturation
        self.histogram = histogram
    }
}

/// Solves for the best ColorGradeParams to match a source image to a target look.
public struct ColorMatchSolver {
    
    public static func solve(source: ColorStats, target: ColorStats) -> ColorGradeParams {
        var params = ColorGradeParams()
        
        // 1. Match Exposure (Luma)
        // Simple log-space offset
        let exposureOffset = log2(target.averageLuma + 0.001) - log2(source.averageLuma + 0.001)
        params.exposure = exposureOffset
        
        // 2. Match White Balance (Average RGB)
        // Calculate the vector rotation needed to align source white point to target white point
        // This is a simplified approximation using Gain
        let sourceWhite = source.averageRGB / (source.averageRGB.max() + 0.001)
        let targetWhite = target.averageRGB / (target.averageRGB.max() + 0.001)
        
        // If source is "warmer" (more red) than target, we need to cool it down.
        // Gain = Target / Source
        params.slope = SIMD3<Float>(
            targetWhite.x / (sourceWhite.x + 0.001),
            targetWhite.y / (sourceWhite.y + 0.001),
            targetWhite.z / (sourceWhite.z + 0.001)
        )
        
        // 3. Match Contrast
        // Ratio of standard deviations (approximated here by pre-calculated contrast)
        params.contrast = target.contrast / (source.contrast + 0.001)
        
        // 4. Match Saturation
        params.saturation = target.saturation / (source.saturation + 0.001)
        
        return params
    }
}
