import Foundation

// MARK: - Request

public struct GeminiGenerateContentRequest: Codable, Sendable {
    public struct Content: Codable, Sendable {
        public var role: String?
        public var parts: [Part]

        public init(role: String? = nil, parts: [Part]) {
            self.role = role
            self.parts = parts
        }
    }

    public enum Part: Codable, Sendable {
        case text(String)
        case inlineData(mimeType: String, dataBase64: String)

        private enum CodingKeys: String, CodingKey {
            case text
            case inlineData = "inline_data"
        }

        private enum InlineDataKeys: String, CodingKey {
            case mimeType = "mime_type"
            case data
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode(text, forKey: .text)
            case .inlineData(let mimeType, let dataBase64):
                var nested = container.nestedContainer(keyedBy: InlineDataKeys.self, forKey: .inlineData)
                try nested.encode(mimeType, forKey: .mimeType)
                try nested.encode(dataBase64, forKey: .data)
            }
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let text = try container.decodeIfPresent(String.self, forKey: .text) {
                self = .text(text)
                return
            }
            if container.contains(.inlineData) {
                let nested = try container.nestedContainer(keyedBy: InlineDataKeys.self, forKey: .inlineData)
                let mimeType = try nested.decode(String.self, forKey: .mimeType)
                let dataBase64 = try nested.decode(String.self, forKey: .data)
                self = .inlineData(mimeType: mimeType, dataBase64: dataBase64)
                return
            }
            throw GeminiError.decode("Unknown Part")
        }
    }

    public var contents: [Content]

    public init(contents: [Content]) {
        self.contents = contents
    }
}

// MARK: - Response

public struct GeminiGenerateContentResponse: Codable, Sendable {
    public struct Candidate: Codable, Sendable {
        public struct Content: Codable, Sendable {
            public struct Part: Codable, Sendable {
                public var text: String?
            }

            public var parts: [Part]?
        }

        public var content: Content?
    }

    public var candidates: [Candidate]?

    public var primaryText: String? {
        candidates?
            .first?
            .content?
            .parts?
            .compactMap { $0.text }
            .joined()
    }
}
