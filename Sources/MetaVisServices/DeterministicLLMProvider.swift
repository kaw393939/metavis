import Foundation

/// Deterministic LLM provider for unit tests.
///
/// - It can simulate latency (including a slow first request) without using wall-clock sleeps in tests.
/// - It can be used to validate cancellation semantics.
public actor DeterministicLLMProvider: LLMProvider {

    public typealias Handler = @Sendable (LLMRequest) async throws -> LLMResponse

    private let handler: Handler
    private var lastRequest: LLMRequest?

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    public func generate(request: LLMRequest) async throws -> LLMResponse {
        lastRequest = request
        try Task.checkCancellation()
        return try await handler(request)
    }

    public func lastSeenRequest() -> LLMRequest? {
        lastRequest
    }
}
