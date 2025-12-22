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
    private let urlSession: URLSession
    private var client: GeminiClient

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
                    "system": "string (optional)",
                    "imageData": "data (optional; JPEG/PNG)",
                    "imageMimeType": "string (optional; e.g. image/jpeg)"
                ]
            ),
            "reload_config": ActionDefinition(
                name: "reload_config",
                description: "Reload Gemini configuration from environment variables.",
                parameters: [:]
            )
        ]
    }

    public init(config: GeminiConfig? = nil, urlSession: URLSession = .shared) throws {
        let resolved = try (config ?? GeminiConfig.fromEnvironment())
        self.config = resolved
        self.propertyStore = [
            "model": .string(resolved.model),
            "baseURL": .string(resolved.baseURL.absoluteString)
        ]
        self.urlSession = urlSession
        self.client = GeminiClient(config: resolved, urlSession: urlSession)
    }

    @discardableResult
    public func perform(action: String, with params: [String: NodeValue]) async throws -> [String: NodeValue] {
        switch action {
        case "reload_config":
            self.config = try GeminiConfig.fromEnvironment()
            self.propertyStore["model"] = .string(self.config.model)
            self.propertyStore["baseURL"] = .string(self.config.baseURL.absoluteString)
            self.client = GeminiClient(config: self.config, urlSession: urlSession)
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

            var parts: [GeminiGenerateContentRequest.Part] = []
            if let system, !system.isEmpty {
                parts.append(.text("SYSTEM: \(system)"))
            }
            parts.append(.text(prompt))

            if case .data(let data)? = params["imageData"], !data.isEmpty {
                let mimeType: String
                if case .string(let m)? = params["imageMimeType"], !m.isEmpty {
                    mimeType = m
                } else {
                    mimeType = "image/jpeg"
                }
                parts.append(.inlineData(mimeType: mimeType, dataBase64: data.base64EncodedString()))
            }

            let requestBody = GeminiGenerateContentRequest(contents: [
                .init(role: "user", parts: parts)
            ])

            let response = try await client.generateContent(requestBody)
            guard let text = response.primaryText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GeminiError.emptyResponse
            }
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
            client = GeminiClient(config: config, urlSession: urlSession)
        case ("baseURL", .string(let urlString)):
            guard let url = URL(string: urlString) else {
                throw GeminiError.misconfigured("Invalid baseURL")
            }
            config.baseURL = url
            propertyStore["baseURL"] = .string(url.absoluteString)
            client = GeminiClient(config: config, urlSession: urlSession)
        default:
            propertyStore[key] = value
        }
    }
}
