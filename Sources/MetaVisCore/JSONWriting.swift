import Foundation

public enum JSONWriting {
    /// Encodes a value to JSON with deterministic formatting and writes it atomically.
    public static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encode(value)
        try data.write(to: url, options: [.atomic])
    }

    /// Encodes a value to JSON with deterministic formatting.
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}
