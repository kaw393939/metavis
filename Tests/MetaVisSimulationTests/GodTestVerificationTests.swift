import XCTest
import MetaVisCore
import MetaVisTimeline
import MetaVisSimulation
import MetaVisSession

final class GodTestVerificationTests: XCTestCase {
    
    func testTimelineCompilation() async throws {
        // 1. Build the "God Test" Timeline
        let timeline = GodTestBuilder.build()
        
        // 2. Setup Compiler
        let compiler = TimelineCompiler()
        let quality = QualityProfile(name: "Test", fidelity: .high, resolutionHeight: 1080, colorDepth: 8)
        
        // --- Check SMPTE (0-5s) at t=2.5s ---
        let request1 = try await compiler.compile(timeline: timeline, at: Time(seconds: 2.5), quality: quality)
        let graph1 = request1.graph
        
        // Verify we have a node with "fx_smpte_bars"
        let smpteNode = graph1.nodes.first(where: { $0.shader == "fx_smpte_bars" })
        XCTAssertNotNil(smpteNode, "Should contain SMPTE generator at 2.5s")
        
        // --- Check Macbeth (5-10s) at t=7.5s ---
        let request2 = try await compiler.compile(timeline: timeline, at: Time(seconds: 7.5), quality: quality)
        let graph2 = request2.graph
        
        let macbethNode = graph2.nodes.first(where: { $0.shader == "fx_macbeth" })
        XCTAssertNotNil(macbethNode, "Should contain Macbeth generator at 7.5s")
        
        // --- Check Zone Plate (10-15s) at t=12.5s ---
        let request3 = try await compiler.compile(timeline: timeline, at: Time(seconds: 12.5), quality: quality)
        let graph3 = request3.graph
        
        let zoneNode = graph3.nodes.first(where: { $0.shader == "fx_zone_plate" })
        XCTAssertNotNil(zoneNode, "Should contain Zone Plate generator at 12.5s")
        
        // Verify time parameter is bound
        if let node = zoneNode, let timeParam = node.parameters["time"] {
            if case .float(let t) = timeParam {
                XCTAssertEqual(t, 12.5, accuracy: 0.1)
            } else {
                XCTFail("Zone Plate time param should be float")
            }
        }
    }
}
