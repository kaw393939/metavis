import Foundation
@preconcurrency import Metal
import simd

public class ChartRenderer: @unchecked Sendable {
    private let device: MTLDevice
    private let rectPipelineState: MTLRenderPipelineState
    private let piePipelineState: MTLRenderPipelineState
    private let vertexBuffer: MTLBuffer

    public init(device: MTLDevice) throws {
        self.device = device

        // Load shader library
        let library: MTLLibrary
        if let bundlePath = Bundle.module.path(forResource: "ChartShaders", ofType: "metal"),
           let shaderSource = try? String(contentsOfFile: bundlePath) {
            library = try device.makeLibrary(source: shaderSource, options: nil)
        } else if let defaultLibrary = device.makeDefaultLibrary() {
            library = defaultLibrary
        } else {
            throw ChartRendererError.cannotLoadShaders
        }

        guard let rectVertex = library.makeFunction(name: "rect_vertex"),
              let rectFragment = library.makeFunction(name: "rect_fragment"),
              let pieVertex = library.makeFunction(name: "pie_vertex"),
              let pieFragment = library.makeFunction(name: "pie_fragment")
        else {
            throw ChartRendererError.cannotLoadShaders
        }

        // Rect Pipeline
        let rectDesc = MTLRenderPipelineDescriptor()
        rectDesc.vertexFunction = rectVertex
        rectDesc.fragmentFunction = rectFragment
        rectDesc.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        rectDesc.colorAttachments[0].isBlendingEnabled = true
        rectDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        rectDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha

        rectPipelineState = try device.makeRenderPipelineState(descriptor: rectDesc)

        // Pie Pipeline
        let pieDesc = MTLRenderPipelineDescriptor()
        pieDesc.vertexFunction = pieVertex
        pieDesc.fragmentFunction = pieFragment
        pieDesc.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        pieDesc.colorAttachments[0].isBlendingEnabled = true
        pieDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pieDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha

        piePipelineState = try device.makeRenderPipelineState(descriptor: pieDesc)

        // Quad Vertices
        let vertices: [SIMD2<Float>] = [
            SIMD2<Float>(-1, -1),
            SIMD2<Float>(1, -1),
            SIMD2<Float>(-1, 1),
            SIMD2<Float>(1, -1),
            SIMD2<Float>(1, 1),
            SIMD2<Float>(-1, 1)
        ]

        guard let buffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<SIMD2<Float>>.stride,
            options: .storageModeShared
        ) else {
            throw ChartRendererError.cannotCreateBuffer
        }
        vertexBuffer = buffer
    }

    public func render(
        elements: [ChartDrawable],
        encoder: MTLRenderCommandEncoder,
        screenSize: SIMD2<Float>
    ) {
        // Group by type to minimize state changes
        let bars = elements.filter { $0.type == .bar }
        let slices = elements.filter { $0.type == .pieSlice }

        // Render Bars
        if !bars.isEmpty {
            encoder.setRenderPipelineState(rectPipelineState)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

            for bar in bars {
                var uniforms = RectUniforms(
                    rect: bar.rect,
                    color: bar.color,
                    screenSize: screenSize
                )
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<RectUniforms>.stride, index: 1)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            }
        }

        // Render Pie Slices
        if !slices.isEmpty {
            encoder.setRenderPipelineState(piePipelineState)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

            for slice in slices {
                // Extract pie data from rect/value
                // rect.xy = center, rect.z = radius
                // value = startAngle, value2 = endAngle (need to pack this)
                // Wait, ChartDrawable definition needs to support this.
                // Let's assume rect.xy is center, rect.z is radius.
                // And we need start/end angle.
                // I'll update ChartDrawable to have specific fields or use 'value' for start and 'extra' for end.

                // For now, let's assume ChartDrawable has what we need.
                // I will update ChartDrawable definition in next step.

                var uniforms = PieUniforms(
                    center: SIMD2<Float>(slice.rect.x, slice.rect.y),
                    radius: slice.rect.z,
                    startAngle: slice.value, // Start Angle
                    endAngle: slice.extra, // End Angle
                    color: slice.color,
                    screenSize: screenSize
                )
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<PieUniforms>.stride, index: 1)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            }
        }
    }
}

struct RectUniforms {
    var rect: SIMD4<Float>
    var color: SIMD4<Float>
    var screenSize: SIMD2<Float>
}

struct PieUniforms {
    var center: SIMD2<Float>
    var radius: Float
    var startAngle: Float
    var endAngle: Float
    var color: SIMD4<Float>
    var screenSize: SIMD2<Float>
}

public enum ChartRendererError: Error {
    case cannotLoadShaders
    case cannotCreateBuffer
}
