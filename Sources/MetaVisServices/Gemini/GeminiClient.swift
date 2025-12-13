import Foundation

public struct GeminiClient: Sendable {
    private let config: GeminiConfig
    private let urlSession: URLSession

    public init(config: GeminiConfig, urlSession: URLSession = .shared) {
        self.config = config
        self.urlSession = urlSession
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
        } catch let GeminiError.http(statusCode, _) where statusCode == 404 {
            // Many 404s include guidance to call ListModels. Do a single retry with a discovered model.
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

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

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
