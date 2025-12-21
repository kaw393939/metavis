import XCTest
@testable import MetaVisCore

final class NodeGraphCycleTests: XCTestCase {
    
    func testTreeCycleDetection() {
        var graph = ProjectGraph()
        
        // P1 -> P2 -> P3
        let p1 = Project(id: UUID(), name: "P1", mode: .cinematic)
        let p2 = Project(id: UUID(), name: "P2", mode: .cinematic)
        let p3 = Project(id: UUID(), name: "P3", mode: .cinematic)
        
        // Setup initial graph
        var p1_mod = p1
        p1_mod.imports = [ProjectImport(projectId: p2.id, namespace: "p2")]
        
        var p2_mod = p2
        p2_mod.imports = [ProjectImport(projectId: p3.id, namespace: "p3")]
        
        graph.add(p1_mod)
        graph.add(p2_mod)
        graph.add(p3)
        
        // Test: Adding P1 as dependency to P3 should be detected as cycle
        // P3 -> P1 (which goes -> P2 -> P3)
        let cycleDetected = graph.wouldCreateCycle(targetId: p3.id, importedId: p1.id)
        XCTAssertTrue(cycleDetected, "Should detect cycle P3 -> P1 -> P2 -> P3")
        
        // Test: Adding P3 as dependency to P1 (redundant but not cycle per se if DAG, but here imports are distinct edges)
        // If P1 imports P3, logic: P1 -> P3. P3 has no imports. No cycle back to P1.
        let cycleDetected2 = graph.wouldCreateCycle(targetId: p1.id, importedId: p3.id)
        XCTAssertFalse(cycleDetected2, "P1 importing P3 directly is fine (diamond dependency is allowed, cycles are not)")
    }
}
