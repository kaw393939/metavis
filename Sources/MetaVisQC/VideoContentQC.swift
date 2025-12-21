import Foundation
import AVFoundation
import CoreGraphics
import CoreImage
import CoreVideo
import VideoToolbox
import MetaVisPerception

public enum VideoContentQC {
    private static let metalFingerprinter = MetalQCFingerprint.shared
    private static let metalColorStats = MetalQCColorStats.shared
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private final class PixelBufferSampler {
        enum SamplerError: Swift.Error, LocalizedError {
            case missingVideoTrack
            case cannotCreateReader
            case cannotAddOutput
            case cannotStartReading(String)
            case noSample
            case noImageBuffer

            var errorDescription: String? {
                switch self {
                case .missingVideoTrack: return "No video track found"
                case .cannotCreateReader: return "Failed to create AVAssetReader"
                case .cannotAddOutput: return "Failed to configure AVAssetReader output"
                case .cannotStartReading(let msg): return "AVAssetReader failed to start: \(msg)"
                case .noSample: return "No video sample available"
                case .noImageBuffer: return "SampleBuffer missing CVImageBuffer"
                }
            }
        }

        private let asset: AVURLAsset
        private let track: AVAssetTrack
        private let duration: CMTime

        private static let timebaseTimescale: CMTimeScale = 600
        private static let endEpsilon: CMTime = CMTime(value: 1, timescale: timebaseTimescale) // 1/600s
        private static let preroll: CMTime = CMTime(seconds: 2.0, preferredTimescale: timebaseTimescale)

        private var reader: AVAssetReader?
        private var output: AVAssetReaderTrackOutput?
        private var lastPTS: CMTime = .invalid

        private init(asset: AVURLAsset, track: AVAssetTrack, duration: CMTime) {
            self.asset = asset
            self.track = track
            self.duration = duration
        }

        static func make(url: URL) async throws -> PixelBufferSampler {
            let asset = AVURLAsset(url: url)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else {
                throw SamplerError.missingVideoTrack
            }

            let duration = try await asset.load(.duration)
            return PixelBufferSampler(asset: asset, track: track, duration: duration)
        }

        private func clampToAssetDuration(_ time: CMTime) -> CMTime {
            guard duration.isNumeric && duration.seconds.isFinite else {
                return time
            }
            if duration <= .zero {
                return .zero
            }

            let t = CMTimeMaximum(.zero, time)
            let latest = CMTimeMaximum(.zero, duration - Self.endEpsilon)
            return CMTimeMinimum(t, latest)
        }

        private func restart(at time: CMTime) throws {
            reader?.cancelReading()
            reader = nil
            output = nil

            let r: AVAssetReader
            do {
                r = try AVAssetReader(asset: asset)
            } catch {
                throw SamplerError.cannotCreateReader
            }

            let settings: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            let out = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
            out.alwaysCopiesSampleData = false

            guard r.canAdd(out) else {
                throw SamplerError.cannotAddOutput
            }
            r.add(out)

            // Avoid setting `reader.timeRange` here.
            // In practice (and in our own `VideoQC.countVideoSamples`), scanning forward from the start
            // is the most reliable way to ensure we can always decode frames for compressed sources.

            guard r.startReading() else {
                throw SamplerError.cannotStartReading(r.error?.localizedDescription ?? "unknown")
            }

            reader = r
            output = out
            lastPTS = .invalid
        }

        func pixelBuffer(closestTo time: CMTime) throws -> CVPixelBuffer {
            try pixelBufferImpl(closestTo: clampToAssetDuration(time), didRetry: false)
        }

        private func pixelBufferImpl(closestTo time: CMTime, didRetry: Bool) throws -> CVPixelBuffer {
            if reader == nil || output == nil {
                try restart(at: time)
            }
            guard let r = reader, let o = output else {
                throw SamplerError.cannotStartReading("reader/output unavailable")
            }

            if lastPTS.isValid {
                if time < lastPTS {
                    try restart(at: time)
                } else {
                    let delta = CMTimeSubtract(time, lastPTS)
                    if delta.isValid, delta.seconds > 2.0 {
                        try restart(at: time)
                    }
                }
            }

            var previous: CMSampleBuffer?
            var next: CMSampleBuffer?

            while true {
                if let sample = o.copyNextSampleBuffer() {
                    let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                    lastPTS = pts
                    if pts >= time {
                        next = sample
                        break
                    }
                    previous = sample
                    continue
                }

                if r.status == .failed {
                    throw SamplerError.cannotStartReading(r.error?.localizedDescription ?? "failed")
                }
                break
            }

            let chosen: CMSampleBuffer?
            if let prev = previous, let nxt = next {
                let prevPTS = CMSampleBufferGetPresentationTimeStamp(prev)
                let nextPTS = CMSampleBufferGetPresentationTimeStamp(nxt)
                let dp = abs(prevPTS.seconds - time.seconds)
                let dn = abs(nextPTS.seconds - time.seconds)
                chosen = (dn <= dp) ? nxt : prev
            } else {
                chosen = next ?? previous
            }

            guard let sample = chosen else {
                // Some codecs require decode history; retry once starting from an earlier time.
                if !didRetry {
                    // As a last resort, restart from zero (full decode history) and scan forward.
                    try restart(at: .zero)
                    return try pixelBufferImpl(closestTo: time, didRetry: true)
                }
                throw SamplerError.noSample
            }
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sample) else {
                throw SamplerError.noImageBuffer
            }
            return imageBuffer
        }
    }


    public struct Sample: Sendable {
        public var timeSeconds: Double
        public var label: String
        public init(timeSeconds: Double, label: String) {
            self.timeSeconds = timeSeconds
            self.label = label
        }
    }

    public struct Fingerprint: Sendable {
        public var meanR: Double
        public var meanG: Double
        public var meanB: Double
        public var stdR: Double
        public var stdG: Double
        public var stdB: Double

        public func distance(to other: Fingerprint) -> Double {
            let dm = (meanR - other.meanR) * (meanR - other.meanR)
                + (meanG - other.meanG) * (meanG - other.meanG)
                + (meanB - other.meanB) * (meanB - other.meanB)
            let ds = (stdR - other.stdR) * (stdR - other.stdR)
                + (stdG - other.stdG) * (stdG - other.stdG)
                + (stdB - other.stdB) * (stdB - other.stdB)
            return (dm + ds).squareRoot()
        }
    }

    public struct PerceptualHash: Sendable {
        public var hash64: UInt64

        public init(hash64: UInt64) {
            self.hash64 = hash64
        }

        public func hammingDistance(to other: PerceptualHash) -> Int {
            return Int((hash64 ^ other.hash64).nonzeroBitCount)
        }
    }

    public struct LumaSignature: Sendable {
        public var dimension: Int
        public var luma: [UInt8]

        public init(dimension: Int, luma: [UInt8]) {
            self.dimension = dimension
            self.luma = luma
        }

        public func meanAbsDiff(to other: LumaSignature) -> Double {
            guard dimension == other.dimension, luma.count == other.luma.count, !luma.isEmpty else {
                return .infinity
            }
            var sum: Int = 0
            for i in 0..<luma.count {
                sum += abs(Int(luma[i]) - Int(other.luma[i]))
            }
            return Double(sum) / Double(luma.count)
        }
    }

    public static func lumaSignatures(
        movieURL: URL,
        samples: [Sample],
        dimension: Int = 32
    ) async throws -> [(String, LumaSignature)] {
        let sampler = try await PixelBufferSampler.make(url: movieURL)

        var out: [(String, LumaSignature)] = []
        out.reserveCapacity(samples.count)

        for s in samples {
            let time = CMTime(seconds: s.timeSeconds, preferredTimescale: 600)
            let pb = try sampler.pixelBuffer(closestTo: time)
            let luma = try downsampledLuma(pixelBuffer: pb, dimension: dimension)
            out.append((s.label, LumaSignature(dimension: dimension, luma: luma)))
        }

        return out
    }

    public static func perceptualHashes(
        movieURL: URL,
        samples: [Sample]
    ) async throws -> [(String, PerceptualHash)] {
        let sampler = try await PixelBufferSampler.make(url: movieURL)

        var out: [(String, PerceptualHash)] = []
        out.reserveCapacity(samples.count)

        for s in samples {
            let time = CMTime(seconds: s.timeSeconds, preferredTimescale: 600)
            let pb = try sampler.pixelBuffer(closestTo: time)
            let hash = try averageHash64(pixelBuffer: pb)
            out.append((s.label, PerceptualHash(hash64: hash)))
        }

        return out
    }

    private static func averageHash64(pixelBuffer: CVPixelBuffer) throws -> UInt64 {
        // Downsample to 8x8 and compute a deterministic aHash over luma.
        let image = CIImage(cvPixelBuffer: pixelBuffer)

        let extent = image.extent
        let targetW: CGFloat = 8
        let targetH: CGFloat = 8

        let sx = targetW / max(1.0, extent.width)
        let sy = targetH / max(1.0, extent.height)
        let scale = min(sx, sy)

        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let moved = scaled.transformed(by: CGAffineTransform(translationX: -scaled.extent.origin.x, y: -scaled.extent.origin.y))
        let finalRect = CGRect(x: 0, y: 0, width: targetW, height: targetH)
        let finalImage = moved.cropped(to: finalRect)

        guard let cg = ciContext.createCGImage(finalImage, from: finalRect) else {
            throw NSError(domain: "MetaVisQC", code: 41, userInfo: [NSLocalizedDescriptionKey: "Failed to create 8x8 CGImage"])
        }
        guard let cfData = cg.dataProvider?.data else {
            throw NSError(domain: "MetaVisQC", code: 42, userInfo: [NSLocalizedDescriptionKey: "Missing CGImage pixel data"])
        }

        let data = cfData as Data
        let bytes = [UInt8](data)
        let bytesPerPixel = 4
        guard bytes.count >= Int(targetW * targetH) * bytesPerPixel else {
            throw NSError(domain: "MetaVisQC", code: 43, userInfo: [NSLocalizedDescriptionKey: "Unexpected CGImage pixel data size"])
        }

        var luma: [UInt8] = []
        luma.reserveCapacity(64)

        for i in 0..<(Int(targetW) * Int(targetH)) {
            let base = i * bytesPerPixel
            let r = Int(bytes[base + 0])
            let g = Int(bytes[base + 1])
            let b = Int(bytes[base + 2])
            // ITU-R BT.601 luma approximation.
            let y = (299 * r + 587 * g + 114 * b) / 1000
            luma.append(UInt8(max(0, min(255, y))))
        }

        return FaceIdentityService.averageHash64(fromLuma8x8: luma)
    }

    private static func downsampledLuma(pixelBuffer: CVPixelBuffer, dimension: Int) throws -> [UInt8] {
        let dim = max(2, min(256, dimension))
        let image = CIImage(cvPixelBuffer: pixelBuffer)

        let extent = image.extent
        let targetW = CGFloat(dim)
        let targetH = CGFloat(dim)

        let sx = targetW / max(1.0, extent.width)
        let sy = targetH / max(1.0, extent.height)
        let scale = min(sx, sy)

        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let moved = scaled.transformed(by: CGAffineTransform(translationX: -scaled.extent.origin.x, y: -scaled.extent.origin.y))
        let finalRect = CGRect(x: 0, y: 0, width: targetW, height: targetH)
        let finalImage = moved.cropped(to: finalRect)

        guard let cg = ciContext.createCGImage(finalImage, from: finalRect) else {
            throw NSError(domain: "MetaVisQC", code: 51, userInfo: [NSLocalizedDescriptionKey: "Failed to create downsampled CGImage"])
        }
        guard let cfData = cg.dataProvider?.data else {
            throw NSError(domain: "MetaVisQC", code: 52, userInfo: [NSLocalizedDescriptionKey: "Missing CGImage pixel data"])
        }

        let data = cfData as Data
        let bytes = [UInt8](data)
        let bytesPerPixel = 4
        guard bytes.count >= dim * dim * bytesPerPixel else {
            throw NSError(domain: "MetaVisQC", code: 53, userInfo: [NSLocalizedDescriptionKey: "Unexpected CGImage pixel data size"])
        }

        var luma: [UInt8] = []
        luma.reserveCapacity(dim * dim)

        for i in 0..<(dim * dim) {
            let base = i * bytesPerPixel
            let r = Int(bytes[base + 0])
            let g = Int(bytes[base + 1])
            let b = Int(bytes[base + 2])
            let y = (299 * r + 587 * g + 114 * b) / 1000
            luma.append(UInt8(max(0, min(255, y))))
        }

        return luma
    }

    /// Samples frames and computes a lightweight fingerprint; fails if adjacent samples are too similar.
    public static func assertTemporalVariety(
        movieURL: URL,
        samples: [Sample],
        minDistance: Double = 0.020
    ) async throws {
        let fps = try await fingerprints(movieURL: movieURL, samples: samples)
        for i in 1..<fps.count {
            let (prev, prevFP) = fps[i - 1]
            let (cur, curFP) = fps[i]
            let d = prevFP.distance(to: curFP)
            if d < minDistance {
                let dStr = String(format: "%.5f", d)
                throw NSError(
                    domain: "MetaVisQC",
                    code: 30,
                    userInfo: [NSLocalizedDescriptionKey: "Frames too similar (d=\(dStr)) between \(prev) and \(cur). Possible stuck source."]
                )
            }
        }
    }

    public static func fingerprints(
        movieURL: URL,
        samples: [Sample]
    ) async throws -> [(String, Fingerprint)] {
        let sampler = try await PixelBufferSampler.make(url: movieURL)

        var out: [(String, Fingerprint)] = []
        out.reserveCapacity(samples.count)

        for s in samples {
            let time = CMTime(seconds: s.timeSeconds, preferredTimescale: 600)
            let pb = try sampler.pixelBuffer(closestTo: time)
            let fp = try fingerprint(pixelBuffer: pb)
            out.append((s.label, fp))
        }
        return out
    }

    public struct ColorStatsSample: Sendable {
        public var timeSeconds: Double
        public var label: String

        // Expected bounds/shape (kept intentionally coarse/tolerant).
        public var minMeanLuma: Float
        public var maxMeanLuma: Float
        public var maxChannelDelta: Float
        public var minLowLumaFraction: Float
        public var minHighLumaFraction: Float

        public init(
            timeSeconds: Double,
            label: String,
            minMeanLuma: Float,
            maxMeanLuma: Float,
            maxChannelDelta: Float,
            minLowLumaFraction: Float,
            minHighLumaFraction: Float
        ) {
            self.timeSeconds = timeSeconds
            self.label = label
            self.minMeanLuma = minMeanLuma
            self.maxMeanLuma = maxMeanLuma
            self.maxChannelDelta = maxChannelDelta
            self.minLowLumaFraction = minLowLumaFraction
            self.minHighLumaFraction = minHighLumaFraction
        }
    }

    public struct ColorStatsResult: Sendable {
        public var label: String
        public var timeSeconds: Double
        public var meanRGB: SIMD3<Float>
        public var meanLuma: Float
        public var lowLumaFraction: Float
        public var highLumaFraction: Float
        public var peakBin: Int
    }

    /// Computes deterministic color statistics on a downscaled proxy and validates them against coarse expectations.
    /// Intended for fast, local QC of known test patterns.
    public static func validateColorStats(
        movieURL: URL,
        samples: [ColorStatsSample],
        maxDimension: Int = 256
    ) async throws -> [ColorStatsResult] {
        let sampler = try await PixelBufferSampler.make(url: movieURL)

        var out: [ColorStatsResult] = []
        out.reserveCapacity(samples.count)

        for s in samples {
            let time = CMTime(seconds: s.timeSeconds, preferredTimescale: 600)
            let pb = try sampler.pixelBuffer(closestTo: time)

            let meanRGB: SIMD3<Float>
            let histogram: [Float]
            let peakBin: Int

            if let metalColorStats {
                do {
                    let result = try metalColorStats.colorStats(pixelBuffer: pb, maxDimension: maxDimension)
                    meanRGB = result.meanRGB
                    histogram = result.histogram
                    peakBin = result.peakBin
                } catch {
                    let analyzer = VideoAnalyzer(options: .init(maxDimension: maxDimension))
                    let analysis = try analyzer.analyze(pixelBuffer: pb)
                    meanRGB = analysis.dominantColors.first ?? SIMD3<Float>(0, 0, 0)
                    histogram = analysis.lumaHistogram
                    peakBin = analysis.lumaHistogram.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
                }
            } else {
                let analyzer = VideoAnalyzer(options: .init(maxDimension: maxDimension))
                let analysis = try analyzer.analyze(pixelBuffer: pb)
                meanRGB = analysis.dominantColors.first ?? SIMD3<Float>(0, 0, 0)
                histogram = analysis.lumaHistogram
                peakBin = analysis.lumaHistogram.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
            }

            let meanLuma = meanLuma(from: histogram)
            let lowFrac = lumaFraction(in: histogram, range: 0...25)
            let highFrac = lumaFraction(in: histogram, range: 230...255)

            // Coarse validation.
            if !(meanLuma >= s.minMeanLuma && meanLuma <= s.maxMeanLuma) {
                throw NSError(
                    domain: "MetaVisQC",
                    code: 40,
                    userInfo: [NSLocalizedDescriptionKey: "Mean luma out of range for \(s.label): \(meanLuma) not in [\(s.minMeanLuma), \(s.maxMeanLuma)]"]
                )
            }

            let dRG = abs(meanRGB.x - meanRGB.y)
            let dGB = abs(meanRGB.y - meanRGB.z)
            let dRB = abs(meanRGB.x - meanRGB.z)
            let maxDelta = max(dRG, max(dGB, dRB))
            if maxDelta > s.maxChannelDelta {
                throw NSError(
                    domain: "MetaVisQC",
                    code: 41,
                    userInfo: [NSLocalizedDescriptionKey: "Average RGB not neutral enough for \(s.label): maxΔ=\(maxDelta) > \(s.maxChannelDelta)"]
                )
            }

            if lowFrac < s.minLowLumaFraction {
                throw NSError(
                    domain: "MetaVisQC",
                    code: 42,
                    userInfo: [NSLocalizedDescriptionKey: "Too little low-luma content for \(s.label): \(lowFrac) < \(s.minLowLumaFraction)"]
                )
            }

            if highFrac < s.minHighLumaFraction {
                throw NSError(
                    domain: "MetaVisQC",
                    code: 43,
                    userInfo: [NSLocalizedDescriptionKey: "Too little high-luma content for \(s.label): \(highFrac) < \(s.minHighLumaFraction)"]
                )
            }

            out.append(ColorStatsResult(
                label: s.label,
                timeSeconds: s.timeSeconds,
                meanRGB: meanRGB,
                meanLuma: meanLuma,
                lowLumaFraction: lowFrac,
                highLumaFraction: highFrac,
                peakBin: peakBin
            ))
        }

        return out
    }

    private static func fingerprint(pixelBuffer: CVPixelBuffer) throws -> Fingerprint {
        if let metalFingerprinter {
            do {
                return try metalFingerprinter.fingerprint(pixelBuffer: pixelBuffer)
            } catch {
                // Fall through to CPU.
            }
        }

        // CPU fallback: keep behavior stable by converting to CGImage and reusing existing path.
        var cg: CGImage?
        let status = VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cg)
        if status == noErr, let cg {
            return try fingerprintCPU(cgImage: cg)
        }

        throw NSError(domain: "MetaVisQC", code: 32, userInfo: [NSLocalizedDescriptionKey: "Failed to compute fingerprint (Metal unavailable + CVPixelBuffer->CGImage conversion failed)"])
    }

    private static func fingerprint(cgImage: CGImage) throws -> Fingerprint {
        // Prefer Metal path (tiny GPU reduction + tiny readback). Fall back to CPU for environments
        // without Metal or if the Metal pipeline is unavailable.
        if let metalFingerprinter {
            do {
                let pb = try pixelBuffer(from: cgImage)
                return try metalFingerprinter.fingerprint(pixelBuffer: pb)
            } catch {
                // Fall through to CPU.
            }
        }

        return try fingerprintCPU(cgImage: cgImage)
    }

    private static func fingerprintCPU(cgImage: CGImage) throws -> Fingerprint {
        // Downsample to keep this fast + deterministic.
        let w = 64
        let h = 36

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = w * bytesPerPixel
        var buf = [UInt8](repeating: 0, count: w * h * bytesPerPixel)

        guard let ctx = CGContext(
            data: &buf,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "MetaVisQC", code: 31, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGContext"])
        }

        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        let n = Double(w * h)
        var sumR = 0.0, sumG = 0.0, sumB = 0.0
        var sumR2 = 0.0, sumG2 = 0.0, sumB2 = 0.0

        for i in stride(from: 0, to: buf.count, by: 4) {
            let r = Double(buf[i]) / 255.0
            let g = Double(buf[i + 1]) / 255.0
            let b = Double(buf[i + 2]) / 255.0
            sumR += r; sumG += g; sumB += b
            sumR2 += r * r; sumG2 += g * g; sumB2 += b * b
        }

        let meanR = sumR / n
        let meanG = sumG / n
        let meanB = sumB / n

        let varR = max(0.0, (sumR2 / n) - meanR * meanR)
        let varG = max(0.0, (sumG2 / n) - meanG * meanG)
        let varB = max(0.0, (sumB2 / n) - meanB * meanB)

        return Fingerprint(
            meanR: meanR,
            meanG: meanG,
            meanB: meanB,
            stdR: varR.squareRoot(),
            stdG: varG.squareRoot(),
            stdB: varB.squareRoot()
        )
    }

    private static func meanLuma(from histogram: [Float]) -> Float {
        if histogram.isEmpty { return 0 }
        var m: Float = 0
        let denom: Float = 255.0
        for (i, p) in histogram.enumerated() {
            m += (Float(i) / denom) * p
        }
        return m
    }

    private static func lumaFraction(in histogram: [Float], range: ClosedRange<Int>) -> Float {
        if histogram.isEmpty { return 0 }
        let lo = max(0, range.lowerBound)
        let hi = min(histogram.count - 1, range.upperBound)
        if lo > hi { return 0 }
        var s: Float = 0
        for i in lo...hi { s += histogram[i] }
        return s
    }

    private static func pixelBuffer(from cgImage: CGImage) throws -> CVPixelBuffer {
        let width = cgImage.width
        let height = cgImage.height

        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pb
        )
        guard status == kCVReturnSuccess, let pb else {
            throw NSError(domain: "MetaVisQC", code: 44, userInfo: [NSLocalizedDescriptionKey: "CVPixelBufferCreate failed (\(status))"])
        }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let base = CVPixelBufferGetBaseAddress(pb) else {
            throw NSError(domain: "MetaVisQC", code: 45, userInfo: [NSLocalizedDescriptionKey: "No pixel buffer base address"])
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue))

        guard let ctx = CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw NSError(domain: "MetaVisQC", code: 46, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGContext"])
        }

        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pb
    }
}
