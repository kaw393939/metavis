import XCTest
import CoreVideo
import MetaVisCore
import MetaVisTimeline
import MetaVisPerception
import MetaVisServices
@testable import MetaVisSession

final class ProjectSessionTests: XCTestCase {
    
    func testDispatchAction() async {
        let session = ProjectSession()
        
        // Setup Trace
        let trackId = UUID()
        let track = Track(id: trackId, name: "V1")
        // var initialState = await session.state 
        // We use dispatch to add track now
        await session.dispatch(.addTrack(track))
        
        
        // Action: Add Clip
        let clip = Clip(name: "Clip 1", asset: AssetReference(sourceFn: "file://"), startTime: .zero, duration: Time(seconds: 5))
        await session.dispatch(.addClip(clip, toTrackId: trackId))
        
        var state = await session.state
        XCTAssertEqual(state.timeline.tracks[0].clips.count, 1)
        XCTAssertEqual(state.timeline.tracks[0].clips[0].name, "Clip 1")
        
        // Undo
        await session.undo()
        state = await session.state
        XCTAssertEqual(state.timeline.tracks[0].clips.count, 0) // Undoing addClip removes clip but keeps track
        
        // Undo again should remove track
        await session.undo()
        state = await session.state
        XCTAssertEqual(state.timeline.tracks.count, 0)
        
        // Redo to add track
        await session.redo() 
        // Redo to add clip
        await session.redo()
        state = await session.state
        XCTAssertEqual(state.timeline.tracks[0].clips.count, 1)
    }
    
    func testProjectName() async {
        let session = ProjectSession()
        await session.dispatch(.setProjectName("My Movie"))
        
        let state = await session.state
        XCTAssertEqual(state.config.name, "My Movie")
        
        await session.undo()
        let oldState = await session.state
        XCTAssertEqual(oldState.config.name, "Untitled Project")
    }
    
    func testAnalyzeFrame() async {
         let session = ProjectSession()
         
         // Create dummy buffer
         let width = 100
         let height = 100
         var pixelBuffer: CVPixelBuffer?
         CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
         
         guard let pb = pixelBuffer else {
             XCTFail("Failed to create pixel buffer")
             return
         }
         
         // Initial state: no context
         let initialState = await session.state
         XCTAssertNil(initialState.visualContext)
         
         // Analyze
         await session.analyzeFrame(pixelBuffer: pb, time: 1.5)
         
         // Check state update
         let newState = await session.state
         XCTAssertNotNil(newState.visualContext)
         XCTAssertEqual(newState.visualContext?.timestamp, 1.5)
         XCTAssertNotNil(newState.visualContext?.subjects)
    }
    
    func testProcessCommand() async throws {
        let session = ProjectSession()
        
        // Mock query known to trigger the mock LLM
        let query = "change the shirt to blue"
        
        guard let intent = try await session.processCommand(query) else {
            XCTFail("Intent should not be nil")
            return
        }
        
        XCTAssertEqual(intent.action, .colorGrade)
        XCTAssertEqual(intent.target, "shirt")
    }
}
