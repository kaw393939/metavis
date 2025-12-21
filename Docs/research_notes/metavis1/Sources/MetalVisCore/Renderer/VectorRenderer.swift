import Metal
import simd

/// Vector Renderer
/// Renders vector graphics using GPU acceleration
public final class VectorRenderer {
    public let device: MTLDevice
    public let pipeline: MTLRenderPipelineState

    public init(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb) throws {
        self.device = device

        // Load library
        let library: MTLLibrary
        if let defaultLib = device.makeDefaultLibrary() {
            library = defaultLib
        } else {
            // Fallback for tests/dev: load from source
            // This path assumption might be brittle, but works for now in this project structure
            let source = try String(contentsOfFile: "Sources/MetalVisCore/Shaders/Vector.metal", encoding: .utf8)
            library = try device.makeLibrary(source: source, options: nil)
        }

        guard let vertexFunction = library.makeFunction(name: "vector_vertex"),
              let fragmentFunction = library.makeFunction(name: "vector_fragment")
        else {
            throw VectorRendererError.shaderCompilationFailed("Could not find vector shader functions")
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha

        // Vertex Descriptor
        let vertexDescriptor = MTLVertexDescriptor()

        // Attribute 0: Position (float2)
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0

        // Attribute 1: Color (float4)
        vertexDescriptor.attributes[1].format = .float4
        vertexDescriptor.attributes[1].offset = 16
        vertexDescriptor.attributes[1].bufferIndex = 0

        // Attribute 2: TexCoord (float2)
        vertexDescriptor.attributes[2].format = .float2
        vertexDescriptor.attributes[2].offset = 32
        vertexDescriptor.attributes[2].bufferIndex = 0

        // Layout
        // Stride is 48 bytes (16 pos + 16 color + 16 texCoord+padding)
        vertexDescriptor.layouts[0].stride = 48
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        pipelineDescriptor.vertexDescriptor = vertexDescriptor

        pipeline = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }

    // MARK: - Rendering

    struct VectorVertex {
        var position: SIMD2<Float>
        var color: SIMD4<Float>
        var texCoord: SIMD2<Float>
        // Implicit padding to 48 bytes
    }

    struct VectorUniforms {
        var shapeType: Int32 // 0 = Rect, 1 = Circle, 2 = RoundedRect
        var softness: Float
        var cornerRadius: Float
        var padding: Float
        var dimensions: SIMD2<Float>
    }

    /// Render a filled rectangle
    public func renderRectangle(
        rect: CGRect,
        color: SIMD4<Float>,
        into texture: MTLTexture,
        clearColor: MTLClearColor? = nil
    ) throws {
        try renderShape(rect: rect, color: color, type: 0, into: texture, clearColor: clearColor)
    }

    /// Render a filled circle
    public func renderCircle(
        rect: CGRect,
        color: SIMD4<Float>,
        softness: Float = 0.0,
        into texture: MTLTexture,
        clearColor: MTLClearColor? = nil
    ) throws {
        try renderShape(rect: rect, color: color, type: 1, into: texture, clearColor: clearColor, softness: softness)
    }

    /// Render a rounded rectangle
    public func renderRoundedRect(
        rect: CGRect,
        cornerRadius: Float,
        color: SIMD4<Float>,
        softness: Float = 0.0,
        into texture: MTLTexture,
        clearColor: MTLClearColor? = nil
    ) throws {
        try renderShape(
            rect: rect,
            color: color,
            type: 2,
            into: texture,
            clearColor: clearColor,
            cornerRadius: cornerRadius,
            softness: softness,
            dimensions: SIMD2<Float>(Float(rect.width), Float(rect.height))
        )
    }

    private func renderShape(
        rect: CGRect,
        color: SIMD4<Float>,
        type: Int32,
        into texture: MTLTexture,
        clearColor: MTLClearColor? = nil,
        cornerRadius: Float = 0.0,
        softness: Float = 0.0,
        dimensions: SIMD2<Float> = .zero
    ) throws {
        let width = Float(texture.width)
        let height = Float(texture.height)

        // Create vertices (2 triangles)
        let x = Float(rect.origin.x)
        let y = Float(rect.origin.y)
        let w = Float(rect.width)
        let h = Float(rect.height)

        let vertices: [VectorVertex] = [
            VectorVertex(position: SIMD2(x, y), color: color, texCoord: SIMD2(0, 0)),
            VectorVertex(position: SIMD2(x + w, y), color: color, texCoord: SIMD2(1, 0)),
            VectorVertex(position: SIMD2(x, y + h), color: color, texCoord: SIMD2(0, 1)),

            VectorVertex(position: SIMD2(x + w, y), color: color, texCoord: SIMD2(1, 0)),
            VectorVertex(position: SIMD2(x + w, y + h), color: color, texCoord: SIMD2(1, 1)),
            VectorVertex(position: SIMD2(x, y + h), color: color, texCoord: SIMD2(0, 1))
        ]

        // Create MVP Matrix (Orthographic)
        let left: Float = 0
        let right = width
        let bottom = height
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

        var uniforms = VectorUniforms(
            shapeType: type,
            softness: softness,
            cornerRadius: cornerRadius,
            padding: 0.0,
            dimensions: dimensions
        )

        // Create Command Buffer
        guard let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            throw VectorRendererError.commandBufferCreationFailed
        }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        if let clear = clearColor {
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].clearColor = clear
        } else {
            renderPassDescriptor.colorAttachments[0].loadAction = .load
        }
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            throw VectorRendererError.commandBufferCreationFailed
        }

        renderEncoder.setRenderPipelineState(pipeline)
        renderEncoder.setVertexBytes(vertices, length: vertices.count * 48, index: 0) // 48 bytes stride
        renderEncoder.setVertexBytes(&mvpMatrix, length: MemoryLayout<matrix_float4x4>.stride, index: 1)
        renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<VectorUniforms>.stride, index: 0)

        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
        renderEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
}

public enum VectorRendererError: Error {
    case shaderCompilationFailed(String)
    case commandBufferCreationFailed
}
