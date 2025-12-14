import Foundation

/// A high-level output type representing a creator-facing deliverable.
///
/// v1 is intentionally minimal: it mainly drives naming/metadata while the export pipeline remains policy-driven.
public struct ExportDeliverable: Codable, Sendable, Equatable {
    public var id: String
    public var displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    public static let youtubeMaster = ExportDeliverable(id: "youtube_master", displayName: "YouTube Master")
    public static let reviewProxy = ExportDeliverable(id: "review_proxy", displayName: "Review Proxy")
}
