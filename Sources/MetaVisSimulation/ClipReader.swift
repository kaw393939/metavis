import Foundation
import AVFoundation
import Metal
import CoreVideo
import CoreMedia
import CoreImage
import MetaVisCore

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

    private var stillPixelBuffers: [DecoderKey: CVPixelBuffer] = [:]

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

        let isEXR = assetURL.pathExtension.lowercased() == "exr"

        let decodedPixelBuffer: CVPixelBuffer
        if isEXR {
            let stillKey = DecoderKey(assetURL: assetURL.absoluteString, width: width, height: height)
            if let cached = stillPixelBuffers[stillKey] {
                decodedPixelBuffer = cached
            } else {
                let pb = try FFmpegEXRDecoder.decodeFirstFrameRGBAHalf(exrURL: assetURL, width: width, height: height)
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

            let requestTime = CMTime(seconds: timeSeconds, preferredTimescale: 600)
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

        if isEXR {
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

// MARK: - EXR decoding (ffmpeg-based)

private enum FFmpegEXRDecoder {
    enum DecodeError: Error, LocalizedError {
        case ffprobeFailed(String)
        case ffmpegFailed(String)
        case invalidProbeOutput
        case invalidDimensions
        case unexpectedByteCount(expected: Int, got: Int)
        case cannotCreatePixelBuffer(OSStatus)

        var errorDescription: String? {
            switch self {
            case .ffprobeFailed(let msg): return "ffprobe failed: \(msg)"
            case .ffmpegFailed(let msg): return "ffmpeg failed: \(msg)"
            case .invalidProbeOutput: return "ffprobe returned unexpected output"
            case .invalidDimensions: return "ffprobe returned invalid dimensions"
            case .unexpectedByteCount(let expected, let got): return "ffmpeg raw output size mismatch (expected \(expected) bytes, got \(got) bytes)"
            case .cannotCreatePixelBuffer(let status): return "CVPixelBufferCreate failed (\(status))"
            }
        }
    }

    static func decodeFirstFrameRGBAHalf(exrURL: URL, width w: Int, height h: Int) throws -> CVPixelBuffer {
        guard w > 0, h > 0 else { throw DecodeError.invalidDimensions }

        // NOTE: We intentionally avoid piping rawvideo through stdout here.
        // In practice, larger frames (e.g. 1280x720+) can intermittently hang/timeout
        // when captured via pipes, causing the engine to fall back to black.
        // Writing to a temporary file is slower in theory but far more robust and
        // only happens once per EXR+resolution due to ClipReader caching.
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("metavis_exr_\(UUID().uuidString).rgba128le")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let raw = try runFFmpegAndReadFile(
            args: [
                "-nostdin",
                "-y",
                "-v", "error",
                "-i", exrURL.path,
                "-frames:v", "1",
                "-vf", "scale=\(w):\(h):flags=bicubic,format=gbrapf32le",
                "-f", "rawvideo",
                "-pix_fmt", "gbrapf32le",
                tmpURL.path
            ],
            timeoutSeconds: 20.0
        )

        let expectedBytes = w * h * 16 // 4 * Float32
        guard raw.count >= expectedBytes else {
            throw DecodeError.unexpectedByteCount(expected: expectedBytes, got: raw.count)
        }

        // Convert float32 RGBA -> float16 RGBA (sanitized) into a CVPixelBuffer.
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
            throw DecodeError.cannotCreatePixelBuffer(-1)
        }

        let dstBytesPerRow = CVPixelBufferGetBytesPerRow(pb)
        let dstHalfBytesPerRow = w * 8 // 4 * Float16
        guard dstBytesPerRow >= dstHalfBytesPerRow else {
            throw DecodeError.cannotCreatePixelBuffer(-2)
        }

        raw.prefix(expectedBytes).withUnsafeBytes { srcRaw in
            let srcFloats = srcRaw.bindMemory(to: Float.self)
            let planeSize = w * h
            let gOff = 0 * planeSize
            let bOff = 1 * planeSize
            let rOff = 2 * planeSize
            let aOff = 3 * planeSize

            for y in 0..<h {
                let dstRow = base.advanced(by: y * dstBytesPerRow)
                let dst = dstRow.bindMemory(to: UInt16.self, capacity: w * 4)
                for x in 0..<w {
                    let p = (y * w + x)
                    let r = ColorScienceReference.sanitizeFinite(srcFloats[rOff + p])
                    let g = ColorScienceReference.sanitizeFinite(srcFloats[gOff + p])
                    let b = ColorScienceReference.sanitizeFinite(srcFloats[bOff + p])
                    let a = ColorScienceReference.sanitizeFinite(srcFloats[aOff + p])

                    dst[(x * 4) + 0] = Float16(r).bitPattern
                    dst[(x * 4) + 1] = Float16(g).bitPattern
                    dst[(x * 4) + 2] = Float16(b).bitPattern
                    dst[(x * 4) + 3] = Float16(a).bitPattern
                }
            }
        }

        return pb
    }

    private static func runFFmpegAndReadFile(args: [String], timeoutSeconds: Double) throws -> Data {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["ffmpeg"] + args

        let errPipe = Pipe()
        p.standardError = errPipe

        try p.run()

        let start = Date()
        while p.isRunning {
            if Date().timeIntervalSince(start) > timeoutSeconds {
                p.terminate()
                // Give ffmpeg a moment to exit.
                Thread.sleep(forTimeInterval: 0.05)
                throw DecodeError.ffmpegFailed("ffmpeg timed out after \(timeoutSeconds)s")
            }
            Thread.sleep(forTimeInterval: 0.005)
        }

        p.waitUntilExit()

        let err = errPipe.fileHandleForReading.readDataToEndOfFile()
        guard p.terminationStatus == 0 else {
            let msg = (String(data: err, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            throw DecodeError.ffmpegFailed(msg.isEmpty ? "ffmpeg failed" : msg)
        }

        // The last arg is the output file path.
        guard let outPath = p.arguments?.last else {
            throw DecodeError.ffmpegFailed("ffmpeg produced no output path")
        }
        let outURL = URL(fileURLWithPath: outPath)
        return try Data(contentsOf: outURL)
    }
}
