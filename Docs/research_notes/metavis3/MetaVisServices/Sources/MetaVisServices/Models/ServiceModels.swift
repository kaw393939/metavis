import Foundation

// MARK: - Enums

public enum ServiceCapability: String, Hashable, Codable, Sendable {
    case textGeneration
    case imageGeneration
    case videoGeneration
    case audioGeneration
    case speechSynthesis
    case speechToSpeech
    case sceneAnalysis
}

public enum ProviderType: String, Codable, Sendable {
    case google
    case elevenLabs
    case ligm
}

public enum ServiceStatus: String, Codable, Sendable {
    case success
    case failure
    case processing
}

public enum ServiceEvent: Sendable {
    case progress(Double)
    case message(String)
    case completion(GenerationResponse)
}

public enum ArtifactType: String, Codable, Sendable {
    case video
    case audio
    case image
    case text
}

// MARK: - Errors

public enum ServiceError: Error {
    case configurationError(String)
    case providerUnavailable(String)
    case unsupportedCapability(ServiceCapability)
    case requestFailed(String)
    case decodingError(String)
}

// MARK: - Structs

public struct GenerationRequest: Codable, Sendable {
    public let id: UUID
    public let type: ServiceCapability
    public let prompt: String
    public let parameters: [String: ServiceParameterValue]
    public let context: [String: ServiceParameterValue]?
    
    public init(
        id: UUID = UUID(),
        type: ServiceCapability,
        prompt: String,
        parameters: [String: ServiceParameterValue] = [:],
        context: [String: ServiceParameterValue]? = nil
    ) {
        self.id = id
        self.type = type
        self.prompt = prompt
        self.parameters = parameters
        self.context = context
    }
}

public struct GenerationResponse: Codable, Sendable {
    public let id: UUID
    public let requestId: UUID
    public let status: ServiceStatus
    public let artifacts: [ServiceArtifact]
    public let metrics: ServiceMetrics
    
    public init(
        id: UUID = UUID(),
        requestId: UUID,
        status: ServiceStatus,
        artifacts: [ServiceArtifact],
        metrics: ServiceMetrics
    ) {
        self.id = id
        self.requestId = requestId
        self.status = status
        self.artifacts = artifacts
        self.metrics = metrics
    }
}

public struct ServiceArtifact: Codable, Sendable {
    public let type: ArtifactType
    public let uri: URL
    public let metadata: [String: String]
    
    public init(type: ArtifactType, uri: URL, metadata: [String: String] = [:]) {
        self.type = type
        self.uri = uri
        self.metadata = metadata
    }
}

public struct ServiceMetrics: Codable, Sendable {
    public let latency: TimeInterval
    public let tokenCount: Int
    public let costEstimate: Double
    
    public init(latency: TimeInterval, tokenCount: Int = 0, costEstimate: Double = 0.0) {
        self.latency = latency
        self.tokenCount = tokenCount
        self.costEstimate = costEstimate
    }
}

// MARK: - Helpers

public enum ServiceParameterValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([ServiceParameterValue])
    case dictionary([String: ServiceParameterValue])
    
    public var value: Any {
        switch self {
        case .string(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .bool(let v): return v
        case .array(let v): return v.map { $0.value }
        case .dictionary(let v): return v.mapValues { $0.value }
        }
    }
}
