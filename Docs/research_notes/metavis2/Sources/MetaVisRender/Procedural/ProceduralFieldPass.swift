//
//  ProceduralFieldPass.swift
//  MetaVisRender
//
//  Render pass for procedural field generation
//

import Metal
import simd

/// Render pass that generates procedural noise fields
final class ProceduralFieldPass: Sendable {
    // MARK: - Properties
    
    private let device: MTLDevice
    private let library: MTLLibrary
    private let pipelineState: MTLComputePipelineState
    
    // Reusable buffers
    // Buffers removed for Sendable compliance - using setBytes instead
    
    private static let maxGradientStops = 16
    
    // MARK: - Init
    
    /// Initialize with separate library loading to avoid hash() conflicts
    init(device: MTLDevice) throws {
        self.device = device
        
        // Load ProceduralField.metal separately to avoid conflicts with Background.metal
        let compiler = ShaderCompiler(bundle: Bundle.module, rootDirectory: "Shaders")
        let source = try compiler.compile(file: "Procedural/ProceduralField.metal")
        self.library = try device.makeLibrary(source: source, options: nil)
        
        // Create compute pipeline
        guard let kernel = library.makeFunction(name: "fx_procedural_field") else {
            throw RenderError.shaderNotFound("fx_procedural_field")
        }
        
        self.pipelineState = try device.makeComputePipelineState(function: kernel)
    }
    
    // MARK: - Render
    
    /// Generate procedural field into output texture
    func render(
        commandBuffer: MTLCommandBuffer,
        definition: ProceduralFieldDefinition,
        outputTexture: MTLTexture,
        time: Float = 0.0
    ) throws {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw RenderError.encoderCreationFailed
        }
        
        encoder.label = "Procedural Field"
        
        // Validate
        try definition.validate()
        
        guard definition.gradient.count <= Self.maxGradientStops else {
            throw RenderError.invalidParameter(
                "Gradient has \(definition.gradient.count) stops, max is \(Self.maxGradientStops)"
            )
        }
        
        // Upload parameters
        var params = definition.toFieldParams(time: time)
        encoder.setBytes(&params, length: MemoryLayout<FieldParams>.stride, index: 0)
        
        // Upload gradient
        var gradient = definition.toGPUGradient()
        
        // Pad gradient to max stops to match shader expectation
        if gradient.count < Self.maxGradientStops {
            let paddingCount = Self.maxGradientStops - gradient.count
            // Create a dummy stop for padding
            let dummyStop = GPUGradientStop(color: SIMD3<Float>(0,0,0), position: 0)
            gradient.append(contentsOf: repeatElement(dummyStop, count: paddingCount))
        }
        
        encoder.setBytes(&gradient, length: MemoryLayout<GPUGradientStop>.stride * Self.maxGradientStops, index: 1)
        
        // Set pipeline and resources
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(outputTexture, index: 0)
        
        // Dispatch
        let width = outputTexture.width
        let height = outputTexture.height
        
        let threadgroupSize = MTLSize(
            width: 16,
            height: 16,
            depth: 1
        )
        
        let threadgroups = MTLSize(
            width: (width + threadgroupSize.width - 1) / threadgroupSize.width,
            height: (height + threadgroupSize.height - 1) / threadgroupSize.height,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
    }
}

// MARK: - Errors
// RenderError is now consolidated in RenderEngine.swift
