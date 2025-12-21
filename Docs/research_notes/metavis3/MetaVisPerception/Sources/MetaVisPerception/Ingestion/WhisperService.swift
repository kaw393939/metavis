import Foundation

public struct TranscriptionSegment: Codable, Sendable {
    public let id: Int
    public let start: Double
    public let end: Double
    public let text: String
}

public protocol TranscriptionService {
    func transcribe(audioURL: URL) async throws -> [TranscriptionSegment]
}

public class MockWhisperService: TranscriptionService {
    public init() {}
    
    public func transcribe(audioURL: URL) async throws -> [TranscriptionSegment] {
        // Simulate processing time
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        return [
            TranscriptionSegment(id: 0, start: 0.0, end: 2.0, text: "Hello, this is a simulation."),
            TranscriptionSegment(id: 1, start: 2.5, end: 5.0, text: "We are testing the perception engine."),
            TranscriptionSegment(id: 2, start: 5.5, end: 8.0, text: "Volumetric data loaded successfully.")
        ]
    }
}
