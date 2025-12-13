import Foundation

public enum GeminiError: Error, Sendable, CustomStringConvertible {
    case misconfigured(String)
    case http(statusCode: Int, body: String?)
    case network(String)
    case decode(String)
    case emptyResponse

    public var description: String {
        switch self {
        case .misconfigured(let msg):
            return "Gemini misconfigured: \(msg)"
        case .http(let code, let body):
            return "Gemini HTTP \(code)\(body.map { ": \($0)" } ?? "")"
        case .network(let msg):
            return "Gemini network error: \(msg)"
        case .decode(let msg):
            return "Gemini decode error: \(msg)"
        case .emptyResponse:
            return "Gemini returned empty response"
        }
    }
}
