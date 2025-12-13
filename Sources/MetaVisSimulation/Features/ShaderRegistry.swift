import Foundation

/// Resolves stable logical shader/pass names to concrete Metal compute function names.
public actor ShaderRegistry {
    public static let shared = ShaderRegistry()

    public enum Error: Swift.Error, Sendable, Equatable {
        case missingLogicalName(String)
    }

    private var aliases: [String: String] = [:]

    public init() {}

    public func register(logicalName: String, function: String) {
        aliases[logicalName] = function
    }

    public func resolve(_ logicalName: String) -> String? {
        aliases[logicalName]
    }

    public func resolveOrThrow(_ logicalName: String) throws -> String {
        guard let function = aliases[logicalName] else {
            throw Error.missingLogicalName(logicalName)
        }
        return function
    }

    public func allLogicalNames() -> [String] {
        aliases.keys.sorted()
    }
}
