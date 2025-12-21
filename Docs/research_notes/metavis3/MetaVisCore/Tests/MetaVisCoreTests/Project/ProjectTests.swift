import XCTest
@testable import MetaVisCore

final class ProjectTests: XCTestCase {
    
    func testProjectInitialization() {
        let id = UUID()
        let rootTimelineId = UUID()
        let now = Date()
        
        let project = Project(
            id: id,
            name: "Test Doc",
            mode: .documentary,
            createdAt: now,
            rootTimelineId: rootTimelineId
        )
        
        XCTAssertEqual(project.id, id)
        XCTAssertEqual(project.name, "Test Doc")
        XCTAssertEqual(project.mode, .documentary)
        XCTAssertEqual(project.rootTimelineId, rootTimelineId)
    }
    
    func testProjectModeDefaults() {
        XCTAssertEqual(ProjectMode.cinematic.defaultFrameRate, 23.976, accuracy: 0.001)
        XCTAssertEqual(ProjectMode.social.defaultFrameRate, 30.0, accuracy: 0.001)
        XCTAssertEqual(ProjectMode.laboratory.defaultFrameRate, 60.0, accuracy: 0.001)
    }
}
