import Foundation

public struct AIUsagePolicy: Codable, Sendable, Equatable {
    public enum MediaSource: String, Codable, Sendable, Equatable {
        /// Only media derived from exported deliverables may be sent.
        case deliverablesOnly
        /// Raw media may be sent if privacy policy allows it.
        case rawAllowed
    }

    public enum Mode: String, Codable, Sendable, Equatable {
        /// Never send anything off-device.
        case off
        /// Send only text (no pixels/audio).
        case textOnly
        /// Send text plus images.
        case textAndImages
        /// Send text plus video.
        case textAndVideo
        /// Send text plus images and video.
        case textImagesAndVideo
    }

    public var mode: Mode
    public var mediaSource: MediaSource

    /// Maximum total bytes allowed for inline media (base64 payload) in a single request.
    /// Gemini docs commonly cite ~20MB request constraints for inline data.
    public var maxInlineBytes: Int

    public struct RedactionPolicy: Codable, Sendable, Equatable {
        public var redactFilePaths: Bool
        public var redactIdentifiers: Bool

        public init(redactFilePaths: Bool = true, redactIdentifiers: Bool = true) {
            self.redactFilePaths = redactFilePaths
            self.redactIdentifiers = redactIdentifiers
        }
    }

    public var redaction: RedactionPolicy

    public init(
        mode: Mode = .off,
        mediaSource: MediaSource = .deliverablesOnly,
        maxInlineBytes: Int = 20 * 1024 * 1024,
        redaction: RedactionPolicy = RedactionPolicy()
    ) {
        self.mode = mode
        self.mediaSource = mediaSource
        self.maxInlineBytes = maxInlineBytes
        self.redaction = redaction
    }

    public static var localOnlyDefault: AIUsagePolicy { AIUsagePolicy(mode: .off) }

    public func allowsNetworkRequests(privacy: PrivacyPolicy) -> Bool {
        switch mode {
        case .off:
            return false
        case .textOnly:
            return true
        case .textAndImages, .textAndVideo, .textImagesAndVideo:
            return privacyAllowsMediaUpload(privacy: privacy)
        }
    }

    public func allowsImages(privacy: PrivacyPolicy) -> Bool {
        switch mode {
        case .textAndImages, .textImagesAndVideo:
            return privacyAllowsMediaUpload(privacy: privacy)
        default:
            return false
        }
    }

    public func allowsVideo(privacy: PrivacyPolicy) -> Bool {
        switch mode {
        case .textAndVideo, .textImagesAndVideo:
            return privacyAllowsMediaUpload(privacy: privacy)
        default:
            return false
        }
    }

    private func privacyAllowsMediaUpload(privacy: PrivacyPolicy) -> Bool {
        switch mediaSource {
        case .deliverablesOnly:
            return privacy.allowDeliverablesUpload
        case .rawAllowed:
            return privacy.allowRawMediaUpload || privacy.allowDeliverablesUpload
        }
    }
}
