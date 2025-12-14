import Foundation
import AVFoundation
import Metal
import CoreVideo
import CoreMedia
import CoreImage

/// Minimal, caching video frame reader that produces Metal textures.
///
/// Notes:
/// - Designed for sequential/export workloads (render frame N, then N+1, ...).
/// - Uses `AVAssetReader` with a `VideoCompositionOutput` so we can apply track transforms
///   and scale directly to the engine's working resolution.
actor ClipReader {
    struct Key: Hashable {
        var assetURL: String
        var timeQuantized: Int64
        var width: Int
        var height: Int
    }

    private let device: MTLDevice

    enum ClipReaderError: Error, LocalizedError {
        case missingVideoTrack
        case cannotCreateAssetReader
        case cannotStartReading(String)
        case noSampleAvailable
        case noImageBuffer
        case cannotCreateMetalTexture

        var errorDescription: String? {
            switch self {
            case .missingVideoTrack: return "No video track found"
            case .cannotCreateAssetReader: return "Failed to create AVAssetReader"
            case .cannotStartReading(let reason): return "AVAssetReader failed to start reading: \(reason)"
            case .noSampleAvailable: return "No video samples available at requested time"
            case .noImageBuffer: return "SampleBuffer had no image buffer"
            case .cannotCreateMetalTexture: return "Failed to create Metal texture from CVPixelBuffer"
            }
        }
    }

    private struct CachedFrame {
        let pixelBuffer: CVPixelBuffer
        let cvMetalTexture: CVMetalTexture
        let texture: MTLTexture
    }

    private struct DecoderKey: Hashable {
        var assetURL: String
        var width: Int
        var height: Int
    }

    private final class DecoderState {
        let assetURL: URL
        let width: Int
        let height: Int

        let asset: AVURLAsset
        let videoTrack: AVAssetTrack
        private let assetDuration: CMTime

        private(set) var reader: AVAssetReader?
        private(set) var output: AVAssetReaderTrackOutput?
        private(set) var lastReadPTS: CMTime = .invalid

        init(assetURL: URL, width: Int, height: Int) async throws {
            self.assetURL = assetURL
            self.width = width
            self.height = height

            let asset = AVURLAsset(url: assetURL)
            self.asset = asset

            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else {
                throw ClipReaderError.missingVideoTrack
            }
            self.videoTrack = track

            self.assetDuration = try await asset.load(.duration)
        }

        func restart(at time: CMTime) throws {
            reader?.cancelReading()
            reader = nil
            output = nil

            let r: AVAssetReader
            do {
                r = try AVAssetReader(asset: asset)
            } catch {
                throw ClipReaderError.cannotCreateAssetReader
            }

            let pixelFormat = kCVPixelFormatType_32BGRA
            let settings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat]
            let out = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: settings)
            out.alwaysCopiesSampleData = false

            guard r.canAdd(out) else {
                throw ClipReaderError.cannotStartReading("cannot add video output")
            }
            r.add(out)

            // Avoid setting `reader.timeRange`.
            // In practice, some reader outputs return sample PTSs relative to the timeRange start,
            // which can make naive absolute-time comparisons miss every frame. Scanning forward
            // from the start is more reliable for compressed sources.

            guard r.startReading() else {
                throw ClipReaderError.cannotStartReading(r.error?.localizedDescription ?? "unknown")
            }

            reader = r
            output = out
            lastReadPTS = .invalid
        }

        func readSample(closestTo time: CMTime) throws -> CMSampleBuffer {
            return try readSampleImpl(closestTo: time, didRetry: false)
        }

        private func readSampleImpl(closestTo time: CMTime, didRetry: Bool) throws -> CMSampleBuffer {
            if reader == nil || output == nil {
                try restart(at: time)
            }
            // If the request moves backwards, or jumps far ahead, restart at the new time.
            // (AVAssetReader is strictly forward-only.)
            if lastReadPTS.isValid {
                if time < lastReadPTS {
                    try restart(at: time)
                } else {
                    let delta = CMTimeSubtract(time, lastReadPTS)
                    if delta.isValid, delta.seconds.isFinite, delta.seconds > 2.0 {
                        try restart(at: time)
                    }
                }
            }

            // Bind reader/output *after* any possible restart.
            guard let r = reader, let o = output else {
                throw ClipReaderError.cannotStartReading("reader/output unavailable")
            }

            var previous: CMSampleBuffer?
            var next: CMSampleBuffer?

            while true {
                if let sample = o.copyNextSampleBuffer() {
                    let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                    lastReadPTS = pts
                    if pts >= time {
                        next = sample
                        break
                    }
                    previous = sample
                    continue
                }

                // No more samples.
                if r.status == .failed {
                    throw ClipReaderError.cannotStartReading(r.error?.localizedDescription ?? "failed")
                }
                break
            }

            // Choose nearest sample by PTS when we have both sides.
            if let prev = previous, let nxt = next {
                let prevPTS = CMSampleBufferGetPresentationTimeStamp(prev)
                let nextPTS = CMSampleBufferGetPresentationTimeStamp(nxt)
                let dp = abs(prevPTS.seconds - time.seconds)
                let dn = abs(nextPTS.seconds - time.seconds)
                return (dn <= dp) ? nxt : prev
            }
            if let nxt = next { return nxt }
            if let prev = previous { return prev }

            // Some codecs require decode history; retry once starting from zero.
            if !didRetry {
                try restart(at: .zero)
                return try readSampleImpl(closestTo: time, didRetry: true)
            }
            throw ClipReaderError.noSampleAvailable
        }
    }

    private var decoders: [DecoderKey: DecoderState] = [:]

    private var cache: [Key: CachedFrame] = [:]
    private var cacheOrder: [Key] = []

    private let maxCachedFrames: Int

    private var metalTextureCache: CVMetalTextureCache?

    private let ciContext: CIContext

    init(device: MTLDevice, maxCachedFrames: Int = 24) {
        self.device = device
        self.maxCachedFrames = max(4, maxCachedFrames)

        self.ciContext = CIContext(options: [
            CIContextOption.cacheIntermediates: false,
            CIContextOption.useSoftwareRenderer: false
        ])

        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        if status == kCVReturnSuccess {
            self.metalTextureCache = cache
        } else {
            self.metalTextureCache = nil
        }
    }

    func texture(
        assetURL: URL,
        timeSeconds: Double,
        width: Int,
        height: Int
    ) async throws -> MTLTexture {
        try await textureInternal(assetURL: assetURL, timeSeconds: timeSeconds, width: width, height: height)
    }

    nonisolated func prefetch(
        assetURL: URL,
        timeSeconds: Double,
        width: Int,
        height: Int
    ) {
        Task {
            _ = try? await self.texture(assetURL: assetURL, timeSeconds: timeSeconds, width: width, height: height)
        }
    }

    // MARK: - Internals

    private func textureInternal(
        assetURL: URL,
        timeSeconds: Double,
        width: Int,
        height: Int
    ) async throws -> MTLTexture {
        let quantized = Int64((timeSeconds * 60_000.0).rounded())
        let key = Key(assetURL: assetURL.absoluteString, timeQuantized: quantized, width: width, height: height)

        if let hit = cache[key] {
            return hit.texture
        }

        guard let cache = metalTextureCache else {
            throw ClipReaderError.cannotCreateMetalTexture
        }

        let decoderKey = DecoderKey(assetURL: assetURL.absoluteString, width: width, height: height)
        let decoder: DecoderState
        if let existing = decoders[decoderKey] {
            decoder = existing
        } else {
            decoder = try await DecoderState(assetURL: assetURL, width: width, height: height)
            decoders[decoderKey] = decoder
        }

        let requestTime = CMTime(seconds: timeSeconds, preferredTimescale: 600)
        let sample = try decoder.readSample(closestTo: requestTime)
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sample) else {
            throw ClipReaderError.noImageBuffer
        }
        let decodedPixelBuffer = imageBuffer

        let pbW = CVPixelBufferGetWidth(decodedPixelBuffer)
        let pbH = CVPixelBufferGetHeight(decodedPixelBuffer)
        let pixelBuffer: CVPixelBuffer
        if pbW == width && pbH == height {
            pixelBuffer = decodedPixelBuffer
        } else {
            // Some sources ignore the requested composition renderSize. Scale deterministically to the
            // engine's working size so `source_texture` can read within bounds.
            pixelBuffer = try scale(pixelBuffer: decodedPixelBuffer, toWidth: width, height: height)
        }

        var cvMetalTex: CVMetalTexture?
        let createResult = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvMetalTex
        )

        guard createResult == kCVReturnSuccess,
              let cvTex = cvMetalTex,
              let mtlTex = CVMetalTextureGetTexture(cvTex) else {
            throw ClipReaderError.cannotCreateMetalTexture
        }

        let frame = CachedFrame(pixelBuffer: pixelBuffer, cvMetalTexture: cvTex, texture: mtlTex)
        insert(frame, for: key)
        return mtlTex
    }

    private func scale(pixelBuffer: CVPixelBuffer, toWidth width: Int, height: Int) throws -> CVPixelBuffer {
        var out: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true
        ]

        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &out)
        guard status == kCVReturnSuccess, let out else {
            throw ClipReaderError.cannotStartReading("failed to allocate scaled CVPixelBuffer (\(status))")
        }

        let srcW = max(1, CVPixelBufferGetWidth(pixelBuffer))
        let srcH = max(1, CVPixelBufferGetHeight(pixelBuffer))
        let sx = CGFloat(width) / CGFloat(srcW)
        let sy = CGFloat(height) / CGFloat(srcH)

        let srcImage = CIImage(cvPixelBuffer: pixelBuffer)
        let scaled = srcImage.transformed(by: CGAffineTransform(scaleX: sx, y: sy))

        CVPixelBufferLockBaseAddress(out, [])
        defer { CVPixelBufferUnlockBaseAddress(out, []) }

        ciContext.render(
            scaled,
            to: out,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        return out
    }

    private func insert(_ frame: CachedFrame, for key: Key) {
        cache[key] = frame
        cacheOrder.append(key)

        while cacheOrder.count > maxCachedFrames {
            let evicted = cacheOrder.removeFirst()
            cache.removeValue(forKey: evicted)
        }
    }
}
