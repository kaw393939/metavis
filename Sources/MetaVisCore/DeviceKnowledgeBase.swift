import Foundation

/// "Documentation as Code".
/// Holds the educational context for a Virtual Device or Action.
public struct DeviceKnowledgeBase: Sendable, Codable {
    public let description: String
    public let educationalContext: String
    public let bestPractices: [String]
    public let warnings: [String]
    
    public init(
        description: String,
        educationalContext: String = "",
        bestPractices: [String] = [],
        warnings: [String] = []
    ) {
        self.description = description
        self.educationalContext = educationalContext
        self.bestPractices = bestPractices
        self.warnings = warnings
    }
}

/// Hints for the Agent on how to use a specific action safely.
public enum AgentSafetyLevel: String, Codable, Sendable {
    case safe           // Can perform without asking
    case confirm        // Ask user first ("This will change the look")
    case expertOnly     // High risk, explain thoroughly
}
