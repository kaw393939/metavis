import Foundation

/// Abstraction over any LLM backend (local heuristics, on-device CoreML, or cloud).
///
/// This protocol exists so `MetaVisSession` can be decoupled from any concrete LLM implementation
/// and so tests can inject deterministic providers.
public protocol LLMProvider: Sendable {
    func generate(request: LLMRequest) async throws -> LLMResponse
}
