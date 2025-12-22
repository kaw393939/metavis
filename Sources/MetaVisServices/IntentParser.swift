import Foundation

public enum IntentParserError: Error, LocalizedError, Sendable {
    case missingJSON
    case invalidUTF8
    case decodeFailed(String)
    case invalidIntent(String)

    public var errorDescription: String? {
        switch self {
        case .missingJSON:
            return "LLM response did not contain a JSON object"
        case .invalidUTF8:
            return "Failed to decode intent JSON as UTF-8"
        case .decodeFailed(let msg):
            return "Failed to decode intent JSON: \(msg)"
        case .invalidIntent(let msg):
            return "Intent failed validation: \(msg)"
        }
    }
}

/// Parses raw text from the LLM into structured UserIntents.
public struct IntentParser {
    
    public init() {}
    
    /// Extracts and decodes the JSON block from an LLM response.
    /// Expects the JSON to be markdown fenced or just a raw block.
    public func parse(response: String) -> UserIntent? {
        // 1. Find JSON block
        guard let jsonString = extractJSON(from: response) else { return nil }
        
        // 2. Decode
        guard let data = jsonString.data(using: .utf8) else { return nil }
        
        do {
            let intent = try JSONDecoder().decode(UserIntent.self, from: data)
            return intent
        } catch {
            print("Intent Parsing Failed: \(error)")
            // Fallback strategy could go here
            return nil
        }
    }

    /// Strict parsing for production intent application.
    ///
    /// - Returns: `nil` if the response contains no JSON at all.
    /// - Throws: `IntentParserError` if JSON exists but is invalid or fails validation.
    public func parseValidated(response: String) throws -> UserIntent? {
        guard let jsonString = extractJSON(from: response) else { return nil }
        guard let data = jsonString.data(using: .utf8) else { throw IntentParserError.invalidUTF8 }

        let intent: UserIntent
        do {
            intent = try JSONDecoder().decode(UserIntent.self, from: data)
        } catch {
            throw IntentParserError.decodeFailed(String(describing: error))
        }

        try validate(intent)
        return intent
    }

    private func validate(_ intent: UserIntent) throws {
        if intent.action == .unknown {
            throw IntentParserError.invalidIntent("action=unknown")
        }
        for (k, v) in intent.params {
            if !v.isFinite {
                throw IntentParserError.invalidIntent("param \(k) is not finite")
            }
        }
    }
    
    private func extractJSON(from text: String) -> String? {
        // Look for ```json ... ```
        let pattern = "```json(.*?)```"
        if let range = text.range(of: pattern, options: .regularExpression) {
            let match = text[range]
            // Strip fences
            let json = match.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return json
        }
        
        // Look for just { ... }
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }
        
        return nil
    }
}
