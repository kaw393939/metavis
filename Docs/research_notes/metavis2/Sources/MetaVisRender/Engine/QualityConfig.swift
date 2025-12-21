import Foundation
import simd

/// Defines the fidelity tier for the rendering engine.
public enum MVQualityMode: UInt32, CaseIterable {
    case realtime = 0
    case cinema = 1
    case lab = 2
}

/// Configuration struct that controls shader loop counts and quality parameters.
/// Must match `MVQualitySettings` in `Core/QualitySettings.metal`.
public struct MVQualitySettings {
    public var mode: UInt32
    
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
    public var temporalShutterCurve: UInt32 // 0: box, 1: Gaussian
    public var temporalResponseSpeed: Float
    
    // Tone mapping / grading
    public var toneMappingMode: UInt32
    public var gradingLUTResolution: UInt32
    
    // Grain
    public var grainResolutionScale: Float
    public var grainBlueNoiseEnabled: UInt32
    
    // Reserved (Padding to 16-byte alignment if needed, though Metal struct alignment rules apply)
    public var reserved0: SIMD4<Float>
    public var reserved1: SIMD4<Float>
    
    public init(mode: MVQualityMode) {
        self.mode = mode.rawValue
        self.reserved0 = .zero
        self.reserved1 = .zero
        
        switch mode {
        case .realtime:
            self.blurBaseRadius = 1.0
            self.blurMaxRadius = 16.0
            self.blurTapCount = 3
            self.bloomMipLevels = 4
            self.halationRadius = 0.0 // Disabled
            self.anamorphicStreakSamples = 0 // Disabled
            
            self.volumetricSteps = 12
            self.volumetricJitterStrength = 0.0
            
            self.temporalMaxSamples = 4
            self.temporalShutterCurve = 0 // Box
            self.temporalResponseSpeed = 0.8
            
            self.toneMappingMode = 0 // ACES
            self.gradingLUTResolution = 16
            
            self.grainResolutionScale = 0.5
            self.grainBlueNoiseEnabled = 0
            
        case .cinema:
            self.blurBaseRadius = 1.0
            self.blurMaxRadius = 32.0
            self.blurTapCount = 7
            self.bloomMipLevels = 6
            self.halationRadius = 2.0
            self.anamorphicStreakSamples = 16
            
            self.volumetricSteps = 24
            self.volumetricJitterStrength = 0.5
            
            self.temporalMaxSamples = 8
            self.temporalShutterCurve = 1 // Gaussian
            self.temporalResponseSpeed = 0.5
            
            self.toneMappingMode = 0 // ACES
            self.gradingLUTResolution = 32
            
            self.grainResolutionScale = 1.0
            self.grainBlueNoiseEnabled = 1
            
        case .lab:
            self.blurBaseRadius = 1.0
            self.blurMaxRadius = 64.0
            self.blurTapCount = 11
            self.bloomMipLevels = 8
            self.halationRadius = 4.0
            self.anamorphicStreakSamples = 32
            
            self.volumetricSteps = 48
            self.volumetricJitterStrength = 1.0
            
            self.temporalMaxSamples = 16
            self.temporalShutterCurve = 1 // Gaussian
            self.temporalResponseSpeed = 0.1
            
            self.toneMappingMode = 0 // ACES
            self.gradingLUTResolution = 64
            
            self.grainResolutionScale = 1.0
            self.grainBlueNoiseEnabled = 1
        }
    }
}
