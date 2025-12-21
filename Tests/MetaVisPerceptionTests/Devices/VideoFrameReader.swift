import Foundation
import AVFoundation
import CoreVideo

enum VideoFrameReader {

    enum FrameReaderError: Error {
        case noVideoTrack
        case cannotStartReading
        case noFrames
    }

    /// Reads up to `maxFrames` frames from a local movie file as 32BGRA pixel buffers.
    static func readFrames(
        url: URL,
        maxFrames: Int,
        maxSeconds: Double
    ) async throws -> [CVPixelBuffer] {
        return try await readFrames(url: url, maxFrames: maxFrames, startSeconds: 0.0, maxSeconds: maxSeconds)
    }

    /// Reads up to `maxFrames` frames from a local movie file as 32BGRA pixel buffers,
    /// starting from `startSeconds` and stopping at `startSeconds + maxSeconds`.
    static func readFrames(
        url: URL,
        maxFrames: Int,
        startSeconds: Double,
        maxSeconds: Double
    ) async throws -> [CVPixelBuffer] {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw FrameReaderError.noVideoTrack }

        let duration = try await asset.load(.duration)
        let durSeconds = duration.seconds.isFinite ? duration.seconds : 0.0
        let start = max(0.0, min(durSeconds, startSeconds.isFinite ? startSeconds : 0.0))
        let maxDur = max(0.0, maxSeconds.isFinite ? maxSeconds : 0.0)
        let limitSeconds = min(durSeconds, start + maxDur)

        let reader = try AVAssetReader(asset: asset)

        // Seek without decoding from t=0.
        if start > 0.0 {
            let startTime = CMTime(seconds: start, preferredTimescale: 600)
            let endTime = CMTime(seconds: limitSeconds, preferredTimescale: 600)
            reader.timeRange = CMTimeRange(start: startTime, end: endTime)
        }
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw FrameReaderError.cannotStartReading }
        reader.add(output)

        guard reader.startReading() else { throw FrameReaderError.cannotStartReading }

        var frames: [CVPixelBuffer] = []
        frames.reserveCapacity(maxFrames)

        while reader.status == .reading, let sb = output.copyNextSampleBuffer() {
            let pts = CMSampleBufferGetPresentationTimeStamp(sb)
            let t = pts.isValid ? pts.seconds : 0.0
            if t > limitSeconds { break }

            guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
            frames.append(pb)

            if frames.count >= maxFrames { break }
        }

        if frames.isEmpty { throw FrameReaderError.noFrames }
        return frames
    }
}
