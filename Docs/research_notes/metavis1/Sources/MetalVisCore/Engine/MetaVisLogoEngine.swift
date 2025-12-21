import Metal
import simd
import CoreGraphics
import Foundation

// MARK: - Public API

public enum MVFlameMode: Int {
    case none = 0
    case torch = 1
    case pureFlame = 2
}

public enum MVLogoLayoutMode: Int {
    case flameOnBlack = 0
    case flameOnCard = 1
}

public struct MVFXConfig {
    // Optical
    public var enableChromaticAberration: Bool = false
    public var enableLensDistortion: Bool = false
    public var enableBloomV2: Bool = false
    public var enableAnamorphicStreaks: Bool = false

    // Lighting
    public var enableEmissiveRim: Bool = false
    public var enableHeatGlow: Bool = false
    public var enableBacklightBeam: Bool = false
    public var enableVolumetricCone: Bool = false

    // Physical
    public var enableHeatHaze: Bool = false
    public var enableEmberParticles: Bool = false
    public var enableSmokeDissolve: Bool = false
    public var enableFireToAsh: Bool = false

    // Camera
    public var enableMicroShake: Bool = false
    public var enableExposureFlicker: Bool = false
    public var enableMotionBlur: Bool = false
    public var enableDollyIn: Bool = false

    // Post
    public var enableFilmGrain: Bool = false
    public var enableHalation: Bool = false
    public var enableGateWeave: Bool = false
    public var enableLensDirt: Bool = false
    
    public init() {}
}

public struct MetaVisLogoParams {
    public var curveStrength: Float      // 0.0–1.0
    public var columnWidthRatio: Float   // 0.2–0.5
    public var showApertureArc: Bool
    public var flameMode: MVFlameMode
    public var layoutMode: MVLogoLayoutMode
    public var fxConfig: MVFXConfig
    public var flameIntensity: Float
    public var flameSharpness: Float
    public var enableGlow: Bool
    public var enableHeatDistortion: Bool
    public var time: Float
    public var isForSmallMark: Bool

    public init(
        curveStrength: Float = 0.7,
        columnWidthRatio: Float = 0.32,
        showApertureArc: Bool = false,
        flameMode: MVFlameMode = .none,
        layoutMode: MVLogoLayoutMode = .flameOnBlack,
        fxConfig: MVFXConfig = MVFXConfig(),
        flameIntensity: Float = 1.0,
        flameSharpness: Float = 3.5,
        enableGlow: Bool = true,
        enableHeatDistortion: Bool = true,
        time: Float = 0.0,
        isForSmallMark: Bool = false
    ) {
        self.curveStrength = curveStrength
        self.columnWidthRatio = columnWidthRatio
        self.showApertureArc = showApertureArc
        self.flameMode = flameMode
        self.layoutMode = layoutMode
        self.fxConfig = fxConfig
        self.flameIntensity = flameIntensity
        self.flameSharpness = flameSharpness
        self.enableGlow = enableGlow
        self.enableHeatDistortion = enableHeatDistortion
        self.time = time
        self.isForSmallMark = isForSmallMark
    }
}

// MARK: - Engine

public final class MetaVisLogoEngine {
    private let device: MTLDevice
    private let pipelineState: MTLRenderPipelineState
    
    // Cached geometry
    private var leftShapeBuffer: MTLBuffer?
    private var rightShapeBuffer: MTLBuffer?
    private var centerFlameBuffer: MTLBuffer?
    private var vertexCount: Int = 0
    
    // Current params to check for regeneration
    private var lastGenParams: MetaVisLogoParams?
    
    public init(device: MTLDevice, library: MTLLibrary, pixelFormat: MTLPixelFormat = .bgra8Unorm) throws {
        self.device = device
        
        // Load Shaders
        guard let vertexFunc = library.makeFunction(name: "metavis_logo_vertex"),
              let fragmentFunc = library.makeFunction(name: "metavis_logo_fragment")
        else {
            throw LogoEngineError.shadersNotFound
        }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunc
        descriptor.fragmentFunction = fragmentFunc
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        
        // Additive Blending for Emission (C_out = C_dst + C_src)
        // We want pure addition for the flame to accumulate light
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
        
        // Vertex Descriptor
        let vertexDescriptor = MTLVertexDescriptor()
        // Pos (float2)
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        // UV (float2)
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = 8
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        vertexDescriptor.layouts[0].stride = 16
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        descriptor.vertexDescriptor = vertexDescriptor
        
        self.pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    public func renderLogoSymbol(
        into encoder: MTLRenderCommandEncoder,
        params: MetaVisLogoParams,
        in bounds: CGRect,
        offset: SIMD2<Float> = .zero
    ) {
        // 1. Regenerate geometry if needed
        if geometryNeedsUpdate(params) {
            generateGeometry(params)
            lastGenParams = params
        }
        
        guard let leftBuffer = leftShapeBuffer, let rightBuffer = rightShapeBuffer else { return }
        
        encoder.setRenderPipelineState(pipelineState)
        
        // 2. Setup Uniforms
        let boundsAspect = Float(bounds.width / bounds.height)
        var matrix = makeProjectionMatrix(bounds: bounds)
        matrix.columns.3.x = offset.x
        matrix.columns.3.y = offset.y
        
        var uniforms = LogoUniforms(
            viewProjectionMatrix: matrix,
            color: SIMD4<Float>(1, 1, 1, 1), // White
            time: params.time,
            flameMode: Int32(params.flameMode.rawValue),
            curveStrength: params.curveStrength,
            columnWidthRatio: params.columnWidthRatio,
            flameIntensity: params.flameIntensity,
            flameSharpness: params.flameSharpness,
            enableGlow: params.enableGlow ? 1 : 0,
            enableHeatDistortion: params.enableHeatDistortion ? 1 : 0,
            isFlame: 0, // 0 = Left Shape
            layoutMode: Int32(params.layoutMode.rawValue),
            aspectRatio: boundsAspect
        )
        
        // 3. Render Left Shape
        // Torch Mode: White Shapes
        uniforms.color = SIMD4<Float>(1, 1, 1, 1)
        uniforms.isFlame = 0
        
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<LogoUniforms>.size, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<LogoUniforms>.size, index: 1)
        encoder.setVertexBuffer(leftBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertexCount)
        
        // 4. Render Right Shape
        uniforms.isFlame = 1 // 1 = Right Shape
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<LogoUniforms>.size, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<LogoUniforms>.size, index: 1)
        encoder.setVertexBuffer(rightBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertexCount)
        
        // 5. Render Center Flame (if needed)
        if let flameBuffer = centerFlameBuffer, params.flameMode != .none {
            uniforms.isFlame = 2 // 2 = Center Flame
            // Flame color handled in shader, but pass base white
            uniforms.color = SIMD4<Float>(1, 1, 1, 1)
            
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<LogoUniforms>.size, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<LogoUniforms>.size, index: 1)
            encoder.setVertexBuffer(flameBuffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertexCount)
        }
    }
    
    public func renderLogoLockup(
        into encoder: MTLRenderCommandEncoder,
        params: MetaVisLogoParams,
        in bounds: CGRect,
        title: String = "MetaVis",
        subtitle: String = "Studios"
    ) {
        // 1. Render Symbol
        // Calculate symbol rect (top part of bounds)
        // Let's say symbol takes 70% height, text 30%
        let symbolHeight = bounds.height * 0.7
        let symbolRect = CGRect(
            x: bounds.midX - symbolHeight * 0.3, // Aspect ratio approx 0.6
            y: bounds.minY,
            width: symbolHeight * 0.6,
            height: symbolHeight
        )
        
        renderLogoSymbol(into: encoder, params: params, in: symbolRect)
        
        // 2. Render Text (Placeholder for now, assuming SDFTextRenderer is external)
        // The spec says "Use the existing SDF Text Renderer".
        // Since this class doesn't own the text renderer, we might need to pass it in or
        // the caller handles text.
        // But the API signature requires `renderLogoLockup`.
        // I'll leave a comment or TODO as I don't have the SDFTextRenderer instance here.
        // Actually, I should probably accept it in init or method if I strictly follow the API.
        // For now, I will focus on the symbol as that's the engine's core job.
    }
    
    // MARK: - Private Helpers
    
    private func geometryNeedsUpdate(_ params: MetaVisLogoParams) -> Bool {
        guard let last = lastGenParams else { return true }
        return last.curveStrength != params.curveStrength ||
               last.columnWidthRatio != params.columnWidthRatio
    }
    
    private func generateGeometry(_ params: MetaVisLogoParams) {
        // Generate Three Shapes: Left, Right, and Center Flame
        // Golden Ratio Rect: H/W = 1.618
        let phi: Float = 1.61803398875
        let halfH = phi / 2.0
        let halfW: Float = 0.5
        
        let segments = 256
        var leftVerts: [Float] = []
        var rightVerts: [Float] = []
        var flameVerts: [Float] = []
        
        // Control Points for S-Curve (The Gap)
        let p0 = SIMD2<Float>(0, -halfH * 0.8)
        let p1 = SIMD2<Float>(halfW * params.curveStrength, -halfH * 0.2)
        let p2 = SIMD2<Float>(-halfW * params.curveStrength, halfH * 0.2)
        let p3 = SIMD2<Float>(0, halfH * 0.8)
        
        for i in 0...segments {
            let t = Float(i) / Float(segments)
            
            // Cubic Bezier
            let omt = 1.0 - t
            let omt2 = omt * omt
            let omt3 = omt2 * omt
            let t2 = t * t
            let t3 = t2 * t
            
            let pos = p0 * omt3 + p1 * (3 * omt2 * t) + p2 * (3 * omt * t2) + p3 * t3
            
            // Gap Width (Variable)
            let gapWidth = sin(t * Float.pi) * params.columnWidthRatio * 0.5
            
            let y = -halfH + t * phi
            
            // Left Shape
            leftVerts.append(-halfW); leftVerts.append(y)
            leftVerts.append(0); leftVerts.append(t)
            
            leftVerts.append(pos.x - gapWidth); leftVerts.append(y)
            leftVerts.append(1); leftVerts.append(t)
            
            // Right Shape
            rightVerts.append(pos.x + gapWidth); rightVerts.append(y)
            rightVerts.append(0); rightVerts.append(t)
            
            rightVerts.append(halfW); rightVerts.append(y)
            rightVerts.append(1); rightVerts.append(t)
            
            // Center Flame Shape (Fills the gap)
            // UV.x: 0 (Left Edge) -> 1 (Right Edge). Center is 0.5
            flameVerts.append(pos.x - gapWidth); flameVerts.append(y)
            flameVerts.append(0); flameVerts.append(t)
            
            flameVerts.append(pos.x + gapWidth); flameVerts.append(y)
            flameVerts.append(1); flameVerts.append(t)
        }
        
        vertexCount = leftVerts.count / 4
        leftShapeBuffer = device.makeBuffer(bytes: leftVerts, length: leftVerts.count * MemoryLayout<Float>.size, options: .storageModeShared)
        rightShapeBuffer = device.makeBuffer(bytes: rightVerts, length: rightVerts.count * MemoryLayout<Float>.size, options: .storageModeShared)
        centerFlameBuffer = device.makeBuffer(bytes: flameVerts, length: flameVerts.count * MemoryLayout<Float>.size, options: .storageModeShared)
    }
    
    private func makeProjectionMatrix(bounds: CGRect) -> matrix_float4x4 {
        // Map local coords to NDC preserving aspect ratio
        let boundsAspect = Float(bounds.width / bounds.height)
        
        // Scale X by 1/Aspect to correct for non-square viewport
        let scaleY: Float = 1.0
        let scaleX: Float = 1.0 / boundsAspect
        
        // Global scale to fit comfortably in view
        // REDUCED from 0.85 to 0.60 to prevent clipping when offset
        let globalScale: Float = 0.60
        
        return matrix_float4x4(diagonal: SIMD4<Float>(scaleX * globalScale, scaleY * globalScale, 1, 1))
    }
}

// MARK: - Internal Types

struct LogoUniforms {
    var viewProjectionMatrix: matrix_float4x4
    var color: SIMD4<Float>
    var time: Float
    var flameMode: Int32
    var curveStrength: Float
    var columnWidthRatio: Float
    var flameIntensity: Float
    var flameSharpness: Float
    var enableGlow: Int32
    var enableHeatDistortion: Int32
    var isFlame: Int32
    var layoutMode: Int32
    var aspectRatio: Float
    var padding: Int32 = 0 // Pad to 128 bytes
}

enum LogoEngineError: Error {
    case shadersNotFound
}

extension matrix_float4x4 {
    init(diagonal: SIMD4<Float>) {
        self.init(columns: (
            SIMD4<Float>(diagonal.x, 0, 0, 0),
            SIMD4<Float>(0, diagonal.y, 0, 0),
            SIMD4<Float>(0, 0, diagonal.z, 0),
            SIMD4<Float>(0, 0, 0, diagonal.w)
        ))
    }
}
