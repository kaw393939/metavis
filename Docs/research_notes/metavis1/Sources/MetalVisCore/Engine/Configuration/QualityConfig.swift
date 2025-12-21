import Foundation
import simd

public enum MVQualityMode: UInt32 {
    case realtime = 0   // lowest cost, good quality
    case cinema  = 1    // higher quality for normal use
    case lab     = 2    // maximum quality, M2/M3 render
}

public struct MVPlatformProfile {
    public var isAppleSilicon: Bool
    public var gpuClass: UInt32    // 0: low, 1: mid, 2: high (M1, M2, M3 tiers)
    public var supportsM3Features: Bool
    public var maxRenderResolution: SIMD2<UInt32>
    
    public init(isAppleSilicon: Bool = true, 
                gpuClass: UInt32 = 1, 
                supportsM3Features: Bool = false, 
                maxRenderResolution: SIMD2<UInt32> = SIMD2<UInt32>(3840, 2160)) {
        self.isAppleSilicon = isAppleSilicon
        self.gpuClass = gpuClass
        self.supportsM3Features = supportsM3Features
        self.maxRenderResolution = maxRenderResolution
    }
}

public struct MVQualitySettings {
    public var mode: UInt32      // MVQualityMode rawValue

    // Blur / Bloom / Halation / Anamorphic
    public var blurBaseRadius: Float
    public var blurMaxRadius: Float
    public var blurTapCount: UInt32
    public var bloomMipLevels: UInt32
    public var halationRadius: Float
    public var anamorphicStreakSamples: UInt32

    // Volumetric
    public var volumetricSteps: UInt32
    public var volumetricJitterStrength: Float

    // Temporal
    public var temporalMaxSamples: UInt32
    public var temporalShutterCurve: UInt32  // 0: box, 1: Gaussian
    public var temporalResponseSpeed: Float  // for EMA, if applicable

    // Tone mapping / grading
    public var toneMappingMode: UInt32       // 0: ACES, 1: FilmicCustom
    public var gradingLUTResolution: UInt32  // 16/32/etc, if using LUTs

    // Grain
    public var grainResolutionScale: Float   // 1.0 = full res, 0.5 = half res
    public var grainBlueNoiseEnabled: UInt32 // 0/1

    // Reserved for future (pad to multiple of 16 bytes for Metal)
    public var reserved0: SIMD4<Float>
    public var reserved1: SIMD4<Float>
    
    public init(mode: MVQualityMode) {
        self.mode = mode.rawValue
        self.reserved0 = SIMD4<Float>(0,0,0,0)
        self.reserved1 = SIMD4<Float>(0,0,0,0)
        
        switch mode {
        case .realtime:
            self.blurBaseRadius = 4.0
            self.blurMaxRadius = 32.0
            self.blurTapCount = 7
            self.bloomMipLevels = 4
            self.halationRadius = 4.0
            self.anamorphicStreakSamples = 16
            self.volumetricSteps = 12
            self.volumetricJitterStrength = 0.0
            self.temporalMaxSamples = 4
            self.temporalShutterCurve = 0
            self.temporalResponseSpeed = 0.1
            self.toneMappingMode = 0
            self.gradingLUTResolution = 16
            self.grainResolutionScale = 0.5
            self.grainBlueNoiseEnabled = 0
            
        case .cinema:
            self.blurBaseRadius = 5.0
            self.blurMaxRadius = 64.0
            self.blurTapCount = 13
            self.bloomMipLevels = 6
            self.halationRadius = 5.0
            self.anamorphicStreakSamples = 32
            self.volumetricSteps = 24
            self.volumetricJitterStrength = 0.5
            self.temporalMaxSamples = 8
            self.temporalShutterCurve = 1
            self.temporalResponseSpeed = 0.05
            self.toneMappingMode = 0
            self.gradingLUTResolution = 32
            self.grainResolutionScale = 1.0
            self.grainBlueNoiseEnabled = 1
            
        case .lab:
            self.blurBaseRadius = 6.0
            self.blurMaxRadius = 128.0
            self.blurTapCount = 25
            self.bloomMipLevels = 8
            self.halationRadius = 6.0
            self.anamorphicStreakSamples = 64
            self.volumetricSteps = 48
            self.volumetricJitterStrength = 1.0
            self.temporalMaxSamples = 16
            self.temporalShutterCurve = 1
            self.temporalResponseSpeed = 0.02
            self.toneMappingMode = 0
            self.gradingLUTResolution = 32
            self.grainResolutionScale = 1.0
            self.grainBlueNoiseEnabled = 1
        }
    }
}
