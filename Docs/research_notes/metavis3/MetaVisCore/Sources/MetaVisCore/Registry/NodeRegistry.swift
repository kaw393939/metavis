import Foundation

/// Describes the interface and metadata of a Node type.
/// This is used by the UI to populate menus and by Agents to understand capabilities.
public struct NodeDefinition: Codable, Sendable, Identifiable {
    public var id: String { type }
    
    /// Unique type identifier (e.g. "core.color.aces_transform")
    public let type: String
    
    /// User-friendly name (e.g. "ACES Transform")
    public let displayName: String
    
    /// Grouping category (e.g. "Color", "Filter", "Compositing")
    public let category: String
    
    /// Description for tooltips and Agent context
    public let description: String
    
    /// Input ports defining the data requirements
    public let inputs: [NodePort]
    
    /// Output ports defining the data produced
    public let outputs: [NodePort]
    
    /// Keywords for search and discovery
    public let tags: [String]
    
    public init(
        type: String,
        displayName: String,
        category: String,
        description: String,
        inputs: [NodePort],
        outputs: [NodePort],
        tags: [String] = []
    ) {
        self.type = type
        self.displayName = displayName
        self.category = category
        self.description = description
        self.inputs = inputs
        self.outputs = outputs
        self.tags = tags
    }
}

/// A thread-safe registry for all available Node types.
public actor NodeRegistry {
    public static let shared = NodeRegistry()
    
    private var definitions: [String: NodeDefinition] = [:]
    
    public init() {}
    
    /// Register a new node definition.
    public func register(_ definition: NodeDefinition) {
        definitions[definition.type] = definition
    }
    
    /// Retrieve a definition by type.
    public func definition(for type: String) -> NodeDefinition? {
        return definitions[type]
    }
    
    /// List all registered definitions.
    public func allDefinitions() -> [NodeDefinition] {
        return Array(definitions.values).sorted { $0.displayName < $1.displayName }
    }
    
    /// Find definitions matching a category.
    public func definitions(in category: String) -> [NodeDefinition] {
        return definitions.values.filter { $0.category == category }
    }
}
