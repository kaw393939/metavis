import Foundation

/// Structured provenance reference (v1).
///
/// This is intended to be compiler-like: a stable, inspectable pointer back to the
/// signals/devices/artifacts/windows that justified an output.
public struct ProvenanceRefV1: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, Equatable {
        case signal
        case device
        case artifact
        case metric
        case interval
        case unknown

        public init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            let raw = (try? c.decode(String.self)) ?? "unknown"
            self = Kind(rawValue: raw) ?? .unknown
        }
    }

    public var kind: Kind
    public var id: String?
    public var field: String?
    public var value: Double?

    public var startSeconds: Double?
    public var endSeconds: Double?

    public init(
        kind: Kind,
        id: String? = nil,
        field: String? = nil,
        value: Double? = nil,
        startSeconds: Double? = nil,
        endSeconds: Double? = nil
    ) {
        self.kind = kind
        self.id = id
        self.field = field
        self.value = value
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }

    public static func metric(_ field: String, value: Double) -> ProvenanceRefV1 {
        ProvenanceRefV1(kind: .metric, field: field, value: value)
    }

    public static func interval(_ id: String? = nil, startSeconds: Double, endSeconds: Double) -> ProvenanceRefV1 {
        ProvenanceRefV1(kind: .interval, id: id, startSeconds: startSeconds, endSeconds: endSeconds)
    }
}
