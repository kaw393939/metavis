import AVFoundation
import CoreVideo
import Metal

public enum VideoReaderError: Error {
    case assetNotFound
    case noVideoTrack
    case cannotRead
}

/// Reads frames from a video file sequentially
public class VideoReader {
    private let asset: AVAsset
    private var reader: AVAssetReader?
    private var trackOutput: AVAssetReaderTrackOutput?
    private let videoTrack: AVAssetTrack

    // Caching for efficient streaming
    private var currentPixelBuffer: CVPixelBuffer?
    private var currentPTS: TimeInterval?

    public let duration: TimeInterval
    public let frameRate: Float
    public let size: CGSize
    public let pixelFormat: OSType

    public static let standardFormat = kCVPixelFormatType_32BGRA
    public static let highQualityFormat = kCVPixelFormatType_64RGBAHalf

    public init(url: URL, pixelFormat: OSType = kCVPixelFormatType_32BGRA) async throws {
        let asset = AVAsset(url: url)

        // Load properties asynchronously
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw VideoReaderError.noVideoTrack
        }

        duration = try await asset.load(.duration).seconds
        frameRate = try await track.load(.nominalFrameRate)
        size = try await track.load(.naturalSize)

        self.asset = asset
        videoTrack = track
        self.pixelFormat = pixelFormat

        // Don't start reading immediately, wait for first request
    }

    private func startReading(at time: CMTime) throws {
        let reader = try AVAssetReader(asset: asset)

        let settings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(pixelFormat),
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: settings)
        output.alwaysCopiesSampleData = false

        reader.add(output)

        let timeRange = CMTimeRange(start: time, duration: .positiveInfinity)
        reader.timeRange = timeRange

        if !reader.startReading() {
            throw VideoReaderError.cannotRead
        }

        self.reader = reader
        trackOutput = output

        // Reset cache
        currentPixelBuffer = nil
        currentPTS = nil
    }

    /// Smart frame retrieval that handles seeking and streaming automatically
    public func getFrame(at time: TimeInterval) throws -> CVPixelBuffer? {
        // 1. Check if we need to seek
        // If we haven't started, or if requested time is backwards, or if we are too far ahead (gap > 0.5s)
        if reader == nil ||
            (currentPTS != nil && time < currentPTS!) ||
            (currentPTS != nil && time > currentPTS! + 0.5) {
            try seek(to: time)
        }

        // 2. Read forward until we catch up to the requested time
        // We want the frame that is closest to 'time' without going over too much,
        // or simply the frame that covers this time slice.
        // Simple strategy: If current frame is too old, read next.

        // If we have no frame, read one
        if currentPixelBuffer == nil {
            readNextSample()
        }

        // While the *next* frame might be a better match...
        // Actually, we just want to ensure currentPTS is <= time.
        // If currentPTS is way behind time, we skip frames.

        let frameDuration = 1.0 / Double(frameRate)

        while let pts = currentPTS, pts < (time - frameDuration) {
            // The current frame is too old. Read next.
            if !readNextSample() {
                break // End of file
            }
        }

        return currentPixelBuffer
    }

    @discardableResult
    private func readNextSample() -> Bool {
        guard let reader = reader, reader.status == .reading,
              let output = trackOutput
        else {
            return false
        }

        if let sampleBuffer = output.copyNextSampleBuffer(),
           let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            currentPixelBuffer = pixelBuffer
            currentPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            return true
        }

        return false
    }

    /// Returns the next frame as a CVPixelBuffer (Legacy/Raw access)
    public func nextFrame() -> CVPixelBuffer? {
        if readNextSample() {
            return currentPixelBuffer
        }
        return nil
    }

    /// Resets the reader to the specified time
    public func seek(to time: TimeInterval) throws {
        reader?.cancelReading()
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        try startReading(at: cmTime)

        // Prime the pump
        readNextSample()
    }

    public func cancel() {
        reader?.cancelReading()
    }
}
