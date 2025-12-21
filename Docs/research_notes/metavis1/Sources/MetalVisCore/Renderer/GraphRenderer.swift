import Foundation
@preconcurrency import Metal
import simd

/// High-performance GPU-accelerated graph renderer
public class GraphRenderer: @unchecked Sendable {
    private let device: MTLDevice
    private let nodePipelineState: MTLRenderPipelineState
    private let edgePipelineState: MTLRenderPipelineState
    private let nodeVertexBuffer: MTLBuffer

    public init(device: MTLDevice) throws {
        self.device = device

        // Load shader library - compile from source for SPM compatibility
        let library: MTLLibrary
        if let bundlePath = Bundle.module.path(forResource: "GraphShaders", ofType: "metal"),
           let shaderSource = try? String(contentsOfFile: bundlePath) {
            library = try device.makeLibrary(source: shaderSource, options: nil)
        } else if let defaultLibrary = device.makeDefaultLibrary() {
            library = defaultLibrary
        } else {
            throw GraphRendererError.cannotLoadShaders
        }

        guard let nodeVertexFunction = library.makeFunction(name: "node_vertex"),
              let nodeFragmentFunction = library.makeFunction(name: "node_fragment"),
              let edgeVertexFunction = library.makeFunction(name: "edge_vertex"),
              let edgeFragmentFunction = library.makeFunction(name: "edge_fragment")
        else {
            throw GraphRendererError.cannotLoadShaders
        }

        // Create node pipeline
        let nodePipelineDescriptor = MTLRenderPipelineDescriptor()
        nodePipelineDescriptor.vertexFunction = nodeVertexFunction
        nodePipelineDescriptor.fragmentFunction = nodeFragmentFunction
        nodePipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        nodePipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        nodePipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        nodePipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        nodePipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        nodePipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        nodePipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        nodePipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add

        nodePipelineState = try device.makeRenderPipelineState(descriptor: nodePipelineDescriptor)

        // Create edge pipeline
        let edgePipelineDescriptor = MTLRenderPipelineDescriptor()
        edgePipelineDescriptor.vertexFunction = edgeVertexFunction
        edgePipelineDescriptor.fragmentFunction = edgeFragmentFunction
        edgePipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        edgePipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        edgePipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        edgePipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        edgePipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        edgePipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        edgePipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        edgePipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add

        edgePipelineState = try device.makeRenderPipelineState(descriptor: edgePipelineDescriptor)

        // Create quad vertex buffer for nodes (reusable)
        let quadVertices: [SIMD2<Float>] = [
            SIMD2<Float>(-1, -1),
            SIMD2<Float>(1, -1),
            SIMD2<Float>(-1, 1),
            SIMD2<Float>(1, -1),
            SIMD2<Float>(1, 1),
            SIMD2<Float>(-1, 1)
        ]

        guard let buffer = device.makeBuffer(
            bytes: quadVertices,
            length: quadVertices.count * MemoryLayout<SIMD2<Float>>.stride,
            options: .storageModeShared
        ) else {
            throw GraphRendererError.cannotCreateBuffer
        }

        nodeVertexBuffer = buffer
    }

    /// Render nodes to the command encoder
    public func renderNodes(
        _ nodes: [NodeDrawable],
        encoder: MTLRenderCommandEncoder,
        screenSize: SIMD2<Float>
    ) {
        encoder.setRenderPipelineState(nodePipelineState)
        encoder.setVertexBuffer(nodeVertexBuffer, offset: 0, index: 0)

        for node in nodes {
            var uniforms = NodeUniforms(
                center: node.position,
                size: node.size,
                color: node.color,
                screenSize: screenSize
            )

            encoder.setVertexBytes(&uniforms, length: MemoryLayout<NodeUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
    }

    /// Render edges to the command encoder
    public func renderEdges(
        _ edges: [EdgeDrawable],
        encoder: MTLRenderCommandEncoder,
        screenSize: SIMD2<Float>
    ) {
        encoder.setRenderPipelineState(edgePipelineState)

        for edge in edges {
            var uniforms = EdgeUniforms(
                start: edge.source,
                end: edge.target,
                thickness: edge.thickness,
                color: edge.color,
                screenSize: screenSize
            )

            encoder.setVertexBytes(&uniforms, length: MemoryLayout<EdgeUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }
}

// Uniform structures matching the Metal shader
struct NodeUniforms {
    var center: SIMD2<Float>
    var size: Float
    var color: SIMD4<Float>
    var screenSize: SIMD2<Float>
}

struct EdgeUniforms {
    var start: SIMD2<Float>
    var end: SIMD2<Float>
    var thickness: Float
    var color: SIMD4<Float>
    var screenSize: SIMD2<Float>
}

public enum GraphRendererError: Error {
    case cannotLoadShaders
    case cannotCreateBuffer
    case cannotCreatePipelineState
}
