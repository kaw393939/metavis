import XCTest
import Metal
import MetaVisCore
import MetaVisGraphics
@testable import MetaVisSimulation

final class LUTVerificationTests: XCTestCase {
    
    // Helper to generate a simple LUT string
    func generateIdentityCube(size: Int) -> Data {
        var str = "LUT_3D_SIZE \(size)\n"
        for z in 0..<size {
            for y in 0..<size {
                for x in 0..<size {
                    let r = Float(x) / Float(size - 1)
                    let g = Float(y) / Float(size - 1)
                    let b = Float(z) / Float(size - 1)
                    str += String(format: "%.5f %.5f %.5f\n", r, g, b)
                }
            }
        }
        return str.data(using: .utf8)!
    }
    
    func generateBlueTintCube(size: Int) -> Data {
         var str = "LUT_3D_SIZE \(size)\n"
         for z in 0..<size {
             for y in 0..<size {
                 for x in 0..<size {
                     let r = Float(x) / Float(size - 1)
                     let g = Float(y) / Float(size - 1)
                     let b = Float(z) / Float(size - 1)
                     // boost blue
                     str += String(format: "%.5f %.5f %.5f\n", r, g, b + 0.5) 
                 }
             }
         }
         return str.data(using: .utf8)!
    }
    
    func testLUTIdentity() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { return }
        
        let engine = try MetalSimulationEngine()
        try await engine.configure()
        
        // 1. Create Identity LUT (Small size 3 is enough to verify plumbing)
        let lutData = generateIdentityCube(size: 8)
        
        // 2. Build Graph: Source(Ramp) -> LUT
        // Using Linear Ramp (0.0 - 5.0).
        // LUT Apply shader expects 0-1 input.
        // We really should use a 0-1 test pattern.
        // 'source_test_color' is 0-1.
        
        let sourceNode = RenderNode(
            name: "Source",
            shader: "source_test_color",
            inputs: [:],
            parameters: [:]
        )
        
        let lutNode = RenderNode(
            name: "Apply LUT",
            shader: "lut_apply_3d",
            inputs: ["input": sourceNode.id],
            parameters: ["lut": .data(lutData)]
        )
        
        let graph = RenderGraph(nodes: [sourceNode, lutNode], rootNodeID: lutNode.id)
        let request = RenderRequest(
             graph: graph,
             time: .zero,
             quality: QualityProfile(name: "LUTTest", fidelity: .draft, resolutionHeight: 64, colorDepth: 32)
        )
        
        // 3. Render
        let result = try await engine.render(request: request)
        
        guard let outputData = result.imageBuffer else {
            XCTFail("No output")
            return
        }
        
        // 4. Verify
        // Identity LUT should produce exactly same output as input.
        // Or very close (interpolation error).
        // Since input is linear gradient and LUT is linear identity, error should be tiny.
        
        // Let's check a few pixels.
        // source_test_color(u) -> r=u, g=u*0.5, b=1-u
        
        let width = 256
        let outputFloats = outputData.withUnsafeBytes { ptr in
            Array(UnsafeBufferPointer(start: ptr.bindMemory(to: Float.self).baseAddress!, count: width * 4))
        }
        
        // Check middle pixel (u=0.5)
        let midIdx = 128
        let rObs = outputFloats[midIdx * 4 + 0]
        let gObs = outputFloats[midIdx * 4 + 1]
        let bObs = outputFloats[midIdx * 4 + 2]
        
        // Exp: r=0.5, g=0.25, b=0.5
        XCTAssertEqual(rObs, 0.5, accuracy: 0.05)
        XCTAssertEqual(gObs, 0.25, accuracy: 0.05)
        XCTAssertEqual(bObs, 0.5, accuracy: 0.05)
        
        print("✅ LUT Identity Test Passed. Mid Pixel: (\(rObs), \(gObs), \(bObs))")
    }
}
