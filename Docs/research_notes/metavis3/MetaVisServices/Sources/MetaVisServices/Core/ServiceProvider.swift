import Foundation

/// The contract that all AI service providers must adhere to.
public protocol ServiceProvider: Sendable {
    /// Unique identifier for the provider (e.g., "google.vertex", "elevenlabs")
    var id: String { get }
    
    /// The set of capabilities this provider supports.
    var capabilities: Set<ServiceCapability> { get }
    
    /// Initialize the provider with configuration.
    func initialize(loader: ConfigurationLoader) async throws
    
    /// Execute a generation request.
    func generate(request: GenerationRequest) -> AsyncThrowingStream<ServiceEvent, Error>
}
