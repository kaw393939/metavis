import Foundation
import AVFoundation

public enum VideoMetadataQC {
    public struct VideoTrackReport: Codable, Sendable, Equatable {
        /// FourCC subtype string (e.g. "hvc1", "avc1").
        public var codecFourCC: String?

        /// Human-friendly format name when available.
        public var formatName: String?

        /// Bits per component when present in format description extensions.
        public var bitsPerComponent: Int?

        /// Full-range video flag when present in format description extensions.
        public var fullRangeVideo: Bool?

        /// Color metadata if present in the format description extensions.
        public var colorPrimaries: String?
        public var transferFunction: String?
        public var yCbCrMatrix: String?

        /// Derived from `transferFunction` when possible.
        public var isHDR: Bool?

        public init(
            codecFourCC: String? = nil,
            formatName: String? = nil,
            bitsPerComponent: Int? = nil,
            fullRangeVideo: Bool? = nil,
            colorPrimaries: String? = nil,
            transferFunction: String? = nil,
            yCbCrMatrix: String? = nil,
            isHDR: Bool? = nil
        ) {
            self.codecFourCC = codecFourCC
            self.formatName = formatName
            self.bitsPerComponent = bitsPerComponent
            self.fullRangeVideo = fullRangeVideo
            self.colorPrimaries = colorPrimaries
            self.transferFunction = transferFunction
            self.yCbCrMatrix = yCbCrMatrix
            self.isHDR = isHDR
        }
    }

    public struct AudioTrackReport: Codable, Sendable, Equatable {
        public var channelCount: Int?
        public var sampleRateHz: Double?

        public init(channelCount: Int? = nil, sampleRateHz: Double? = nil) {
            self.channelCount = channelCount
            self.sampleRateHz = sampleRateHz
        }
    }

    public struct Report: Codable, Sendable, Equatable {
        public var hasVideoTrack: Bool
        public var hasAudioTrack: Bool
        public var video: VideoTrackReport?
        public var audio: AudioTrackReport?

        public init(hasVideoTrack: Bool, hasAudioTrack: Bool, video: VideoTrackReport? = nil, audio: AudioTrackReport? = nil) {
            self.hasVideoTrack = hasVideoTrack
            self.hasAudioTrack = hasAudioTrack
            self.video = video
            self.audio = audio
        }
    }

    public static func inspectMovie(at url: URL) async throws -> Report {
        let asset = AVURLAsset(url: url)

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        var videoReport: VideoTrackReport?
        if let vt = videoTracks.first {
            let formatDescriptions = try await vt.load(.formatDescriptions)
            if let fd = formatDescriptions.first {
                let codecFourCC = fourCCString(from: CMFormatDescriptionGetMediaSubType(fd))

                var colorPrimaries: String?
                var transferFunction: String?
                var yCbCrMatrix: String?
                var formatName: String?
                var bitsPerComponent: Int?
                var fullRangeVideo: Bool?
                var isHDR: Bool?

                if let ext = CMFormatDescriptionGetExtensions(fd) as? [String: Any] {
                    colorPrimaries = ext[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String
                    transferFunction = ext[kCMFormatDescriptionExtension_TransferFunction as String] as? String
                    yCbCrMatrix = ext[kCMFormatDescriptionExtension_YCbCrMatrix as String] as? String

                    formatName = ext[kCMFormatDescriptionExtension_FormatName as String] as? String
                    bitsPerComponent = (ext[kCMFormatDescriptionExtension_BitsPerComponent as String] as? NSNumber)?.intValue
                    fullRangeVideo = (ext[kCMFormatDescriptionExtension_FullRangeVideo as String] as? NSNumber)?.boolValue
                }

                if let tf = transferFunction?.lowercased() {
                    // Conservative heuristic: mark HDR true only when transfer clearly indicates HDR.
                    if tf.contains("2100") || tf.contains("pq") || tf.contains("hlg") {
                        isHDR = true
                    } else {
                        isHDR = false
                    }
                }

                videoReport = VideoTrackReport(
                    codecFourCC: codecFourCC,
                    formatName: formatName,
                    bitsPerComponent: bitsPerComponent,
                    fullRangeVideo: fullRangeVideo,
                    colorPrimaries: colorPrimaries,
                    transferFunction: transferFunction,
                    yCbCrMatrix: yCbCrMatrix,
                    isHDR: isHDR
                )
            } else {
                videoReport = VideoTrackReport()
            }
        }

        var audioReport: AudioTrackReport?
        if let at = audioTracks.first {
            let formatDescriptions = try await at.load(.formatDescriptions)
            if let fd = formatDescriptions.first,
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee {
                audioReport = AudioTrackReport(channelCount: Int(asbd.mChannelsPerFrame), sampleRateHz: asbd.mSampleRate)
            } else {
                audioReport = AudioTrackReport()
            }
        }

        return Report(
            hasVideoTrack: !videoTracks.isEmpty,
            hasAudioTrack: !audioTracks.isEmpty,
            video: videoReport,
            audio: audioReport
        )
    }

    private static func fourCCString(from code: FourCharCode) -> String {
        let be = code.bigEndian
        var chars: [UInt8] = [0, 0, 0, 0]
        withUnsafeBytes(of: be) { raw in
            chars[0] = raw[0]
            chars[1] = raw[1]
            chars[2] = raw[2]
            chars[3] = raw[3]
        }
        return String(bytes: chars, encoding: .macOSRoman) ?? String(format: "%c%c%c%c", chars[0], chars[1], chars[2], chars[3])
    }
}
