import Foundation
import AVFoundation
import Metal
import CoreVideo
import CoreMedia
import CoreImage
import MetaVisCore
import MetaVisIngest

/// Minimal, caching video frame reader that produces Metal textures.
///
/// Notes:
/// - Designed for sequential/export workloads (render frame N, then N+1, ...).
/// - Uses `AVAssetReader` with a `VideoCompositionOutput` so we can apply track transforms
///   and scale directly to the engine's working resolution.
public actor ClipReader {
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
        case cannotDecodeStill(String)

        var errorDescription: String? {
            switch self {
            case .missingVideoTrack: return "No video track found"
            case .cannotCreateAssetReader: return "Failed to create AVAssetReader"
            case .cannotStartReading(let reason): return "AVAssetReader failed to start reading: \(reason)"
            case .noSampleAvailable: return "No video samples available at requested time"
            case .noImageBuffer: return "SampleBuffer had no image buffer"
            case .cannotCreateMetalTexture: return "Failed to create Metal texture from CVPixelBuffer"
            case .cannotDecodeStill(let reason): return "Failed to decode still: \(reason)"
            }
        }
    }

    private struct CachedFrame {
        let pixelBuffer: CVPixelBuffer?
        let cvMetalTexture: CVMetalTexture?
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

    private var timingDecisions: [String: VideoTimingNormalization.Decision] = [:]
    private var timingDecisionFailures: Set<String> = []

    private var stillPixelBuffers: [DecoderKey: CVPixelBuffer] = [:]

    private var cache: [Key: CachedFrame] = [:]
    private var cacheOrder: [Key] = []

    private let maxCachedFrames: Int

    private var metalTextureCache: CVMetalTextureCache?

    private let ciContext: CIContext

    public struct CacheStats: Sendable, Equatable {
        public var frameCacheCount: Int
        public var stillPixelBufferCount: Int
        public var decoderCount: Int

        public init(frameCacheCount: Int, stillPixelBufferCount: Int, decoderCount: Int) {
            self.frameCacheCount = frameCacheCount
            self.stillPixelBufferCount = stillPixelBufferCount
            self.decoderCount = decoderCount
        }
    }

    public init(device: MTLDevice, maxCachedFrames: Int = 24) {
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

    public func cacheStats() -> CacheStats {
        CacheStats(
            frameCacheCount: cache.count,
            stillPixelBufferCount: stillPixelBuffers.count,
            decoderCount: decoders.count
        )
    }

    public func clearCaches() {
        cache.removeAll(keepingCapacity: false)
        cacheOrder.removeAll(keepingCapacity: false)
        stillPixelBuffers.removeAll(keepingCapacity: false)
        decoders.removeAll(keepingCapacity: false)
        timingDecisions.removeAll(keepingCapacity: false)
        timingDecisionFailures.removeAll(keepingCapacity: false)

        // Best-effort flush of Metal texture cache.
        if let metalTextureCache {
            CVMetalTextureCacheFlush(metalTextureCache, 0)
        }
    }

    /// Test seam / manual hook for responding to memory pressure.
    public func handleMemoryPressure() {
        clearCaches()
    }

    func texture(
        assetURL: URL,
        timeSeconds: Double,
        width: Int,
        height: Int,
        fallbackFPS: Double = 24.0
    ) async throws -> MTLTexture {
        try await textureInternal(assetURL: assetURL, timeSeconds: timeSeconds, width: width, height: height, fallbackFPS: fallbackFPS)
    }

    nonisolated func prefetch(
        assetURL: URL,
        timeSeconds: Double,
        width: Int,
        height: Int,
        fallbackFPS: Double = 24.0
    ) {
        Task {
            _ = try? await self.texture(assetURL: assetURL, timeSeconds: timeSeconds, width: width, height: height, fallbackFPS: fallbackFPS)
        }
    }

    public func pixelBuffer(
        assetURL: URL,
        timeSeconds: Double,
        width: Int,
        height: Int,
        fallbackFPS: Double = 24.0
    ) async throws -> CVPixelBuffer {
        let normalizedTimeSeconds = await normalizeTimeSecondsIfNeeded(assetURL: assetURL, timeSeconds: timeSeconds, fallbackFPS: fallbackFPS)
        let quantized = Int64((normalizedTimeSeconds * 60_000.0).rounded())
        let key = Key(assetURL: assetURL.absoluteString, timeQuantized: quantized, width: width, height: height)

        if let hit = cache[key], let pb = hit.pixelBuffer {
            return pb
        }

        _ = try await textureInternal(assetURL: assetURL, timeSeconds: timeSeconds, width: width, height: height, fallbackFPS: fallbackFPS)

        if let hit = cache[key], let pb = hit.pixelBuffer {
            return pb
        }
        throw ClipReaderError.noImageBuffer
    }

    // MARK: - Internals

    private func textureInternal(
        assetURL: URL,
        timeSeconds: Double,
        width: Int,
        height: Int,
        fallbackFPS: Double
    ) async throws -> MTLTexture {
        let normalizedTimeSeconds = await normalizeTimeSecondsIfNeeded(assetURL: assetURL, timeSeconds: timeSeconds, fallbackFPS: fallbackFPS)
        let quantized = Int64((normalizedTimeSeconds * 60_000.0).rounded())
        let key = Key(assetURL: assetURL.absoluteString, timeQuantized: quantized, width: width, height: height)

        if let hit = cache[key] {
            return hit.texture
        }

        guard let cache = metalTextureCache else {
            throw ClipReaderError.cannotCreateMetalTexture
        }

        let ext = assetURL.pathExtension.lowercased()
        let isEXR = ext == "exr"
        let isFITS = ext == "fits" || ext == "fit"

        let decodedPixelBuffer: CVPixelBuffer
        if isEXR || isFITS {
            let stillKey = DecoderKey(assetURL: assetURL.absoluteString, width: width, height: height)
            if let cached = stillPixelBuffers[stillKey] {
                decodedPixelBuffer = cached
            } else {
                let pb: CVPixelBuffer
                if isEXR {
                    pb = try NativeEXRDecoder.decodeRGBAHalf(exrURL: assetURL, width: width, height: height, ciContext: ciContext)
                } else {
                    pb = try FITSStillDecoder.decodeRGBAHalf(fitsURL: assetURL, width: width, height: height)
                }
                stillPixelBuffers[stillKey] = pb
                decodedPixelBuffer = pb
            }
        } else {
            let decoderKey = DecoderKey(assetURL: assetURL.absoluteString, width: width, height: height)
            let decoder: DecoderState
            if let existing = decoders[decoderKey] {
                decoder = existing
            } else {
                decoder = try await DecoderState(assetURL: assetURL, width: width, height: height)
                decoders[decoderKey] = decoder
            }

            let requestTime = CMTime(seconds: normalizedTimeSeconds, preferredTimescale: 600)
            let sample = try decoder.readSample(closestTo: requestTime)
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sample) else {
                throw ClipReaderError.noImageBuffer
            }
            decodedPixelBuffer = imageBuffer
        }

        let pbW = CVPixelBufferGetWidth(decodedPixelBuffer)
        let pbH = CVPixelBufferGetHeight(decodedPixelBuffer)
        let pixelBuffer: CVPixelBuffer
        if pbW == width && pbH == height {
            pixelBuffer = decodedPixelBuffer
        } else {
            if isEXR {
                // EXR decode should already be at the requested size.
                // Avoid CI-based scaling here because it would quantize/convert pixel formats.
                throw ClipReaderError.cannotStartReading("EXR decode returned unexpected dimensions: \(pbW)x\(pbH) (expected \(width)x\(height))")
            }

            // Some sources ignore the requested composition renderSize. Scale deterministically to the
            // engine's working size so `source_texture` can read within bounds.
            pixelBuffer = try scale(pixelBuffer: decodedPixelBuffer, toWidth: width, height: height)
        }

        let mtlTex: MTLTexture
        var cvTex: CVMetalTexture?

        if isEXR || isFITS {
            var cvMetalTex: CVMetalTexture?
            let createResult = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault,
                cache,
                pixelBuffer,
                nil,
                .rgba16Float,
                width,
                height,
                0,
                &cvMetalTex
            )

            guard createResult == kCVReturnSuccess,
                  let cvMetalTex,
                  let tex = CVMetalTextureGetTexture(cvMetalTex) else {
                throw ClipReaderError.cannotCreateMetalTexture
            }

            cvTex = cvMetalTex
            mtlTex = tex
        } else {
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
                  let cvMetalTex,
                  let tex = CVMetalTextureGetTexture(cvMetalTex) else {
                throw ClipReaderError.cannotCreateMetalTexture
            }

            cvTex = cvMetalTex
            mtlTex = tex
        }

        let frame = CachedFrame(pixelBuffer: pixelBuffer, cvMetalTexture: cvTex, texture: mtlTex)
        insert(frame, for: key)
        return mtlTex
    }

    private func normalizeTimeSecondsIfNeeded(assetURL: URL, timeSeconds: Double, fallbackFPS: Double) async -> Double {
        // Only apply to local video files where VFR is plausible.
        let ext = assetURL.pathExtension.lowercased()
        let isLikelyVideo = ["mov", "mp4", "m4v"].contains(ext)
        guard isLikelyVideo else { return timeSeconds }

        let key = assetURL.standardizedFileURL.absoluteString
        if let decision = timingDecisions[key], decision.mode == .normalizeToCFR {
            return ClipReader.quantize(timeSeconds: timeSeconds, toTargetFPS: decision.targetFPS)
        }
        if timingDecisionFailures.contains(key) {
            return timeSeconds
        }

        do {
            // Keep it lightweight: ClipReader is already doing decode work; avoid long probes.
            let profile = try await VideoTimingProbe.probe(
                url: assetURL,
                config: .init(sampleLimit: 240, minSamplesForDecision: 30)
            )
            let decision = VideoTimingNormalization.decide(profile: profile, fallbackFPS: fallbackFPS)
            if decision.mode == .normalizeToCFR {
                timingDecisions[key] = decision
                return ClipReader.quantize(timeSeconds: timeSeconds, toTargetFPS: decision.targetFPS)
            }
            // Cache the decision even if passthrough so we don't probe again.
            timingDecisions[key] = decision
            return timeSeconds
        } catch {
            timingDecisionFailures.insert(key)
            return timeSeconds
        }
    }

    nonisolated static func quantize(timeSeconds: Double, toTargetFPS fps: Double) -> Double {
        guard timeSeconds.isFinite else { return timeSeconds }
        guard fps.isFinite, fps > 0 else { return timeSeconds }

        // Prefer exact frame durations for common rates.
        if let fd = commonFrameDuration(forFPS: fps) {
            return quantize(timeSeconds: timeSeconds, frameDuration: fd)
        }

        // Fallback: quantize using floating seconds.
        let step = 1.0 / fps
        if !step.isFinite || step <= 0 { return timeSeconds }
        let idx = (timeSeconds / step).rounded()
        return idx * step
    }

    private nonisolated static func commonFrameDuration(forFPS fps: Double) -> CMTime? {
        func close(_ a: Double, _ b: Double, tol: Double = 0.001) -> Bool { abs(a - b) <= tol }

        // Drop-frame style common rates.
        if close(fps, 23.976) { return CMTime(value: 1001, timescale: 24000) }
        if close(fps, 29.97) { return CMTime(value: 1001, timescale: 30000) }
        if close(fps, 59.94) { return CMTime(value: 1001, timescale: 60000) }

        // Integer rates.
        if close(fps, 24.0) { return CMTime(value: 1, timescale: 24) }
        if close(fps, 25.0) { return CMTime(value: 1, timescale: 25) }
        if close(fps, 30.0) { return CMTime(value: 1, timescale: 30) }
        if close(fps, 50.0) { return CMTime(value: 1, timescale: 50) }
        if close(fps, 60.0) { return CMTime(value: 1, timescale: 60) }
        return nil
    }

    private nonisolated static func quantize(timeSeconds: Double, frameDuration: CMTime) -> Double {
        let t = CMTime(seconds: timeSeconds, preferredTimescale: 60000)
        if !t.isValid || t.timescale == 0 || frameDuration.timescale == 0 || frameDuration.value == 0 {
            return timeSeconds
        }

        // idx ~= t / frameDuration using integer math with rounding.
        let num = Int64(t.value) * Int64(frameDuration.timescale)
        let den = Int64(t.timescale) * Int64(frameDuration.value)
        if den == 0 { return timeSeconds }
        let idx = (num >= 0) ? ((num + den / 2) / den) : ((num - den / 2) / den)

        let qValue = CMTimeValue(idx) * frameDuration.value
        let q = CMTime(value: qValue, timescale: frameDuration.timescale)
        return q.seconds
    }

    private func scale(pixelBuffer: CVPixelBuffer, toWidth width: Int, height: Int) throws -> CVPixelBuffer {
        var out: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
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

// MARK: - EXR decoding (native ImageIO/CoreImage)

private enum NativeEXRDecoder {
    enum DecodeError: Error, LocalizedError {
        case invalidDimensions
        case cannotLoadImage
        case cannotCreatePixelBuffer(OSStatus)

        var errorDescription: String? {
            switch self {
            case .invalidDimensions: return "Invalid decode dimensions"
            case .cannotLoadImage: return "Failed to load EXR image (ImageIO/CoreImage)"
            case .cannotCreatePixelBuffer(let status): return "CVPixelBufferCreate failed (\(status))"
            }
        }
    }

    static func decodeRGBAHalf(exrURL: URL, width w: Int, height h: Int, ciContext: CIContext) throws -> CVPixelBuffer {
        guard w > 0, h > 0 else { throw DecodeError.invalidDimensions }

        // Prefer native ImageIO/CoreImage decode when available.
        if let ci = CIImage(contentsOf: exrURL) {
            // Scale to requested size if needed.
            let srcW = max(1, Int(ci.extent.width.rounded()))
            let srcH = max(1, Int(ci.extent.height.rounded()))
            let image: CIImage
            if srcW == w && srcH == h {
                image = ci
            } else {
                let sx = CGFloat(w) / CGFloat(srcW)
                let sy = CGFloat(h) / CGFloat(srcH)
                image = ci.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            }

            // Render to float32 first, then sanitize/clamp and convert to RGBA16F.
            // (Some CoreImage paths produce zeros when rendering directly to kCVPixelFormatType_64RGBAHalf.)
            let cs = CGColorSpace(name: CGColorSpace.linearSRGB) ?? CGColorSpaceCreateDeviceRGB()
            let rect = CGRect(x: 0, y: 0, width: w, height: h)

            var rgba32 = [Float](repeating: 0, count: w * h * 4)
            rgba32.withUnsafeMutableBytes { raw in
                ciContext.render(
                    image,
                    toBitmap: raw.baseAddress!,
                    rowBytes: w * 4 * MemoryLayout<Float>.size,
                    bounds: rect,
                    format: .RGBAf,
                    colorSpace: cs
                )
            }

            var pb: CVPixelBuffer?
            let attrs: [CFString: Any] = [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true,
                kCVPixelBufferMetalCompatibilityKey: true,
                kCVPixelBufferIOSurfacePropertiesKey: [:]
            ]
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                w,
                h,
                kCVPixelFormatType_64RGBAHalf,
                attrs as CFDictionary,
                &pb
            )
            guard status == kCVReturnSuccess, let pb else {
                throw DecodeError.cannotCreatePixelBuffer(status)
            }

            CVPixelBufferLockBaseAddress(pb, [])
            defer { CVPixelBufferUnlockBaseAddress(pb, []) }

            guard let base = CVPixelBufferGetBaseAddress(pb) else {
                throw DecodeError.cannotCreatePixelBuffer(kCVReturnError)
            }

            let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
            let expectedRowBytes = w * 4 * MemoryLayout<Float16>.size
            guard bytesPerRow >= expectedRowBytes else {
                throw DecodeError.cannotCreatePixelBuffer(kCVReturnError)
            }

            let halfMax = Float(Float16.greatestFiniteMagnitude)
            for y in 0..<h {
                let dstRow = base.advanced(by: y * bytesPerRow)
                let dst = dstRow.bindMemory(to: UInt16.self, capacity: w * 4)

                // CoreImage uses a bottom-left origin; Metal textures (and our tests) treat y=0 as the top row.
                let srcRowStart = ((h - 1 - y) * w) * 4

                for x in 0..<(w * 4) {
                    let v = rgba32[srcRowStart + x]
                    if v.isFinite {
                        let clamped = min(halfMax, max(-halfMax, v))
                        dst[x] = Float16(clamped).bitPattern
                    } else {
                        dst[x] = Float16(0).bitPattern
                    }
                }
            }

            return pb
        }

        // Fallback: use ffmpeg to decode EXR into planar float32 (gbrapf32le) and convert to RGBA16F.
        // This keeps EXR ingest working on macOS installations without OpenEXR ImageIO support.
        return try FFmpegEXRDecoder.decodeRGBAHalf(exrURL: exrURL, width: w, height: h)
    }
}

private enum FFmpegEXRDecoder {
    enum DecodeError: Error, LocalizedError {
        case ffmpegFailed(String)
        case unexpectedOutput(Int, expected: Int)
        case cannotCreatePixelBuffer(OSStatus)

        var errorDescription: String? {
            switch self {
            case .ffmpegFailed(let msg): return "ffmpeg EXR decode failed: \(msg)"
            case .unexpectedOutput(let got, let expected): return "ffmpeg EXR decode returned \(got) bytes (expected \(expected))"
            case .cannotCreatePixelBuffer(let status): return "CVPixelBufferCreate failed (\(status))"
            }
        }
    }

    static func decodeRGBAHalf(exrURL: URL, width w: Int, height h: Int) throws -> CVPixelBuffer {
        let rawURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("metavis_exr_decode_\(UUID().uuidString).raw")
        defer { try? FileManager.default.removeItem(at: rawURL) }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")

        // Decode to planar float32 gbrapf32le (G,B,R,A planes) into a temp file.
        // Planes are: G, B, R, A (each Float32), top-to-bottom scanlines.
        p.arguments = [
            "ffmpeg",
            "-nostdin",
            "-y",
            "-v", "error",
            "-i", exrURL.path,
            "-vf", "scale=\(w):\(h):flags=neighbor",
            "-frames:v", "1",
            "-f", "rawvideo",
            "-pix_fmt", "gbrapf32le",
            rawURL.path
        ]
        let errPipe = Pipe()
        p.standardError = errPipe

        try p.run()
        p.waitUntilExit()

        let err = errPipe.fileHandleForReading.readDataToEndOfFile()

        guard p.terminationStatus == 0 else {
            let msg = (String(data: err, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            throw DecodeError.ffmpegFailed(msg.isEmpty ? "exit \(p.terminationStatus)" : msg)
        }

        let out = (try? Data(contentsOf: rawURL)) ?? Data()

        let planeSize = w * h
        let expectedBytes = planeSize * 4 * MemoryLayout<Float>.size
        guard out.count == expectedBytes else {
            throw DecodeError.unexpectedOutput(out.count, expected: expectedBytes)
        }

        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            w,
            h,
            kCVPixelFormatType_64RGBAHalf,
            attrs as CFDictionary,
            &pb
        )
        guard status == kCVReturnSuccess, let pb else {
            throw DecodeError.cannotCreatePixelBuffer(status)
        }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let base = CVPixelBufferGetBaseAddress(pb) else {
            throw DecodeError.cannotCreatePixelBuffer(kCVReturnError)
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
        let expectedRowBytes = w * 4 * MemoryLayout<Float16>.size
        guard bytesPerRow >= expectedRowBytes else {
            throw DecodeError.cannotCreatePixelBuffer(kCVReturnError)
        }

        let halfMax = Float(Float16.greatestFiniteMagnitude)

        out.withUnsafeBytes { raw in
            let floats = raw.bindMemory(to: Float.self)
            let gBase = 0 * planeSize
            let bBase = 1 * planeSize
            let rBase = 2 * planeSize
            let aBase = 3 * planeSize

            for y in 0..<h {
                let dstRow = base.advanced(by: y * bytesPerRow)
                let dst = dstRow.bindMemory(to: UInt16.self, capacity: w * 4)
                let rowBase = y * w

                for x in 0..<w {
                    let i = rowBase + x
                    let r = floats[rBase + i]
                    let g = floats[gBase + i]
                    let b = floats[bBase + i]
                    let a = floats[aBase + i]

                    @inline(__always)
                    func toHalfBits(_ v: Float) -> UInt16 {
                        guard v.isFinite else { return Float16(0).bitPattern }
                        let clamped = min(halfMax, max(-halfMax, v))
                        return Float16(clamped).bitPattern
                    }

                    let o = x * 4
                    dst[o + 0] = toHalfBits(r)
                    dst[o + 1] = toHalfBits(g)
                    dst[o + 2] = toHalfBits(b)
                    dst[o + 3] = toHalfBits(a)
                }
            }
        }

        return pb
    }
}

// MARK: - FITS decoding (pure Swift)

private enum FITSStillDecoder {
    static func decodeRGBAHalf(fitsURL: URL, width dstW: Int, height dstH: Int) throws -> CVPixelBuffer {
        guard dstW > 0, dstH > 0 else {
            throw ClipReader.ClipReaderError.cannotDecodeStill("invalid destination dimensions")
        }

        let asset = try FITSReader().read(url: fitsURL)
        guard asset.bitpix == -32 else {
            throw ClipReader.ClipReaderError.cannotDecodeStill("unsupported BITPIX=\(asset.bitpix)")
        }

        let srcW = asset.width
        let srcH = asset.height
        guard srcW > 0, srcH > 0 else {
            throw ClipReader.ClipReaderError.cannotDecodeStill("invalid source dimensions")
        }

        // Use percentiles if available to reduce outlier impact.
        let black = asset.statistics.min
        let white = asset.statistics.percentiles[99] ?? asset.statistics.max
        let denom = max(1e-20 as Float, (white - black))

        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            dstW,
            dstH,
            kCVPixelFormatType_64RGBAHalf,
            attrs as CFDictionary,
            &pb
        )
        guard status == kCVReturnSuccess, let pb else {
            throw ClipReader.ClipReaderError.cannotDecodeStill("CVPixelBufferCreate failed (\(status))")
        }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let base = CVPixelBufferGetBaseAddress(pb) else {
            throw ClipReader.ClipReaderError.cannotDecodeStill("pixel buffer had no base address")
        }

        let dstBytesPerRow = CVPixelBufferGetBytesPerRow(pb)
        let dstHalfBytesPerRow = dstW * 8 // 4 * Float16
        guard dstBytesPerRow >= dstHalfBytesPerRow else {
            throw ClipReader.ClipReaderError.cannotDecodeStill("unexpected pixel buffer stride")
        }

        asset.rawData.withUnsafeBytes { raw in
            let floats = raw.bindMemory(to: Float.self)
            let expected = srcW * srcH
            guard floats.count >= expected else {
                return
            }

            for y in 0..<dstH {
                let dstRow = base.advanced(by: y * dstBytesPerRow)
                let dst = dstRow.bindMemory(to: UInt16.self, capacity: dstW * 4)

                let srcY = min(srcH - 1, Int((Double(y) * Double(srcH)) / Double(dstH)))
                for x in 0..<dstW {
                    let srcX = min(srcW - 1, Int((Double(x) * Double(srcW)) / Double(dstW)))
                    let srcIdx = srcY * srcW + srcX

                    let v = ColorScienceReference.sanitizeFinite(floats[srcIdx])
                    let n = max(0, min(1, (v - black) / denom))
                    let h = Float16(n).bitPattern
                    let a = Float16(1.0).bitPattern

                    dst[(x * 4) + 0] = h
                    dst[(x * 4) + 1] = h
                    dst[(x * 4) + 2] = h
                    dst[(x * 4) + 3] = a
                }
            }
        }

        return pb
    }
}
