import Foundation
import MetaVisCore

public enum TrackType: Codable, Sendable, Equatable {
    case video
    case audio
    case deviceParameter(deviceId: UUID, parameter: String)
    case generic
    
    enum CodingKeys: String, CodingKey {
        case type
        case deviceId
        case parameter
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .video:
            try container.encode("video", forKey: .type)
        case .audio:
            try container.encode("audio", forKey: .type)
        case .generic:
            try container.encode("generic", forKey: .type)
        case .deviceParameter(let deviceId, let parameter):
            try container.encode("deviceParameter", forKey: .type)
            try container.encode(deviceId, forKey: .deviceId)
            try container.encode(parameter, forKey: .parameter)
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "video": self = .video
        case "audio": self = .audio
        case "generic": self = .generic
        case "deviceParameter":
            let deviceId = try container.decode(UUID.self, forKey: .deviceId)
            let parameter = try container.decode(String.self, forKey: .parameter)
            self = .deviceParameter(deviceId: deviceId, parameter: parameter)
        default:
            self = .generic
        }
    }
}
