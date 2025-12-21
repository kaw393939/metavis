
// MARK: - Unified Procedural Field Engine (V2.0)

public struct ProceduralFieldDefinition: Codable {
    public let id: String
    public let graph: ProceduralGraph? // Optional for Phase 1 legacy support
    public let domain: ProceduralDomain?
    public let seed: ProceduralSeed?
    
    // Legacy/Simple support (Phase 1)
    public let patternType: String? // "PERLIN", "FBM", etc.
    public let parameters: [String: Float]?
    
    enum CodingKeys: String, CodingKey {
        case id, graph, domain, seed
        case patternType = "pattern_type"
        case parameters
    }
}

public struct ProceduralGraph: Codable {
    public let nodes: [ProceduralNode]
    public let output: String
}

public struct ProceduralNode: Codable {
    public let id: String
    public let op: String // "FBM", "ADD", "SIN", "COORD", etc.
    public let params: [String: Float]?
    public let inputs: [String]?
}

public struct ProceduralDomain: Codable {
    public let space: String // "OBJECT", "WORLD", "UV"
    public let scale: [Float]?
    public let offset: [Float]?
    public let rotation: [Float]? // Euler degrees
    public let warpStrength: Float?
}

public struct ProceduralSeed: Codable {
    public let mixMode: String // "SHOT_SEED", "GLOBAL_SEED", "FIXED"
    public let fixedValue: Int?
}
