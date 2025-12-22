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

    func testAnalyzeFrame_throttlesUsingSimulationTime_notWallClock() async {
        let session = ProjectSession()

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
        guard let pb = pixelBuffer else {
            XCTFail("Failed to create pixel buffer")
            return
        }

        // First analysis should run.
        await session.analyzeFrame(pixelBuffer: pb, time: 0.0)
        let s1 = await session.state
        XCTAssertEqual(s1.visualContext?.timestamp, 0.0)

        // Too soon in simulation time; should be throttled and NOT update.
        await session.analyzeFrame(pixelBuffer: pb, time: 0.1)
        let s2 = await session.state
        XCTAssertEqual(s2.visualContext?.timestamp, 0.0)

        // Past the interval; should update.
        await session.analyzeFrame(pixelBuffer: pb, time: 0.3)
        let s3 = await session.state
        XCTAssertEqual(s3.visualContext?.timestamp, 0.3)
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

    func testProcessCommand_cancelsStaleRequests() async throws {
        let provider = DeterministicLLMProvider { req in
            if req.userQuery == "slow" {
                // Long enough that a second request can arrive and cancel this one.
                try await Task.sleep(nanoseconds: 300_000_000)
                return LLMResponse(text: "{\"action\":\"cut\",\"target\":\"clip\",\"params\":{}}", intentJSON: nil, latency: 0)
            }
            // Fast response with a valid intent JSON.
            return LLMResponse(text: "{\"action\":\"cut\",\"target\":\"clip\",\"params\":{}}", intentJSON: nil, latency: 0)
        }

        let session = ProjectSession(llm: provider)

        let slowTask = Task { try await session.processCommand("slow") }

        // Give the slow request time to start.
        try await Task.sleep(nanoseconds: 20_000_000)

        // New request should cancel the in-flight one.
        let intent = try await session.processCommand("fast")
        XCTAssertEqual(intent?.action, .cut)

        do {
            _ = try await slowTask.value
            XCTFail("Expected slow request to be cancelled")
        } catch is CancellationError {
            // expected
        }
    }

    func testProcessCommand_includesVisualContextInLLMRequestContext() async throws {
        let provider = DeterministicLLMProvider { _ in
            // Return any valid intent JSON; we only care about what context was sent.
            LLMResponse(text: "{\"action\":\"cut\",\"target\":\"clip\",\"params\":{}}", intentJSON: nil, latency: 0)
        }

        let session = ProjectSession(llm: provider)

        // Ensure visualContext exists.
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
        guard let pb = pixelBuffer else {
            XCTFail("Failed to create pixel buffer")
            return
        }
        await session.analyzeFrame(pixelBuffer: pb, time: 1.0)

        _ = try await session.processCommand("cut the clip")

        guard let last = await provider.lastSeenRequest() else {
            XCTFail("Expected provider to receive a request")
            return
        }
        XCTAssertTrue(last.context.contains("\"visualContext\""))
    }
}
