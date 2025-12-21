import XCTest
@testable import MetaVisServices

// Mock Provider for Testing
struct MockProvider: ServiceProvider {
    let id = "mock-provider"
    let capabilities: Set<ServiceCapability> = [.textGeneration, .imageGeneration]
    
    func initialize(loader: ConfigurationLoader) async throws {
        // No-op
    }
    
    func generate(request: GenerationRequest) -> AsyncThrowingStream<ServiceEvent, Error> {
        return AsyncThrowingStream { continuation in
            if request.prompt == "fail" {
                continuation.finish(throwing: ServiceError.requestFailed("Mock failure"))
                return
            }
            
            continuation.yield(.progress(0.5))
            
            let response = GenerationResponse(
                requestId: request.id,
                status: .success,
                artifacts: [
                    ServiceArtifact(type: .text, uri: URL(string: "memory://result")!)
                ],
                metrics: ServiceMetrics(latency: 0.1)
            )
            continuation.yield(.completion(response))
            continuation.finish()
        }
    }
}

final class ServiceOrchestratorTests: XCTestCase {
    
    var orchestrator: ServiceOrchestrator!
    
    override func setUp() {
        super.setUp()
        orchestrator = ServiceOrchestrator()
    }
    
    func testRegisterAndRetrieveProvider() async throws {
        let mock = MockProvider()
        try await orchestrator.register(provider: mock)
        
        let retrieved = await orchestrator.getProvider(id: "mock-provider")
        XCTAssertNotNil(retrieved)
    }
    
    func testGenerate_Success() async throws {
        let mock = MockProvider()
        try await orchestrator.register(provider: mock)
        
        let request = GenerationRequest(type: .textGeneration, prompt: "Hello")
        
        var receivedProgress = false
        var receivedCompletion = false
        
        for try await event in orchestrator.generate(request: request) {
            switch event {
            case .progress:
                receivedProgress = true
            case .completion(let response):
                XCTAssertEqual(response.status, .success)
                receivedCompletion = true
            case .message: break
            }
        }
        
        XCTAssertTrue(receivedProgress)
        XCTAssertTrue(receivedCompletion)
    }
    
    func testGenerate_UnsupportedCapability() async throws {
        let mock = MockProvider()
        try await orchestrator.register(provider: mock)
        
        // Mock only supports text/image, request video
        let request = GenerationRequest(type: .videoGeneration, prompt: "Make a movie")
        
        do {
            for try await _ in orchestrator.generate(request: request) {}
            XCTFail("Should have thrown unsupportedCapability")
        } catch ServiceError.unsupportedCapability(let cap) {
            XCTAssertEqual(cap, .videoGeneration)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }
    
    func testGenerate_ProviderFailure() async throws {
        let mock = MockProvider()
        try await orchestrator.register(provider: mock)
        
        let request = GenerationRequest(type: .textGeneration, prompt: "fail")
        
        do {
            for try await _ in orchestrator.generate(request: request) {}
            XCTFail("Should have thrown requestFailed")
        } catch ServiceError.requestFailed(let msg) {
            XCTAssertEqual(msg, "Mock failure")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }
    
    func testConcurrency_MultipleRequests() async throws {
        let mock = MockProvider()
        try await orchestrator.register(provider: mock)
        
        // Fire off 100 requests concurrently
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    let req = GenerationRequest(type: .textGeneration, prompt: "Req \(i)")
                    for try await _ in self.orchestrator.generate(request: req) {}
                }
            }
            
            try await group.waitForAll()
        }
    }
}
