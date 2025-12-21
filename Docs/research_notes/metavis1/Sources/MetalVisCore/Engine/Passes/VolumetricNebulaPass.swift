import Metal
import simd

/// True 3D volumetric nebula rendering pass using raymarching.
/// This replaces the layered media_plane approach with physically-based volume rendering.
///
/// Features:
/// - Adaptive step raymarching through FBM density field
/// - Self-shadowing via shadow rays
/// - Henyey-Greenstein phase function for anisotropic scattering
/// - Emission model for self-illuminating gas
/// - Energy-conserving integration
///
public class VolumetricNebulaPass: RenderPass {
    public var label: String = "Volumetric Nebula"
    public var inputs: [String] = ["depth_buffer"]
    public var outputs: [String] = ["volumetric_nebula_buffer"]
    
    private var pipelineState: MTLComputePipelineState?
    private var compositePipeline: MTLComputePipelineState?
    private let scene: Scene
    
    // MARK: - Volume Parameters
    
    /// Bounding box min (world space)
    public var volumeMin: SIMD3<Float> = SIMD3<Float>(-15, -8, -25)
    
    /// Bounding box max (world space)
    public var volumeMax: SIMD3<Float> = SIMD3<Float>(15, 8, 5)
    
    // MARK: - Density Field
    
    /// Base frequency of FBM noise
    public var baseFrequency: Float = 0.5
    
    /// Number of FBM octaves
    public var octaves: Int = 6
    
    /// Frequency multiplier per octave
    public var lacunarity: Float = 2.0
    
    /// Amplitude multiplier per octave
    public var gain: Float = 0.5
    
    /// Overall density multiplier
    public var densityScale: Float = 1.0
    
    /// Density offset (shifts the noise range)
    public var densityOffset: Float = 0.0
    
    // MARK: - Animation
    
    /// Wind velocity for animating the density field
    public var windVelocity: SIMD3<Float> = SIMD3<Float>(0.02, 0.01, 0)
    
    // MARK: - Lighting
    
    /// Direction light comes FROM (will be normalized)
    public var lightDirection: SIMD3<Float> = SIMD3<Float>(0.5, -0.5, -1.0)
    
    /// Light color (linear, can be HDR)
    public var lightColor: SIMD3<Float> = SIMD3<Float>(1.0, 0.95, 0.9)
    
    /// Ambient light intensity
    public var ambientIntensity: Float = 0.05
    
    // MARK: - Scattering
    
    /// Scattering coefficient (how much light is scattered)
    public var scatteringCoeff: Float = 0.3
    
    /// Absorption coefficient (how much light is absorbed)
    public var absorptionCoeff: Float = 0.1
    
    /// Henyey-Greenstein asymmetry parameter (-1 = back, 0 = isotropic, 1 = forward)
    public var phaseG: Float = 0.3
    
    // MARK: - Quality
    
    /// Maximum raymarch steps
    public var maxSteps: Int = 128
    
    /// Shadow ray steps
    public var shadowSteps: Int = 16
    
    /// Step size in world units
    public var stepSize: Float = 0.1
    
    // MARK: - Color
    
    /// Emission color for hot/dense regions
    public var emissionColorWarm: SIMD3<Float> = SIMD3<Float>(1.0, 0.5, 0.1)
    
    /// Emission color for cool/sparse regions
    public var emissionColorCool: SIMD3<Float> = SIMD3<Float>(0.1, 0.3, 0.8)
    
    /// Emission intensity multiplier
    public var emissionIntensity: Float = 0.5
    
    /// HDR scale for output
    public var hdrScale: Float = 2.0
    
    /// Color gradient for density mapping (optional)
    public var colorGradient: [(color: SIMD3<Float>, position: Float)] = []
    
    // MARK: - Initialization
    
    public init(device: MTLDevice, scene: Scene) {
        self.scene = scene
    }
    
    // MARK: - Execution
    
    public func execute(context: RenderContext,
                        inputTextures: [String: MTLTexture],
                        outputTextures: [String: MTLTexture]) throws {
        
        if pipelineState == nil {
            try buildPipeline(device: context.device)
        }
        
        guard let pipeline = pipelineState,
              let depthTexture = inputTextures["depth_buffer"],
              let outputTexture = outputTextures[outputs[0]] else {
            print("VolumetricNebulaPass: Missing textures")
            return
        }
        
        guard let encoder = context.commandBuffer.makeComputeCommandEncoder() else {
            return
        }
        
        encoder.label = label
        encoder.setComputePipelineState(pipeline)
        
        encoder.setTexture(depthTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        
        // Build params struct
        // NOTE: This struct MUST match the Metal struct layout exactly.
        // Using explicit padding to match float3 alignment (16 bytes in Metal).
        let camera = scene.camera
        let aspectRatio = Float(outputTexture.width) / Float(outputTexture.height)
        
        struct VolumetricNebulaParams {
            // Camera (each SIMD3 + padding = 16 bytes)
            var cameraPosition: SIMD3<Float>
            var _pad0: Float
            var cameraForward: SIMD3<Float>
            var _pad1: Float
            var cameraUp: SIMD3<Float>
            var _pad2: Float
            var cameraRight: SIMD3<Float>
            var _pad3: Float
            var fov: Float
            var aspectRatio: Float
            var _pad4: SIMD2<Float> // Align to 16 bytes
            
            // Volume Bounds (AABB)
            var volumeMin: SIMD3<Float>
            var _pad5: Float
            var volumeMax: SIMD3<Float>
            var _pad6: Float
            
            // Density Field
            var baseFrequency: Float
            var octaves: Int32
            var lacunarity: Float
            var gain: Float
            var densityScale: Float
            var densityOffset: Float
            var _pad7: SIMD2<Float> // Align to 16 bytes
            
            // Animation
            var time: Float
            var _pad8: SIMD3<Float> // Align to 16 bytes
            var windVelocity: SIMD3<Float>
            var _pad9: Float
            
            // Lighting
            var lightDirection: SIMD3<Float>
            var _pad10: Float
            var lightColor: SIMD3<Float>
            var ambientIntensity: Float
            
            // Scattering
            var scatteringCoeff: Float
            var absorptionCoeff: Float
            var phaseG: Float
            var _pad11: Float
            
            // Quality
            var maxSteps: Int32
            var shadowSteps: Int32
            var stepSize: Float
            var _pad12: Float
            
            // Color
            var emissionColorWarm: SIMD3<Float>
            var _pad13: Float
            var emissionColorCool: SIMD3<Float>
            var _pad14: Float
            var emissionIntensity: Float
            var hdrScale: Float
            var _pad15: SIMD2<Float> // Final alignment
        }
        
        // Get camera vectors
        let cameraUniforms = camera.getUniforms(aspectRatio: aspectRatio)
        let viewMatrix = cameraUniforms.viewMatrix
        
        // Extract camera vectors from view matrix (inverse of view)
        let cameraRight = SIMD3<Float>(viewMatrix.columns.0.x, viewMatrix.columns.1.x, viewMatrix.columns.2.x)
        let cameraUp = SIMD3<Float>(viewMatrix.columns.0.y, viewMatrix.columns.1.y, viewMatrix.columns.2.y)
        let cameraForward = -SIMD3<Float>(viewMatrix.columns.0.z, viewMatrix.columns.1.z, viewMatrix.columns.2.z)
        
        var params = VolumetricNebulaParams(
            cameraPosition: camera.position,
            _pad0: 0,
            cameraForward: cameraForward,
            _pad1: 0,
            cameraUp: cameraUp,
            _pad2: 0,
            cameraRight: cameraRight,
            _pad3: 0,
            fov: camera.fieldOfView,
            aspectRatio: aspectRatio,
            _pad4: .zero,
            volumeMin: volumeMin,
            _pad5: 0,
            volumeMax: volumeMax,
            _pad6: 0,
            baseFrequency: baseFrequency,
            octaves: Int32(octaves),
            lacunarity: lacunarity,
            gain: gain,
            densityScale: densityScale,
            densityOffset: densityOffset,
            _pad7: .zero,
            time: Float(context.time),
            _pad8: .zero,
            windVelocity: windVelocity,
            _pad9: 0,
            lightDirection: normalize(lightDirection),
            _pad10: 0,
            lightColor: lightColor,
            ambientIntensity: ambientIntensity,
            scatteringCoeff: scatteringCoeff,
            absorptionCoeff: absorptionCoeff,
            phaseG: phaseG,
            _pad11: 0,
            maxSteps: Int32(maxSteps),
            shadowSteps: Int32(shadowSteps),
            stepSize: stepSize,
            _pad12: 0,
            emissionColorWarm: emissionColorWarm,
            _pad13: 0,
            emissionColorCool: emissionColorCool,
            _pad14: 0,
            emissionIntensity: emissionIntensity,
            hdrScale: hdrScale,
            _pad15: .zero
        )
        
        encoder.setBytes(&params, length: MemoryLayout<VolumetricNebulaParams>.stride, index: 0)
        
        // Color gradient (if provided)
        struct GradientStop3D {
            var color: SIMD3<Float>
            var position: Float
        }
        
        var gradientStops: [GradientStop3D] = colorGradient.map {
            GradientStop3D(color: $0.color, position: $0.position)
        }
        
        if gradientStops.isEmpty {
            // Default gradient
            gradientStops = [
                GradientStop3D(color: SIMD3<Float>(0.1, 0.2, 0.5), position: 0.0),
                GradientStop3D(color: SIMD3<Float>(0.8, 0.4, 0.1), position: 1.0)
            ]
        }
        
        encoder.setBytes(&gradientStops, length: MemoryLayout<GradientStop3D>.stride * gradientStops.count, index: 1)
        var gradientCount = Int32(gradientStops.count)
        encoder.setBytes(&gradientCount, length: MemoryLayout<Int32>.size, index: 2)
        
        // Dispatch
        let w = pipeline.threadExecutionWidth
        let h = pipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerGroup = MTLSizeMake(w, h, 1)
        let threadsPerGrid = MTLSizeMake(outputTexture.width, outputTexture.height, 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
    }
    
    private func buildPipeline(device: MTLDevice) throws {
        let library = ShaderLibrary(device: device)
        
        // Try to load the shader
        if (try? library.makeFunction(name: "fx_volumetric_nebula")) == nil {
            try? library.loadSource(resource: "VolumetricNebula")
        }
        
        let function = try library.makeFunction(name: "fx_volumetric_nebula")
        self.pipelineState = try device.makeComputePipelineState(function: function)
        
        // Composite pipeline
        if let compositeFunc = try? library.makeFunction(name: "fx_volumetric_composite") {
            self.compositePipeline = try device.makeComputePipelineState(function: compositeFunc)
        }
    }
}

// MARK: - Quality Presets

extension VolumetricNebulaPass {
    
    /// Apply quality preset
    public func applyQualityPreset(_ quality: MVQualityMode) {
        switch quality {
        case .realtime:
            maxSteps = 64
            shadowSteps = 8
            stepSize = 0.2
            octaves = 4
            
        case .cinema:
            maxSteps = 128
            shadowSteps = 16
            stepSize = 0.1
            octaves = 6
            
        case .lab:
            maxSteps = 256
            shadowSteps = 32
            stepSize = 0.05
            octaves = 8
        }
    }
    
    /// Configure for Carina-like nebula appearance
    public func configureForCarinaNebula() {
        // Colors inspired by JWST Carina Nebula
        emissionColorWarm = SIMD3<Float>(1.0, 0.5, 0.1)    // Warm orange
        emissionColorCool = SIMD3<Float>(0.2, 0.4, 1.0)    // Bright blue
        emissionIntensity = 12.0    // MUCH stronger emission!
        hdrScale = 2.0
        
        // Density
        baseFrequency = 1.0
        octaves = 4
        lacunarity = 2.0
        gain = 0.5
        densityScale = 1.5
        densityOffset = 0.0
        
        // Low scattering for clean look
        scatteringCoeff = 0.03
        absorptionCoeff = 0.01
        phaseG = 0.2
        
        // Lighting
        lightColor = SIMD3<Float>(1.0, 0.95, 0.9)
        ambientIntensity = 0.05
        
        // Quality
        stepSize = 0.1
        maxSteps = 100
        shadowSteps = 6
        
        // Animation
        windVelocity = SIMD3<Float>(0.01, 0.005, 0.0)
    }
}
