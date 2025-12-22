import Foundation

public struct GeminiClient: Sendable {
    private let config: GeminiConfig
    private let urlSession: URLSession
    private let rateLimiter: TokenBucket?

    public init(config: GeminiConfig, urlSession: URLSession = .shared) {
        self.config = config
        self.urlSession = urlSession

        if let rps = config.rateLimitRPS, rps > 0 {
            let burst = config.rateLimitBurst ?? rps
            self.rateLimiter = TokenBucket(ratePerSecond: rps, burst: burst)
        } else {
            self.rateLimiter = nil
        }
    }

    public func generateText(system: String? = nil, user: String) async throws -> String {
        var parts: [GeminiGenerateContentRequest.Part] = []
        if let system, !system.isEmpty {
            parts.append(.text("SYSTEM: \(system)"))
        }
        parts.append(.text(user))

        let requestBody = GeminiGenerateContentRequest(contents: [
            .init(role: "user", parts: parts)
        ])

        let response = try await generateContent(requestBody)
        guard let text = response.primaryText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GeminiError.emptyResponse
        }
        return text
    }

    public func generateContent(_ body: GeminiGenerateContentRequest) async throws -> GeminiGenerateContentResponse {
        // Try configured model first; if it 404s, ListModels and retry once.
        do {
            return try await generateContent(body, model: config.model)
        } catch let GeminiError.http(statusCode, _) where statusCode == 404 || statusCode == 400 {
            // Some environments return 400 INVALID_ARGUMENT for an unavailable/unknown model name
            // (instead of 404). Do a single retry with a discovered model.
            let resolved = try await resolveGenerateContentModel(preferContains: ["gemini", "flash", "pro"])
            return try await generateContent(body, model: resolved)
        } catch {
            throw error
        }
    }

    private func generateContent(_ body: GeminiGenerateContentRequest, model: String) async throws -> GeminiGenerateContentResponse {
        let modelPath = "models/\(model):generateContent"
        let url = config.baseURL
            .appendingPathComponent(modelPath)
            .appending(queryItems: [URLQueryItem(name: "key", value: config.apiKey)])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let snakeBody = try encode(body, style: .snakeCase)

        do {
            return try await send(request: request, body: snakeBody, fallbackBody: body)
        } catch let GeminiError.http(statusCode, _) where statusCode == 400 {
            // Some Gemini endpoints reject snake_case fields like inline_data/mime_type and expect
            // camelCase inlineData/mimeType. Retry once with an alternate encoding.
            let camelBody = try encode(body, style: .camelCase)
            return try await send(request: request, body: camelBody, fallbackBody: nil)
        }
    }

    private enum BodyStyle {
        case snakeCase
        case camelCase
    }

    private func encode(_ body: GeminiGenerateContentRequest, style: BodyStyle) throws -> Data {
        let encoder = JSONEncoder()
        switch style {
        case .snakeCase:
            return try encoder.encode(body)
        case .camelCase:
            return try encoder.encode(CamelCaseGenerateContentRequest(from: body))
        }
    }

    private func send(
        request baseRequest: URLRequest,
        body: Data,
        fallbackBody: GeminiGenerateContentRequest?
    ) async throws -> GeminiGenerateContentResponse {
        // Optional API rate limiting (configured via env).
        try await rateLimiter?.acquire(tokens: 1)

        var request = baseRequest
        request.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            // Avoid leaking query-string API keys in thrown URL errors.
            throw GeminiError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw GeminiError.http(statusCode: -1, body: nil)
        }

        if !(200...299).contains(http.statusCode) {
            let bodyStr = String(data: data, encoding: .utf8)
            throw GeminiError.http(statusCode: http.statusCode, body: bodyStr)
        }

        do {
            return try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)
        } catch {
            throw GeminiError.decode(String(describing: error))
        }
    }

    private func resolveGenerateContentModel(preferContains: [String]) async throws -> String {
        let models = try await listModels()
        let candidates = models.filter { $0.supportedGenerationMethods.contains("generateContent") }
        if candidates.isEmpty {
            throw GeminiError.misconfigured("No models support generateContent")
        }

        func score(_ name: String) -> Int {
            let n = name.lowercased()
            var s = 0
            for (i, token) in preferContains.enumerated() {
                if n.contains(token.lowercased()) { s += (preferContains.count - i) }
            }
            return s
        }

        let best = candidates.max { score($0.name) < score($1.name) } ?? candidates[0]
        // API returns full names like "models/xyz"; we want the segment after "models/".
        if best.name.hasPrefix("models/") {
            return String(best.name.dropFirst("models/".count))
        }
        return best.name
    }

    private func listModels() async throws -> [GeminiModelInfo] {
        let url = config.baseURL
            .appendingPathComponent("models")
            .appending(queryItems: [URLQueryItem(name: "key", value: config.apiKey)])

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw GeminiError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw GeminiError.http(statusCode: -1, body: nil)
        }
        if !(200...299).contains(http.statusCode) {
            let bodyStr = String(data: data, encoding: .utf8)
            throw GeminiError.http(statusCode: http.statusCode, body: bodyStr)
        }
        do {
            let decoded = try JSONDecoder().decode(GeminiListModelsResponse.self, from: data)
            return decoded.models
        } catch {
            throw GeminiError.decode(String(describing: error))
        }
    }
}

private struct GeminiListModelsResponse: Decodable {
    let models: [GeminiModelInfo]
}

private struct GeminiModelInfo: Decodable {
    let name: String
    let supportedGenerationMethods: [String]
}

private extension URL {
    func appending(queryItems: [URLQueryItem]) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        var existing = components.queryItems ?? []
        existing.append(contentsOf: queryItems)
        components.queryItems = existing
        return components.url ?? self
    }
}

// MARK: - CamelCase request fallback

private struct CamelCaseGenerateContentRequest: Encodable {
    struct Content: Encodable {
        var role: String?
        var parts: [Part]
    }

    enum Part: Encodable {
        case text(String)
        case inlineData(mimeType: String, data: String)
        case fileData(mimeType: String, fileUri: String)

        private enum CodingKeys: String, CodingKey {
            case text
            case inlineData
            case fileData
        }

        private enum InlineDataKeys: String, CodingKey {
            case mimeType
            case data
        }

        private enum FileDataKeys: String, CodingKey {
            case mimeType
            case fileUri
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode(text, forKey: .text)
            case .inlineData(let mimeType, let data):
                var nested = container.nestedContainer(keyedBy: InlineDataKeys.self, forKey: .inlineData)
                try nested.encode(mimeType, forKey: .mimeType)
                try nested.encode(data, forKey: .data)
            case .fileData(let mimeType, let fileUri):
                var nested = container.nestedContainer(keyedBy: FileDataKeys.self, forKey: .fileData)
                try nested.encode(mimeType, forKey: .mimeType)
                try nested.encode(fileUri, forKey: .fileUri)
            }
        }
    }

    var contents: [Content]

    init(from body: GeminiGenerateContentRequest) {
        self.contents = body.contents.map { content in
            Content(
                role: content.role,
                parts: content.parts.map { part in
                    switch part {
                    case .text(let t):
                        return .text(t)
                    case .inlineData(let mimeType, let dataBase64):
                        return .inlineData(mimeType: mimeType, data: dataBase64)
                    case .fileData(let mimeType, let fileUri):
                        return .fileData(mimeType: mimeType, fileUri: fileUri)
                    }
                }
            )
        }
    }
}
