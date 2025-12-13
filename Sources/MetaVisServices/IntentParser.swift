import Foundation

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
