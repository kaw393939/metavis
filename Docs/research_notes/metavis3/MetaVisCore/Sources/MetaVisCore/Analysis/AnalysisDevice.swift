import Foundation

/// Represents a deterministic or AI-based analysis tool in the pipeline.
/// Used for QA, automated acceptance testing, and data collection.
public protocol AnalysisDevice: VirtualDevice {
    var category: AnalysisCategory { get }
    
    /// Runs analysis on a video asset.
    func analyze(videoURL: URL) async throws -> AnalysisResult
}

public enum AnalysisCategory: String, Codable, Sendable {
    case technical // Deterministic (Color, Bitrate, PSNR)
    case semantic  // AI (Scene classification, Object detection)
    case qualitative // LLM (Cinematic critique, "Vibe check")
}

public struct AnalysisResult: Codable, Sendable {
    public let deviceId: UUID
    public let deviceName: String
    public let score: Double? // 0.0 - 1.0 Normalized Score
    public let grade: String // A+, B, F
    public let summary: String
    public let metrics: [String: Double]
    public let metadata: [String: String]
    public let timestamp: Date
    
    public init(
        deviceId: UUID,
        deviceName: String,
        score: Double? = nil,
        grade: String,
        summary: String,
        metrics: [String: Double] = [:],
        metadata: [String: String] = [:],
        timestamp: Date = Date()
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.score = score
        self.grade = grade
        self.summary = summary
        self.metrics = metrics
        self.metadata = metadata
        self.timestamp = timestamp
    }
}
