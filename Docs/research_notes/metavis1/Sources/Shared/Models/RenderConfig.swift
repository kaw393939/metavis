import Foundation

public struct RenderConfig: Codable, Sendable {
    public var hdrScalingFactor: Float
    public var exposure: Float
    public var gammaCorrection: Float
    public var tonemapOperator: String
    public var textRenderer: String? // "sdf", "vector", "hybrid"

    public static let `default` = RenderConfig(
        hdrScalingFactor: 100.0,
        exposure: 1.0,
        gammaCorrection: 2.2,
        tonemapOperator: "aces",
        textRenderer: "hybrid"
    )

    public static func load(from path: String = "render_config.json") -> RenderConfig {
        if FileManager.default.fileExists(atPath: path) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let config = try JSONDecoder().decode(RenderConfig.self, from: data)
                print("⚙️ Loaded render config from \(path)")
                return config
            } catch {
                print("⚠️ Failed to load render config: \(error). Using defaults.")
            }
        }
        return .default
    }
}
