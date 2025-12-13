import Foundation
import MetaVisCore
// Note: AssetReference is in MetaVisTimeline but we avoid that dependency here
// Just return asset IDs as strings, caller constructs AssetReference if needed


public actor LIGMDevice: VirtualDevice {
    public nonisolated let id: UUID = UUID()
    public nonisolated let name: String = "LIGM Generator"
    public nonisolated let deviceType: DeviceType = .generator
    
    public nonisolated let knowledgeBase = DeviceKnowledgeBase(
        description: "Local Image Generation Module",
        educationalContext: "Uses Stable Diffusion to generate images locally. Does not upload data.",
        bestPractices: ["Use descriptive prompts", "Specify style keywords like 'Cinematic' or 'ACEScg'"]
    )
    
    public var properties: [String: NodeValue] = [
        "model_version": .string("v1.0-turbo")
    ]
    
    public let actions: [String: ActionDefinition] = [
        "generate": ActionDefinition(
            name: "Generate Image",
            description: "Generates an image from a prompt",
            parameters: ["prompt": "String"]
        )
    ]
    
    public init() {}
    
    public func perform(action: String, with params: [String : NodeValue]) async throws -> [String : NodeValue] {
        guard action == "generate" else {
            throw NSError(domain: "DeviceError", code: 404, userInfo: [NSLocalizedDescriptionKey: "Action not found"])
        }
        
        guard case .string(let prompt) = params["prompt"] else {
            throw NSError(domain: "DeviceError", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing prompt"])
        }
        
        // Simulate Generation Delay
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        // In a real implementation, this would call CoreML/StableDiffusion
        // For Mock/Lab, we return a synthetic Asset ID
        let assetId = UUID().uuidString
        let mockUrl = "ligm://generated/\(assetId)?prompt=\(prompt.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? "")"
        
        return [
            "assetId": .string(assetId),
            "sourceUrl": .string(mockUrl)
        ]
    }
    
    public func setProperty(_ key: String, to value: NodeValue) async throws {
        properties[key] = value
    }
}
