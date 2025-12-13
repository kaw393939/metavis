import Foundation
import MetaVisCore

/// A feature/effect application in the editing timeline.
///
/// This is the user-facing, serializable representation of “apply feature X with parameters Y”.
public struct FeatureApplication: Codable, Sendable, Equatable {
    public let id: String
    public var parameters: [String: NodeValue]

    public init(id: String, parameters: [String: NodeValue] = [:]) {
        self.id = id
        self.parameters = parameters
    }
}
