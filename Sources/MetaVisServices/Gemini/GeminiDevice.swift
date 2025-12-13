import Foundation
import MetaVisCore

/// Gemini (cloud) as a `VirtualDevice`.
///
/// Configuration:
/// - `GEMINI_API_KEY` (required)
/// - `GEMINI_BASE_URL` (optional)
/// - `GEMINI_MODEL` (optional)
public actor GeminiDevice: VirtualDevice {
    public nonisolated let id: UUID = UUID()
    public nonisolated let name: String = "Gemini Expert"
    public nonisolated let deviceType: DeviceType = .hardware

    public nonisolated let knowledgeBase: DeviceKnowledgeBase = DeviceKnowledgeBase(
        description: "Cloud expert model used for multimodal analysis (text/images/audio/video via extracted evidence).",
        educationalContext: "Use this device for second-opinion analysis, QA checks, and explaining observed issues. Keep prompts specific and include measurable expectations.",
        bestPractices: [
            "Send a small set of representative frames (key moments, transitions).",
            "Include deterministic metrics (duration, fps, size, expected patterns) in the prompt.",
            "Treat responses as advisory; validate locally when possible."
        ],
        warnings: [
            "Requires network access and a configured GEMINI_API_KEY.",
            "Do not send sensitive media unless you understand data handling."
        ]
    )

    private var config: GeminiConfig
    private var propertyStore: [String: NodeValue]

    public var properties: [String: NodeValue] {
        get async { propertyStore }
    }

    public nonisolated var actions: [String: ActionDefinition] {
        [
            "ask_expert": ActionDefinition(
                name: "ask_expert",
                description: "Ask Gemini a question and return a text answer.",
                parameters: [
                    "prompt": "string",
                    "system": "string (optional)"
                ]
            ),
            "reload_config": ActionDefinition(
                name: "reload_config",
                description: "Reload Gemini configuration from environment variables.",
                parameters: [:]
            )
        ]
    }

    public init(config: GeminiConfig? = nil) throws {
        let resolved = try (config ?? GeminiConfig.fromEnvironment())
        self.config = resolved
        self.propertyStore = [
            "model": .string(resolved.model),
            "baseURL": .string(resolved.baseURL.absoluteString)
        ]
    }

    @discardableResult
    public func perform(action: String, with params: [String: NodeValue]) async throws -> [String: NodeValue] {
        switch action {
        case "reload_config":
            self.config = try GeminiConfig.fromEnvironment()
            self.propertyStore["model"] = .string(self.config.model)
            self.propertyStore["baseURL"] = .string(self.config.baseURL.absoluteString)
            return ["ok": .bool(true)]

        case "ask_expert":
            guard case .string(let prompt)? = params["prompt"], !prompt.isEmpty else {
                throw GeminiError.misconfigured("Missing param: prompt")
            }
            let system: String?
            if case .string(let s)? = params["system"] {
                system = s
            } else {
                system = nil
            }

            let client = GeminiClient(config: config)
            let text = try await client.generateText(system: system, user: prompt)
            return ["text": .string(text)]

        default:
            throw GeminiError.misconfigured("Unknown action: \(action)")
        }
    }

    public func setProperty(_ key: String, to value: NodeValue) async throws {
        switch (key, value) {
        case ("model", .string(let model)):
            config.model = model
            propertyStore["model"] = .string(model)
        case ("baseURL", .string(let urlString)):
            guard let url = URL(string: urlString) else {
                throw GeminiError.misconfigured("Invalid baseURL")
            }
            config.baseURL = url
            propertyStore["baseURL"] = .string(url.absoluteString)
        default:
            propertyStore[key] = value
        }
    }
}
