import Foundation

public enum VideoCodec: String, Codable, Sendable {
    case h264
    case hevc
    case prores422
    case prores422HQ
    case prores4444
    case prores422Proxy
    case prores422LT
    case prores4444XQ
    case proresRAW
    case hevcWithAlpha
    case av1
    case jpeg
    case mjpeg
    case unknown
    
    public var displayName: String {
        rawValue
    }
}

public enum AudioCodec: String, Codable, Sendable {
    case aac
    case aacLC
    case aacHE
    case pcmS16LE
    case pcmS24LE
    case pcmS32LE
    case pcmFloat
    case alac
    case flac
    case mp3
    case ac3
    case eac3
    case opus
    case unknown
    
    public var isLossless: Bool {
        switch self {
        case .pcmS16LE, .pcmS24LE, .pcmS32LE, .pcmFloat, .alac, .flac:
            return true
        default:
            return false
        }
    }
}

public enum ContainerFormat: String, Codable, Sendable {
    case mp4
    case mov
    case m4v
    case m4a
    case wav
    case mp3
    case aiff
    case webm
    case mkv
    case avi
    case unknown
}


