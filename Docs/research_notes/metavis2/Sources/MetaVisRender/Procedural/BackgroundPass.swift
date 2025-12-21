//
//  BackgroundPass.swift
//  MetaVisRender
//
//  Unified background rendering pass
//

import Metal
import simd

/// Unified render pass for all background types
public final class BackgroundPass: Sendable {
    // MARK: - Properties
    
    private let device: MTLDevice
    private let library: MTLLibrary
    
    // Pipeline states
    private let solidPipeline: MTLComputePipelineState
    private let gradientPipeline: MTLComputePipelineState
    private let starfieldPipeline: MTLComputePipelineState
    
    // Procedural field pass (reused)
    private let proceduralPass: ProceduralFieldPass
    
    // Reusable buffers
    // private let paramsBuffer: MTLBuffer
    // private let gradientBuffer: MTLBuffer
    
    private static let maxGradientStops = 16
    
    // MARK: - Init
    
    init(device: MTLDevice) throws {
        self.device = device
        
        // Load Background.metal separately to avoid hash() redefinition with ProceduralField.metal
        // Try pre-compiled library first, fallback to runtime compilation
        let backgroundLibrary: MTLLibrary
        if let defaultLib = try? device.makeDefaultLibrary(bundle: Bundle.module),
           defaultLib.functionNames.contains("fx_solid_background") {
            backgroundLibrary = defaultLib
        } else {
            // Runtime compile Background.metal
            let compiler = ShaderCompiler(bundle: Bundle.module, rootDirectory: "Shaders")
            let source = try compiler.compile(file: "Background.metal")
            backgroundLibrary = try device.makeLibrary(source: source, options: nil)
        }
        self.library = backgroundLibrary
        
        // Log struct sizes for debugging (Metal alignment can be tricky)
        #if DEBUG
        SolidBackgroundParams.validate()
        GradientBackgroundParams.validate()
        StarfieldParams.validate()
        #endif
        
        // Create pipelines
        guard let solidKernel = backgroundLibrary.makeFunction(name: "fx_solid_background") else {
            throw RenderError.shaderNotFound("fx_solid_background")
        }
        self.solidPipeline = try device.makeComputePipelineState(function: solidKernel)
        
        guard let gradientKernel = backgroundLibrary.makeFunction(name: "fx_gradient_background") else {
            throw RenderError.shaderNotFound("fx_gradient_background")
        }
        self.gradientPipeline = try device.makeComputePipelineState(function: gradientKernel)
        
        guard let starfieldKernel = backgroundLibrary.makeFunction(name: "fx_starfield_background") else {
            throw RenderError.shaderNotFound("fx_starfield_background")
        }
        self.starfieldPipeline = try device.makeComputePipelineState(function: starfieldKernel)
        
        // Create procedural pass (loads its own library separately)
        self.proceduralPass = try ProceduralFieldPass(device: device)
    }
    
    // MARK: - Render
    
    /// Render background into output texture
    func render(
        commandBuffer: MTLCommandBuffer,
        background: BackgroundDefinition,
        outputTexture: MTLTexture,
        time: Float = 0.0
    ) throws {
        switch background {
        case .solid(let solid):
            // Removed excessive logging - was flooding terminal and crashing VS Code
            try renderSolid(commandBuffer: commandBuffer, solid: solid, outputTexture: outputTexture)
        case .gradient(let gradient):
            try renderGradient(commandBuffer: commandBuffer, gradient: gradient, outputTexture: outputTexture)
        case .starfield(let starfield):
            try renderStarfield(commandBuffer: commandBuffer, starfield: starfield, outputTexture: outputTexture, time: time)
        case .procedural(let procedural):
            try proceduralPass.render(commandBuffer: commandBuffer, definition: procedural, outputTexture: outputTexture, time: time)
        }
    }
    
    // MARK: - Private Rendering
    
    private func renderSolid(
        commandBuffer: MTLCommandBuffer,
        solid: SolidBackground,
        outputTexture: MTLTexture
    ) throws {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw RenderError.encoderCreationFailed
        }
        
        encoder.label = "Solid Background"
        
        // Upload parameters
        var params = SolidBackgroundParams(color: solid.color, padding: 0.0)
        
        // Set pipeline and resources
        encoder.setComputePipelineState(solidPipeline)
        encoder.setBytes(&params, length: MemoryLayout<SolidBackgroundParams>.stride, index: 0)
        encoder.setTexture(outputTexture, index: 0)
        
        // Dispatch
        dispatchThreadgroups(encoder: encoder, texture: outputTexture)
        encoder.endEncoding()
    }
    
    private func renderGradient(
        commandBuffer: MTLCommandBuffer,
        gradient: GradientBackground,
        outputTexture: MTLTexture
    ) throws {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw RenderError.encoderCreationFailed
        }
        
        encoder.label = "Gradient Background"
        
        // Validate
        try gradient.validate()
        
        guard gradient.gradient.count <= Self.maxGradientStops else {
            throw RenderError.invalidParameter(
                "Gradient has \(gradient.gradient.count) stops, max is \(Self.maxGradientStops)"
            )
        }
        
        // Upload parameters
        var params = GradientBackgroundParams(
            color1: gradient.gradient.first!.color,
            angle: gradient.angle,
            color2: gradient.gradient.last!.color,
            colorCount: Int32(gradient.gradient.count)
        )
        
        // Upload gradient stops (as SIMD4: xyz=color, w=position)
        var stops: [SIMD4<Float>] = []
        for stop in gradient.gradient {
            stops.append(SIMD4(stop.color.x, stop.color.y, stop.color.z, stop.position))
        }
        
        // Set pipeline and resources
        encoder.setComputePipelineState(gradientPipeline)
        encoder.setBytes(&params, length: MemoryLayout<GradientBackgroundParams>.stride, index: 0)
        encoder.setBytes(stops, length: stops.count * MemoryLayout<SIMD4<Float>>.stride, index: 1)
        encoder.setTexture(outputTexture, index: 0)
        
        // Dispatch
        dispatchThreadgroups(encoder: encoder, texture: outputTexture)
        encoder.endEncoding()
    }
    
    private func renderStarfield(
        commandBuffer: MTLCommandBuffer,
        starfield: StarfieldBackground,
        outputTexture: MTLTexture,
        time: Float
    ) throws {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw RenderError.encoderCreationFailed
        }
        
        encoder.label = "Starfield Background"
        
        // Validate
        try starfield.validate()
        
        // Upload parameters
        var params = StarfieldParams(
            baseColor: starfield.baseColor,
            seed: Int32(starfield.seed),
            starColor: starfield.starColor,
            density: starfield.density,
            brightness: starfield.brightness,
            twinkleSpeed: starfield.twinkleSpeed,
            time: time,
            padding: 0.0
        )
        
        // Set pipeline and resources
        encoder.setComputePipelineState(starfieldPipeline)
        encoder.setBytes(&params, length: MemoryLayout<StarfieldParams>.stride, index: 0)
        encoder.setTexture(outputTexture, index: 0)
        
        // Dispatch
        dispatchThreadgroups(encoder: encoder, texture: outputTexture)
        encoder.endEncoding()
    }
    
    private func dispatchThreadgroups(encoder: MTLComputeCommandEncoder, texture: MTLTexture) {
        let width = texture.width
        let height = texture.height
        
        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: (width + threadgroupSize.width - 1) / threadgroupSize.width,
            height: (height + threadgroupSize.height - 1) / threadgroupSize.height,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
    }
}

// MARK: - GPU Params Structs

/// GPU parameters for solid background
/// CRITICAL: Must match struct in Background.metal exactly
/// NOTE: SIMD3<Float> aligns to 16 bytes in structs (Metal vec3 alignment)
private struct SolidBackgroundParams {
    var color: SIMD3<Float>  // 16 bytes (aligned)
    var padding: Float       // 4 bytes
    // Total stride: 32 bytes (struct alignment)
    
    static func validate() {
        // Expected: 32 bytes due to SIMD3 alignment in Swift matching Metal's vec3
        let actualSize = MemoryLayout<Self>.stride
        print("SolidBackgroundParams: stride=\(actualSize), size=\(MemoryLayout<Self>.size), alignment=\(MemoryLayout<Self>.alignment)")
    }
}

/// GPU parameters for gradient background
/// CRITICAL: Must match struct in Background.metal exactly
private struct GradientBackgroundParams {
    var color1: SIMD3<Float>  // 16 bytes (aligned)
    var angle: Float          // 4 bytes
    var color2: SIMD3<Float>  // 16 bytes (aligned)
    var colorCount: Int32     // 4 bytes
    // Total stride: 48 bytes
    
    static func validate() {
        let actualSize = MemoryLayout<Self>.stride
        print("GradientBackgroundParams: stride=\(actualSize), size=\(MemoryLayout<Self>.size), alignment=\(MemoryLayout<Self>.alignment)")
    }
}

/// GPU parameters for starfield background
/// CRITICAL: Must match struct in Background.metal exactly
private struct StarfieldParams {
    var baseColor: SIMD3<Float>  // 16 bytes (aligned)
    var seed: Int32              // 4 bytes
    var starColor: SIMD3<Float>  // 16 bytes (aligned)
    var density: Float           // 4 bytes
    var brightness: Float        // 4 bytes
    var twinkleSpeed: Float      // 4 bytes
    var time: Float              // 4 bytes
    var padding: Float           // 4 bytes
    // Total stride: 64 bytes
    
    static func validate() {
        let actualSize = MemoryLayout<Self>.stride
        print("StarfieldParams: stride=\(actualSize), size=\(MemoryLayout<Self>.size), alignment=\(MemoryLayout<Self>.alignment)")
    }
}
