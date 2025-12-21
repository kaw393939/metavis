import Foundation

public struct FootageIndexRecord: Codable, Sendable {
    public let clipId: UUID
    public let profile: MediaProfile
    public let tags: [String]
    // public let summary: ClipAnalysisSummary // Future
    
    public init(clipId: UUID = UUID(), profile: MediaProfile, tags: [String] = []) {
        self.clipId = clipId
        self.profile = profile
        self.tags = tags
    }
}
