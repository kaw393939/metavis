import Foundation

public struct PolicyLibrary: Codable, Sendable, Equatable {

    public private(set) var presets: [String: QualityPolicyBundle]

    public init(presets: [String: QualityPolicyBundle] = [:]) {
        self.presets = presets
    }

    public func listPresetNames() -> [String] {
        presets.keys.sorted()
    }

    public func preset(named name: String) -> QualityPolicyBundle? {
        presets[name]
    }

    public mutating func upsertPreset(named name: String, bundle: QualityPolicyBundle) {
        presets[name] = bundle
    }

    @discardableResult
    public mutating func removePreset(named name: String) -> QualityPolicyBundle? {
        presets.removeValue(forKey: name)
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)

        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Atomic write to avoid partial/corrupt saves.
        try data.write(to: url, options: [.atomic])
    }

    public static func load(from url: URL) throws -> PolicyLibrary {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(PolicyLibrary.self, from: data)
    }
}
