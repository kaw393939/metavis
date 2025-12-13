import Foundation
import MetaVisCore

/// Represents a request to the Local LLM.
public struct LLMRequest: Sendable, Codable {
    public let systemPrompt: String
    public let userQuery: String
    public let context: String // JSON representation of Visual/Timeline context
    
    public init(systemPrompt: String = "You are Jarvis, a helpful video editing assistant.", userQuery: String, context: String) {
        self.systemPrompt = systemPrompt
        self.userQuery = userQuery
        self.context = context
    }
}

/// Represents a response from the Local LLM.
public struct LLMResponse: Sendable, Codable {
    public let text: String
    public let intentJSON: String? // Extracted JSON block if present
    public let latency: TimeInterval
}

/// The Service responsible for Text Generation.
/// Wraps a local CoreML Transformer (e.g. Llama-3-8B).
public actor LocalLLMService {
    
    public init() {}
    
    public func warmUp() async throws {
        // Load model...
    }
    
    /// Generates a response for the given request.
    public func generate(request: LLMRequest) async throws -> LLMResponse {
        let start = Date()
        
        // Mock Implementation for now.
        // In real life, we'd feed:
        // System: <request.systemPrompt>
        // Context: <request.context>
        // User: <request.userQuery>
        
        // Simulating "Thinking"
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        
        // Mock Logic: If query contains "blue", output JSON
        let responseText: String
        let json: String?
        
        if request.userQuery.lowercased().contains("blue") {
            responseText = "Here is the command to make it blue."
            json = """
            {
                "action": "color_grade",
                "target": "shirt",
                "params": { "hue": 0.6 }
            }
            """
        } else {
            responseText = "I'm not sure what you want to do."
            json = nil
        }
        
        let latency = Date().timeIntervalSince(start)
        return LLMResponse(text: responseText, intentJSON: json, latency: latency)
    }
}
