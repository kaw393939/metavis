import Foundation
import AVFoundation
import CoreGraphics
import CoreVideo
import MetaVisPerception

public enum VideoContentQC {
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
        let asset = AVURLAsset(url: movieURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        var out: [(String, Fingerprint)] = []
        out.reserveCapacity(samples.count)

        for s in samples {
            let time = CMTime(seconds: s.timeSeconds, preferredTimescale: 600)
            let cg = try generator.copyCGImage(at: time, actualTime: nil)
            let fp = try fingerprint(cgImage: cg)
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
        let asset = AVURLAsset(url: movieURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let analyzer = VideoAnalyzer(options: .init(maxDimension: maxDimension))

        var out: [ColorStatsResult] = []
        out.reserveCapacity(samples.count)

        for s in samples {
            let time = CMTime(seconds: s.timeSeconds, preferredTimescale: 600)
            let cg = try generator.copyCGImage(at: time, actualTime: nil)
            let pb = try pixelBuffer(from: cg)
            let analysis = try analyzer.analyze(pixelBuffer: pb)

            let meanRGB = analysis.dominantColors.first ?? SIMD3<Float>(0, 0, 0)
            let meanLuma = meanLuma(from: analysis.lumaHistogram)
            let lowFrac = lumaFraction(in: analysis.lumaHistogram, range: 0...25)
            let highFrac = lumaFraction(in: analysis.lumaHistogram, range: 230...255)
            let peakBin = analysis.lumaHistogram.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0

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

    private static func fingerprint(cgImage: CGImage) throws -> Fingerprint {
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
