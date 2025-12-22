import Foundation
import CoreGraphics
import MetaVisCore

/// Versioned, governed LLM boundary schema (v2).
///
/// This is intentionally strict:
/// - No untyped attribute dictionaries.
/// - Per-attribute confidence is required.
/// - Provenance is structured.
public struct SemanticFrameV2: Sendable, Codable, Equatable {
    public var schema: String
    public var timestampSeconds: Double
    public var subjects: [SemanticSubjectV2]
    public var contextTags: [String]

    public init(
        schema: String = "semantic.frame.v2",
        timestampSeconds: Double,
        subjects: [SemanticSubjectV2],
        contextTags: [String] = []
    ) {
        self.schema = schema
        self.timestampSeconds = timestampSeconds
        self.subjects = subjects
        self.contextTags = contextTags
    }
}

public struct SemanticSubjectV2: Sendable, Codable, Equatable {
    public enum Label: String, Codable, Sendable, Equatable {
        case person
        case object
    }

    public var trackId: UUID
    public var personId: String?
    public var rect: CGRect // normalized 0..1, top-left origin
    public var label: Label

    /// Bounded typed attributes (no free-form dictionaries).
    public var attributes: [SemanticAttributeV1]

    public init(
        trackId: UUID,
        personId: String? = nil,
        rect: CGRect,
        label: Label = .person,
        attributes: [SemanticAttributeV1] = []
    ) {
        self.trackId = trackId
        self.personId = personId
        self.rect = rect
        self.label = label
        self.attributes = attributes
    }
}

public struct SemanticAttributeV1: Sendable, Codable, Equatable {
    public var key: String
    public var value: SemanticValueV1

    public init(key: String, value: SemanticValueV1) {
        self.key = key
        self.value = value
    }
}

public enum SemanticValueV1: Sendable, Codable, Equatable {
    case string(EvidencedValueV1<String>)
    case double(EvidencedValueV1<Double>)
    case bool(EvidencedValueV1<Bool>)

    private enum CodingKeys: String, CodingKey {
        case type
        case string
        case double
        case bool
    }

    private enum Kind: String, Codable {
        case string
        case double
        case bool
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .type)
        switch kind {
        case .string:
            self = .string(try c.decode(EvidencedValueV1<String>.self, forKey: .string))
        case .double:
            self = .double(try c.decode(EvidencedValueV1<Double>.self, forKey: .double))
        case .bool:
            self = .bool(try c.decode(EvidencedValueV1<Bool>.self, forKey: .bool))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let v):
            try c.encode(Kind.string, forKey: .type)
            try c.encode(v, forKey: .string)
        case .double(let v):
            try c.encode(Kind.double, forKey: .type)
            try c.encode(v, forKey: .double)
        case .bool(let v):
            try c.encode(Kind.bool, forKey: .type)
            try c.encode(v, forKey: .bool)
        }
    }
}
