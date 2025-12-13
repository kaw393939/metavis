import XCTest
import Metal
import MetaVisCore
@testable import MetaVisSimulation

final class WaveformVerificationTests: XCTestCase {
    
    func testWaveformDiagonal() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { return }
        
        let engine = try MetalSimulationEngine()
        try await engine.configure()
        
        // 1. Source: Linear Ramp
        let sourceNode = RenderNode(
            name: "Ramp",
            shader: "source_linear_ramp",
            inputs: [:],
            parameters: [:]
        )
        
        // 2. Waveform Node
        let wfNode = WaveformNode.create(inputID: sourceNode.id)
        
        let graph = RenderGraph(nodes: [sourceNode, wfNode], rootNodeID: wfNode.id)
        let request = RenderRequest(
             graph: graph,
             time: .zero,
             quality: QualityProfile(name: "ScopeTest", fidelity: .draft, resolutionHeight: 256, colorDepth: 32)
        )
        
        // 3. Render
        let result = try await engine.render(request: request)
        
        guard let outputData = result.imageBuffer else {
            XCTFail("No output")
            return
        }
        
        // 4. Check Diagonal
        let width = 256
        let height = 256
        let floatCount = width * height * 4
        
        let floats = outputData.withUnsafeBytes { ptr in
            Array(UnsafeBufferPointer(start: ptr.bindMemory(to: Float.self).baseAddress!, count: floatCount))
        }
        
        // Verify Waveform Signal
        // Note: 'source_linear_ramp' generates a signal from 0.0 to 5.0 across the width.
        // We verify a sample point where the signal is within visible range (0.0 - 1.0).
        // At x=25: Value = (25/256) * 5.0 ~= 0.488.
        // Expected Y-Bucket = 0.488 * 255 ~= 124.
        
        let targetX = 25
        let targetY = 125 // Found at 125 in debug
        
        // Scan a small window to account for rounding/alignment
        var maxIntensity: Float = 0.0
        
        for y in (targetY-2)...(targetY+2) {
            let idx = (y * 256 + targetX) * 4
            let green = floats[idx + 1]
            maxIntensity = max(maxIntensity, green)
        }
        
        XCTAssertGreaterThan(maxIntensity, 0.1, "Waveform should be visible at x=\(targetX) (Expected ~0.5 value)")
        
        print("✅ Waveform Verified. Intensity at x=\(targetX): \(maxIntensity)")
    }
}
