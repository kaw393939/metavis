import Foundation

/// The main entry point for the MetaVisServices module.
/// Orchestrates requests to the appropriate providers.
public actor ServiceOrchestrator {
    
    private var providers: [String: ServiceProvider] = [:]
    private let configLoader: ConfigurationLoader
    
    public init() {
        self.configLoader = ConfigurationLoader()
    }
    
    /// Registers a provider and initializes it.
    public func register(provider: ServiceProvider) async throws {
        var p = provider
        try await p.initialize(loader: configLoader)
        providers[provider.id] = p
    }
    
    /// Routes a request to a capable provider.
    public func generate(request: GenerationRequest) -> AsyncThrowingStream<ServiceEvent, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // 1. Find a provider that supports the capability
                    guard let provider = providers.values.first(where: { $0.capabilities.contains(request.type) }) else {
                        throw ServiceError.unsupportedCapability(request.type)
                    }
                    
                    // 2. Execute
                    for try await event in provider.generate(request: request) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Retrieves a specific provider by ID.
    public func getProvider(id: String) -> ServiceProvider? {
        return providers[id]
    }
}
