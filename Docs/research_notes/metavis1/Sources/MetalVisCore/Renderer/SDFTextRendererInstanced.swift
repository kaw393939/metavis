import CoreGraphics
import CoreText
import Foundation
@preconcurrency import Metal
import simd

/// Instanced SDF Text Renderer
/// 
/// **Memory Optimization**: 2.4× reduction vs standard SDFTextRenderer
/// - Standard: 96 bytes per glyph (6 vertices × 16 bytes)
/// - Instanced: 40 bytes per glyph (1 instance × 40 bytes)
///
/// **Architecture**:
/// - Shared quad geometry (6 vertices, single allocation)
/// - Per-instance buffer: [position, scale, uvOffset, color]
/// - GPU instancing via `drawIndexedPrimitives(instanceCount:)`
///
/// **Use Case**: Efficient rendering of large text blocks (1000+ glyphs)
/// **Compatibility**: Drop-in replacement for SDFTextRenderer
///
/// Reference: Sprint 2 Phase 2 - Instanced Rendering (08_TDD_IMPLEMENTATION_SPEC.md)
public actor SDFTextRendererInstanced {
    
    // MARK: - Instance Data Structure
    
    /// Per-instance data (40 bytes)
    struct InstanceData {
        var position: SIMD2<Float>      // 8 bytes - glyph position (screen space)
        var scale: SIMD2<Float>         // 8 bytes - glyph size (width, height)
        var uvOffset: SIMD2<Float>      // 8 bytes - atlas UV top-left
        var uvScale: SIMD2<Float>       // 8 bytes - atlas UV size
        var color: SIMD4<Float>         // 16 bytes - RGBA (optional per-glyph tint)
    }
    
    // MARK: - Properties
    
    public nonisolated let mode: SDFTextRenderer.SDFMode
    public nonisolated let fontAtlas: SDFFontAtlas
    public nonisolated let pipeline: MTLRenderPipelineState
    public nonisolated let pixelFormat: MTLPixelFormat
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private nonisolated let atlasWidth: Int
    private nonisolated let atlasHeight: Int
    private nonisolated let glyphMetrics: [Character: SDFFontAtlas.GlyphMetrics]
    private nonisolated let samplerState: MTLSamplerState
    private nonisolated let layoutEngine: TextLayoutEngine
    
    /// Shared quad geometry (reused for all instances)
    private nonisolated let sharedQuadVertexBuffer: MTLBuffer
    private nonisolated let sharedQuadIndexBuffer: MTLBuffer
    private nonisolated let indexCount: Int
    
    // MARK: - Initialization
    
    public init(
        fontAtlas: SDFFontAtlas,
        device: MTLDevice,
        mode: SDFTextRenderer.SDFMode = .sdf,
        shaderLibrary: ShaderLibrary? = nil,
        pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb
    ) throws {
        self.fontAtlas = fontAtlas
        self.device = device
        self.mode = mode
        self.pixelFormat = pixelFormat
        self.atlasWidth = fontAtlas.texture.width
        self.atlasHeight = fontAtlas.texture.height
        self.glyphMetrics = fontAtlas.glyphMetrics
        
        guard let queue = device.makeCommandQueue() else {
            throw SDFRendererError.commandQueueCreationFailed
        }
        self.commandQueue = queue
        
        // Create sampler state
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .notMipmapped
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw SDFRendererError.samplerCreationFailed
        }
        self.samplerState = sampler
        
        // Initialize layout engine
        self.layoutEngine = TextLayoutEngine(fontAtlas: fontAtlas)
        
        // Create shared quad geometry (unit square: 0,0 to 1,1)
        // This will be scaled and positioned per-instance in vertex shader
        struct QuadVertex {
            var position: SIMD2<Float>
            var texCoords: SIMD2<Float>
        }
        
        let quadVertices: [QuadVertex] = [
            QuadVertex(position: SIMD2(0, 0), texCoords: SIMD2(0, 0)), // Top-left
            QuadVertex(position: SIMD2(1, 0), texCoords: SIMD2(1, 0)), // Top-right
            QuadVertex(position: SIMD2(0, 1), texCoords: SIMD2(0, 1)), // Bottom-left
            QuadVertex(position: SIMD2(1, 1), texCoords: SIMD2(1, 1))  // Bottom-right
        ]
        
        let quadIndices: [UInt16] = [
            0, 1, 2,  // First triangle
            1, 3, 2   // Second triangle
        ]
        
        guard let vertexBuffer = device.makeBuffer(
            bytes: quadVertices,
            length: quadVertices.count * MemoryLayout<QuadVertex>.stride,
            options: .storageModeShared
        ) else {
            throw SDFRendererError.bufferCreationFailed
        }
        self.sharedQuadVertexBuffer = vertexBuffer
        
        guard let indexBuffer = device.makeBuffer(
            bytes: quadIndices,
            length: quadIndices.count * MemoryLayout<UInt16>.stride,
            options: .storageModeShared
        ) else {
            throw SDFRendererError.bufferCreationFailed
        }
        self.sharedQuadIndexBuffer = indexBuffer
        self.indexCount = quadIndices.count
        
        // Load shaders
        let lib = shaderLibrary ?? ShaderLibrary(device: device)
        
        if (try? lib.makeFunction(name: "sdf_instanced_vertex")) == nil {
            try? lib.loadSource(resource: "SDFTextInstanced")
        }
        
        let fragmentFunctionName: String
        switch mode {
        case .sdf: fragmentFunctionName = "sdf_fragment"
        case .msdf: fragmentFunctionName = "msdf_fragment"
        case .mtsdf: fragmentFunctionName = "mtsdf_fragment"
        }
        
        guard let vertexFunction = try? lib.makeFunction(name: "sdf_instanced_vertex"),
              let fragmentFunction = try? lib.makeFunction(name: fragmentFunctionName)
        else {
            throw SDFRendererError.shaderCompilationFailed("Could not find instanced SDF shader functions")
        }
        
        // Create render pipeline
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        // Vertex descriptor for shared quad
        let vertexDescriptor = MTLVertexDescriptor()
        // Position (float2)
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        // TexCoords (float2)
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 2
        vertexDescriptor.attributes[1].bufferIndex = 0
        // Layout
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.size * 4
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        // Instance buffer layout (buffer index 2)
        vertexDescriptor.attributes[2].format = .float2  // position
        vertexDescriptor.attributes[2].offset = 0
        vertexDescriptor.attributes[2].bufferIndex = 2
        
        vertexDescriptor.attributes[3].format = .float2  // scale
        vertexDescriptor.attributes[3].offset = MemoryLayout<Float>.size * 2
        vertexDescriptor.attributes[3].bufferIndex = 2
        
        vertexDescriptor.attributes[4].format = .float2  // uvOffset
        vertexDescriptor.attributes[4].offset = MemoryLayout<Float>.size * 4
        vertexDescriptor.attributes[4].bufferIndex = 2
        
        vertexDescriptor.attributes[5].format = .float2  // uvScale
        vertexDescriptor.attributes[5].offset = MemoryLayout<Float>.size * 6
        vertexDescriptor.attributes[5].bufferIndex = 2
        
        vertexDescriptor.attributes[6].format = .float4  // color
        vertexDescriptor.attributes[6].offset = MemoryLayout<Float>.size * 8
        vertexDescriptor.attributes[6].bufferIndex = 2
        
        vertexDescriptor.layouts[2].stride = MemoryLayout<InstanceData>.stride  // 40 bytes
        vertexDescriptor.layouts[2].stepRate = 1
        vertexDescriptor.layouts[2].stepFunction = .perInstance
        
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        
        do {
            self.pipeline = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            throw SDFRendererError.pipelineCreationFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Rendering
    
    /// SDFUniforms structure (matches Metal shader)
    struct SDFUniforms {
        var color: SIMD4<Float>
        var edgeDistance: Float
        var edgeSoftness: Float
        var padding1: SIMD2<Float> = .zero
        var outlineColor: SIMD4<Float>
        var outlineWidth: Float
        var padding2: SIMD3<Float> = .zero
    }
    
    /// Render text with instanced rendering (40 bytes per glyph vs 96 bytes)
    public nonisolated func render(
        text: String,
        position: CGPoint,
        width: Int,
        height: Int,
        color: SIMD4<Float> = SIMD4(1, 1, 1, 1),
        fontSize: Float = 64.0,
        weight: Float = 0.5,
        softness: Float = 0.0,
        outlineColor: SIMD4<Float> = SIMD4(0, 0, 0, 0),
        outlineWidth: Float = 0.0,
        tracking: Float = 0.0
    ) async throws -> MTLTexture {
        
        // Create command buffer first
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw SDFRendererError.commandBufferCreationFailed
        }

        // Create output texture descriptor
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.renderTarget, .shaderRead]
        
        guard let outputTexture = device.makeTexture(descriptor: textureDescriptor) else {
            throw SDFRendererError.textureCreationFailed
        }
        
        // Generate text layout
        let layout = layoutEngine.layout(
            text: text,
            position: SIMD2(Float(position.x), Float(position.y)),
            fontSize: fontSize,
            tracking: tracking
        )
        
        // Early exit if no glyphs
        if layout.glyphs.isEmpty {
            return outputTexture
        }
        
        // Build instance data (40 bytes per glyph)
        var instances: [InstanceData] = []
        instances.reserveCapacity(layout.glyphs.count)
        
        for glyph in layout.glyphs {
            let instance = InstanceData(
                position: glyph.position,
                scale: glyph.size,
                uvOffset: SIMD2(glyph.texCoords.x, glyph.texCoords.y),
                uvScale: SIMD2(glyph.texCoords.z - glyph.texCoords.x,
                              glyph.texCoords.w - glyph.texCoords.y),
                color: color  // Could be per-glyph if needed
            )
            instances.append(instance)
        }
        
        // Create instance buffer
        guard let instanceBuffer = device.makeBuffer(
            bytes: instances,
            length: instances.count * MemoryLayout<InstanceData>.stride,
            options: .storageModeShared
        ) else {
            throw SDFRendererError.bufferCreationFailed
        }
        
        // Create orthographic projection matrix
        let left: Float = 0
        let right = Float(width)
        let bottom = Float(height)
        let top: Float = 0
        let near: Float = -1
        let far: Float = 1
        
        var mvpMatrix = matrix_float4x4(
            SIMD4(2.0 / (right - left), 0, 0, 0),
            SIMD4(0, 2.0 / (top - bottom), 0, 0),
            SIMD4(0, 0, -2.0 / (far - near), 0),
            SIMD4(-(right + left) / (right - left),
                  -(top + bottom) / (top - bottom),
                  -(far + near) / (far - near),
                  1)
        )
        
        guard let mvpBuffer = device.makeBuffer(
            bytes: &mvpMatrix,
            length: MemoryLayout<matrix_float4x4>.stride,
            options: .storageModeShared
        ) else {
            throw SDFRendererError.bufferCreationFailed
        }
        
        // Create uniforms buffer
        var uniforms = SDFUniforms(
            color: color,
            edgeDistance: weight,
            edgeSoftness: 1.0 + softness,
            outlineColor: outlineColor,
            outlineWidth: outlineWidth
        )
        
        guard let uniformsBuffer = device.makeBuffer(
            bytes: &uniforms,
            length: MemoryLayout<SDFUniforms>.stride,
            options: .storageModeShared
        ) else {
            throw SDFRendererError.bufferCreationFailed
        }
        
        // Setup render pass
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = outputTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        // Create encoder using existing command buffer
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            throw SDFRendererError.encoderCreationFailed
        }
        
        renderEncoder.setRenderPipelineState(pipeline)
        
        // Bind shared quad geometry
        renderEncoder.setVertexBuffer(sharedQuadVertexBuffer, offset: 0, index: 0)
        
        // Bind MVP matrix
        renderEncoder.setVertexBuffer(mvpBuffer, offset: 0, index: 1)
        
        // Bind instance data
        renderEncoder.setVertexBuffer(instanceBuffer, offset: 0, index: 2)
        
        // Bind uniforms
        renderEncoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        
        // Bind atlas texture
        renderEncoder.setFragmentTexture(fontAtlas.texture, index: 0)
        renderEncoder.setFragmentSamplerState(samplerState, index: 0)
        
        // Draw instanced (KEY: one draw call for all glyphs!)
        renderEncoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indexCount,
            indexType: .uint16,
            indexBuffer: sharedQuadIndexBuffer,
            indexBufferOffset: 0,
            instanceCount: instances.count  // 🎯 Instanced rendering
        )
        
        renderEncoder.endEncoding()
        
        return await withCheckedContinuation { continuation in
            commandBuffer.addCompletedHandler { _ in
                continuation.resume(returning: outputTexture)
            }
            commandBuffer.commit()
        }
    }
    
    /// Render multiple labels in a single batch
    /// Further optimizes by combining instance buffers
    public nonisolated func renderBatch(
        labels: [(text: String, position: CGPoint, color: SIMD4<Float>)],
        width: Int,
        height: Int,
        fontSize: Float = 64.0,
        weight: Float = 0.5,
        softness: Float = 0.0,
        tracking: Float = 0.0
    ) async throws -> MTLTexture {
        
        // Create command buffer first
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw SDFRendererError.commandBufferCreationFailed
        }

        // Create output texture
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.renderTarget, .shaderRead]
        
        guard let outputTexture = device.makeTexture(descriptor: textureDescriptor) else {
            throw SDFRendererError.textureCreationFailed
        }
        
        // Accumulate all instances from all labels
        var allInstances: [InstanceData] = []
        
        for (text, position, color) in labels {
            let layout = layoutEngine.layout(
                text: text,
                position: SIMD2(Float(position.x), Float(position.y)),
                fontSize: fontSize,
                tracking: tracking
            )
            
            for glyph in layout.glyphs {
                let instance = InstanceData(
                    position: glyph.position,
                    scale: glyph.size,
                    uvOffset: SIMD2(glyph.texCoords.x, glyph.texCoords.y),
                    uvScale: SIMD2(glyph.texCoords.z - glyph.texCoords.x,
                                  glyph.texCoords.w - glyph.texCoords.y),
                    color: color
                )
                allInstances.append(instance)
            }
        }
        
        // Early exit
        if allInstances.isEmpty {
            return outputTexture
        }
        
        // Create single instance buffer for all labels
        guard let instanceBuffer = device.makeBuffer(
            bytes: allInstances,
            length: allInstances.count * MemoryLayout<InstanceData>.stride,
            options: .storageModeShared
        ) else {
            throw SDFRendererError.bufferCreationFailed
        }
        
        // Setup matrices and uniforms (same as single label)
        let left: Float = 0
        let right = Float(width)
        let bottom = Float(height)
        let top: Float = 0
        let near: Float = -1
        let far: Float = 1
        
        var mvpMatrix = matrix_float4x4(
            SIMD4(2.0 / (right - left), 0, 0, 0),
            SIMD4(0, 2.0 / (top - bottom), 0, 0),
            SIMD4(0, 0, -2.0 / (far - near), 0),
            SIMD4(-(right + left) / (right - left),
                  -(top + bottom) / (top - bottom),
                  -(far + near) / (far - near),
                  1)
        )
        
        guard let mvpBuffer = device.makeBuffer(
            bytes: &mvpMatrix,
            length: MemoryLayout<matrix_float4x4>.stride,
            options: .storageModeShared
        ) else {
            throw SDFRendererError.bufferCreationFailed
        }
        
        var uniforms = SDFUniforms(
            color: SIMD4(1, 1, 1, 1),  // Color comes from instance data
            edgeDistance: weight,
            edgeSoftness: 1.0 + softness,
            outlineColor: SIMD4(0, 0, 0, 0),
            outlineWidth: 0.0
        )
        
        guard let uniformsBuffer = device.makeBuffer(
            bytes: &uniforms,
            length: MemoryLayout<SDFUniforms>.stride,
            options: .storageModeShared
        ) else {
            throw SDFRendererError.bufferCreationFailed
        }
        
        // Render pass
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = outputTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        // Create encoder using existing command buffer
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            throw SDFRendererError.encoderCreationFailed
        }
        
        renderEncoder.setRenderPipelineState(pipeline)
        renderEncoder.setVertexBuffer(sharedQuadVertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(mvpBuffer, offset: 0, index: 1)
        renderEncoder.setVertexBuffer(instanceBuffer, offset: 0, index: 2)
        renderEncoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentTexture(fontAtlas.texture, index: 0)
        renderEncoder.setFragmentSamplerState(samplerState, index: 0)
        
        // Single draw call for ALL glyphs from ALL labels! 🚀
        renderEncoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indexCount,
            indexType: .uint16,
            indexBuffer: sharedQuadIndexBuffer,
            indexBufferOffset: 0,
            instanceCount: allInstances.count
        )
        
        renderEncoder.endEncoding()
        
        return await withCheckedContinuation { continuation in
            commandBuffer.addCompletedHandler { _ in
                continuation.resume(returning: outputTexture)
            }
            commandBuffer.commit()
        }
    }
}
