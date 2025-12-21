import Metal
import simd

/// A simple helper to draw a full-screen quad.
public class QuadMesh {
    
    public let vertexBuffer: MTLBuffer
    public let vertexCount: Int = 6
    
    public init(device: MTLDevice) {
        // Standard full-screen quad (2 triangles)
        // Position (XY), Texture Coordinate (UV)
        let vertices: [Float] = [
            // Triangle 1
            -1.0,  1.0, 0.0, 0.0, // Top Left
            -1.0, -1.0, 0.0, 1.0, // Bottom Left
             1.0, -1.0, 1.0, 1.0, // Bottom Right
             
            // Triangle 2
            -1.0,  1.0, 0.0, 0.0, // Top Left
             1.0, -1.0, 1.0, 1.0, // Bottom Right
             1.0,  1.0, 1.0, 0.0  // Top Right
        ]
        
        guard let buffer = device.makeBuffer(bytes: vertices,
                                             length: vertices.count * MemoryLayout<Float>.size,
                                             options: .storageModeShared) else {
            fatalError("Failed to create quad vertex buffer")
        }
        self.vertexBuffer = buffer
    }
    
    public func draw(encoder: MTLRenderCommandEncoder) {
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
    }
}
