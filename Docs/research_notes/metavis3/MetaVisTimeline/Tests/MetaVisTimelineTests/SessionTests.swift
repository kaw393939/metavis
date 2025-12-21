import XCTest
@testable import MetaVisTimeline
import MetaVisCore

final class SessionTests: XCTestCase {
    
    func testSessionInitialization() {
        let session = MetaVisSession()
        XCTAssertNotNil(session.id)
        XCTAssertEqual(session.activeTimeline.name, "Main")
    }
    
    func testShadowTimelineForking() {
        // 1. Setup a session with a timeline
        var session = MetaVisSession()
        let originalID = session.activeTimeline.id
        
        // 2. Create a shadow timeline (fork)
        let shadowID = session.createShadowTimeline(name: "Agent Experiment")
        
        // 3. Verify separation
        XCTAssertNotEqual(originalID, shadowID)
        XCTAssertEqual(session.shadowTimelines.count, 1)
        XCTAssertEqual(session.shadowTimelines[shadowID]?.name, "Agent Experiment")
        
        // 4. Verify Content Copy
        // Add a track to main, fork, verify shadow has it
        // (Requires Track init logic, skipping for now as we just test the Session struct logic)
    }
    
    func testCastRegistryIntegration() {
        var session = MetaVisSession()
        let personID = UUID()
        
        session.cast.register(id: personID, name: "Alice")
        
        XCTAssertEqual(session.cast.name(for: personID), "Alice")
    }
}
