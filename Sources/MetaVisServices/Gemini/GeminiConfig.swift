import Foundation

public struct GeminiConfig: Sendable, Codable, Equatable {
    public var apiKey: String
    public var baseURL: URL
    public var model: String
    public var rateLimitRPS: Double?
    public var rateLimitBurst: Double?

    /// Default config reads from environment variables:
    /// - `GEMINI_API_KEY` (required)
    /// - `API__GOOGLE_API_KEY` (accepted alias)
    /// - `GOOGLE_API_KEY` (accepted alias)
    /// - `GEMINI_BASE_URL` (optional; defaults to Google Generative Language API base)
    /// - `GEMINI_MODEL` (optional)
    /// - `GEMINI_RATE_LIMIT_RPS` (optional; requests per second; set <= 0 to disable)
    /// - `GEMINI_RATE_LIMIT_BURST` (optional; max burst; defaults to RPS if provided)
    public static func fromEnvironment() throws -> GeminiConfig {
        let rawApiKey =
            getenvString("GEMINI_API_KEY") ??
            getenvString("API__GOOGLE_API_KEY") ??
            getenvString("GOOGLE_API_KEY")

        // API keys should never contain whitespace; strip it defensively to avoid
        // copy/paste issues (embedded newlines, trailing spaces, etc.).
        let apiKey = rawApiKey?
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()

        guard let apiKey, !apiKey.isEmpty else {
            throw GeminiError.misconfigured("Missing GEMINI_API_KEY (or API__GOOGLE_API_KEY)")
        }

        let base = (getenvString("GEMINI_BASE_URL") ?? "https://generativelanguage.googleapis.com/v1beta")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: base) else {
            throw GeminiError.misconfigured("Invalid GEMINI_BASE_URL: \(base)")
        }

        // Default to a fast model; if it's not available for the configured API version,
        // GeminiClient will auto-resolve via ListModels.
        let model = (getenvString("GEMINI_MODEL") ?? "gemini-2.5-flash")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let rpsRaw = getenvString("GEMINI_RATE_LIMIT_RPS")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let burstRaw = getenvString("GEMINI_RATE_LIMIT_BURST")?.trimmingCharacters(in: .whitespacesAndNewlines)

        let rps = rpsRaw.flatMap(Double.init)
        let burst = burstRaw.flatMap(Double.init)

        let enabledRPS: Double?
        if let rps, rps > 0 {
            enabledRPS = rps
        } else {
            enabledRPS = nil
        }

        let enabledBurst: Double?
        if let enabledRPS {
            if let burst, burst > 0 {
                enabledBurst = burst
            } else {
                enabledBurst = enabledRPS
            }
        } else {
            enabledBurst = nil
        }

        return GeminiConfig(
            apiKey: apiKey,
            baseURL: baseURL,
            model: model,
            rateLimitRPS: enabledRPS,
            rateLimitBurst: enabledBurst
        )
    }

    public init(
        apiKey: String,
        baseURL: URL,
        model: String,
        rateLimitRPS: Double? = nil,
        rateLimitBurst: Double? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.rateLimitRPS = rateLimitRPS
        self.rateLimitBurst = rateLimitBurst
    }
}

private func getenvString(_ key: String) -> String? {
    guard let c = getenv(key) else { return nil }
    return String(cString: c)
}
