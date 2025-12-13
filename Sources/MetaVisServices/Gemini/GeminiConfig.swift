import Foundation

public struct GeminiConfig: Sendable, Codable, Equatable {
    public var apiKey: String
    public var baseURL: URL
    public var model: String

    /// Default config reads from environment variables:
    /// - `GEMINI_API_KEY` (required)
    /// - `API__GOOGLE_API_KEY` (accepted alias)
    /// - `GOOGLE_API_KEY` (accepted alias)
    /// - `GEMINI_BASE_URL` (optional; defaults to Google Generative Language API base)
    /// - `GEMINI_MODEL` (optional)
    public static func fromEnvironment() throws -> GeminiConfig {
        let apiKey =
            getenvString("GEMINI_API_KEY") ??
            getenvString("API__GOOGLE_API_KEY") ??
            getenvString("GOOGLE_API_KEY")

        guard let apiKey, !apiKey.isEmpty else {
            throw GeminiError.misconfigured("Missing GEMINI_API_KEY (or API__GOOGLE_API_KEY)")
        }

        let base = getenvString("GEMINI_BASE_URL") ?? "https://generativelanguage.googleapis.com/v1beta"
        guard let baseURL = URL(string: base) else {
            throw GeminiError.misconfigured("Invalid GEMINI_BASE_URL: \(base)")
        }

        // Default to a fast model; if it's not available for the configured API version,
        // GeminiClient will auto-resolve via ListModels.
        let model = getenvString("GEMINI_MODEL") ?? "gemini-2.5-flash"

        return GeminiConfig(apiKey: apiKey, baseURL: baseURL, model: model)
    }

    public init(apiKey: String, baseURL: URL, model: String) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
    }
}

private func getenvString(_ key: String) -> String? {
    guard let c = getenv(key) else { return nil }
    return String(cString: c)
}
