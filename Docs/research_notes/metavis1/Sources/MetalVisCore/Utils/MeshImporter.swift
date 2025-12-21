import Foundation
import Metal
import simd

public struct MeshData: Codable {
    public struct Vertex: Codable {
        public let x: Float
        public let y: Float
    }
    
    public let width: Int
    public let height: Int
    public let vertices: [Vertex]
}

public class MeshImporter {
    public static func loadMesh(from jsonPath: String, device: MTLDevice) throws -> MTLBuffer? {
        let url = URL(fileURLWithPath: jsonPath)
        let data = try Data(contentsOf: url)
        let meshData = try JSONDecoder().decode(MeshData.self, from: data)
        
        if meshData.vertices.isEmpty {
            return nil
        }
        
        // Convert to Metal vertices
        // We'll use a simple format: float2 position, float2 texCoord
        // Position will be normalized -1 to 1 (NDC)
        // TexCoord will be 0 to 1
        
        struct MeshVertex {
            var position: SIMD2<Float>
            var texCoord: SIMD2<Float>
        }
        
        var metalVertices: [MeshVertex] = []
        
        for v in meshData.vertices {
            // Input is 0-1 (y down?)
            // Metal NDC is -1 to 1 (y up)
            // Let's map 0..1 to -1..1
            // x: 0 -> -1, 1 -> 1  => x * 2 - 1
            // y: 0 -> 1, 1 -> -1  => (1 - y) * 2 - 1  (flip Y)
            
            let ndcX = v.x * 2.0 - 1.0
            let ndcY = (1.0 - v.y) * 2.0 - 1.0
            
            metalVertices.append(MeshVertex(
                position: SIMD2(ndcX, ndcY),
                texCoord: SIMD2(v.x, v.y)
            ))
        }
        
        return device.makeBuffer(
            bytes: metalVertices,
            length: metalVertices.count * MemoryLayout<MeshVertex>.stride,
            options: .storageModeShared
        )
    }
}
