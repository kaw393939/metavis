import Foundation
import MetaVisCore

public struct AskTheExpert: Sendable {
    private let device: any VirtualDevice

    public init(device: any VirtualDevice) {
        self.device = device
    }

    public func ask(prompt: String, system: String? = nil, imageData: Data? = nil, imageMimeType: String? = nil) async throws -> String {
        var params: [String: NodeValue] = ["prompt": .string(prompt)]
        if let system {
            params["system"] = .string(system)
        }
        if let imageData {
            params["imageData"] = .data(imageData)
        }
        if let imageMimeType {
            params["imageMimeType"] = .string(imageMimeType)
        }
        let out = try await device.perform(action: "ask_expert", with: params)
        guard case .string(let text)? = out["text"] else {
            throw NSError(domain: "MetaVisServices", code: 1, userInfo: [NSLocalizedDescriptionKey: "Gemini device returned no text"]) 
        }
        return text
    }
}
