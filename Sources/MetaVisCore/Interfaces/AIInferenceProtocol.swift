import Foundation

/// Defines the hardware compute units available for inference.
public enum AIComputeUnit: Sendable, Codable {
    case all // CPU + GPU + Neural Engine
    case cpuOnly
    case cpuAndGPU
    case neuralEngineOnly // Forced ANE
}

/// A generic request for an AI inference job.
public protocol AIInferenceRequest: Sendable {
    var id: UUID { get }
    var priority: TaskPriority { get }
}

/// A generic result from an AI inference job.
public protocol AIInferenceResult: Sendable {
    var id: UUID { get }
    var processingTime: TimeInterval { get }
}

/// Protocol defining a service capable of performing AI inference.
public protocol AIInferenceService: Actor {
    /// The friendly name of the service (e.g. "VisionService", "LlamaService").
    var name: String { get }
    
    /// Checks if the service is supported on the current hardware.
    func isSupported() async -> Bool
    
    /// Warps up the model/service (loads weights, compiles graph).
    func warmUp() async throws
    
    /// Unloads resources to free memory.
    func coolDown() async
    
    /// Performs inference.
    func infer<Request: AIInferenceRequest, Result: AIInferenceResult>(request: Request) async throws -> Result
}
