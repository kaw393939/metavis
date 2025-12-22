import Foundation
import MetaVisCore

public struct NoiseGeneratorPlugin: GenerativeSourcePlugin {
    public let id: String = "noise"

    public init() {}

    public func canHandle(action: String, params: [String : NodeValue]) -> Bool {
        guard action == "generate" else { return false }
        guard case .string(let prompt) = params["prompt"] else { return false }
        let p = prompt.lowercased()
        return p.contains("noise") || p.contains("starfield")
    }

    public func perform(action: String, params: [String : NodeValue]) async throws -> [String : NodeValue] {
        guard action == "generate" else {
            throw NSError(domain: "DeviceError", code: 404, userInfo: [NSLocalizedDescriptionKey: "Action not found"])
        }

        let assetId = UUID().uuidString

        var promptEncoded: String = ""
        if case .string(let prompt) = params["prompt"] {
            promptEncoded = prompt.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        }

        // Route to an existing procedural video source supported by the render pipeline.
        // Starfield is deterministic given its parameters and acts as a noise-like generator.
        let sourceUrl = "ligm://video/starfield?prompt=\(promptEncoded)"

        return [
            "assetId": .string(assetId),
            "sourceUrl": .string(sourceUrl)
        ]
    }
}
