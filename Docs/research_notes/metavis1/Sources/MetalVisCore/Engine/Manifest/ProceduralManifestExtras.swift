
public struct ColorMapDefinition: Codable {
    public let gradient: [String]? // Hex colors
    public let mode: String? // "ACEScg", "SRGB"
    public let hdrScale: Float?
}
