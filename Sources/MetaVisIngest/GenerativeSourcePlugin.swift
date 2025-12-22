import Foundation
import MetaVisCore

public protocol GenerativeSourcePlugin: Sendable {
    var id: String { get }

    func canHandle(action: String, params: [String: NodeValue]) -> Bool

    func perform(action: String, params: [String: NodeValue]) async throws -> [String: NodeValue]
}
