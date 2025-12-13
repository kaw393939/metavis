import Accelerate
import CoreGraphics
import CoreVideo
import Foundation

public struct VideoAnalyzer: Sendable {
    public enum Error: Swift.Error, LocalizedError {
        case unsupportedPixelFormat(OSType)
        case failedToLockPixelBuffer
        case failedToCreateDownscaleBuffer

        public var errorDescription: String? {
            switch self {
            case .unsupportedPixelFormat(let format):
                return "Unsupported pixel format: \(format)"
            case .failedToLockPixelBuffer:
                return "Failed to lock pixel buffer"
            case .failedToCreateDownscaleBuffer:
                return "Failed to create downscale buffer"
            }
        }
    }

    public struct Options: Sendable {
        public var maxDimension: Int

        public init(maxDimension: Int = 256) {
            self.maxDimension = maxDimension
        }
    }

    private let options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    public func analyze(pixelBuffer: CVPixelBuffer) throws -> VideoAnalysis {
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard pixelFormat == kCVPixelFormatType_32BGRA else {
            throw Error.unsupportedPixelFormat(pixelFormat)
        }

        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
            throw Error.failedToLockPixelBuffer
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let srcWidth = CVPixelBufferGetWidth(pixelBuffer)
        let srcHeight = CVPixelBufferGetHeight(pixelBuffer)
        let srcBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let srcBase = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw Error.failedToLockPixelBuffer
        }

        let targetWidth = min(options.maxDimension, srcWidth)
        let targetHeight = min(options.maxDimension, srcHeight)

        let usesDownscale = targetWidth != srcWidth || targetHeight != srcHeight
        let analysisBase: UnsafeMutableRawPointer
        let analysisBytesPerRow: Int
        var downscaleData: UnsafeMutableRawPointer?

        if usesDownscale {
            let bytesPerPixel = 4
            let rowBytes = targetWidth * bytesPerPixel
            downscaleData = malloc(targetHeight * rowBytes)
            guard let downscaleData else { throw Error.failedToCreateDownscaleBuffer }

            var srcBuffer = vImage_Buffer(
                data: srcBase,
                height: vImagePixelCount(srcHeight),
                width: vImagePixelCount(srcWidth),
                rowBytes: srcBytesPerRow
            )
            var dstBuffer = vImage_Buffer(
                data: downscaleData,
                height: vImagePixelCount(targetHeight),
                width: vImagePixelCount(targetWidth),
                rowBytes: rowBytes
            )

            vImageScale_ARGB8888(&srcBuffer, &dstBuffer, nil, vImage_Flags(kvImageNoFlags))

            analysisBase = downscaleData
            analysisBytesPerRow = rowBytes
        } else {
            analysisBase = srcBase
            analysisBytesPerRow = srcBytesPerRow
        }

        defer { free(downscaleData) }

        let pixelCount = targetWidth * targetHeight
        var histogram = Array<Float>(repeating: 0, count: 256)

        // 12-bit quantized RGB histogram for simple dominant-color extraction.
        var rgbBins = Array<Int>(repeating: 0, count: 4096)

        var sumR: Double = 0
        var sumG: Double = 0
        var sumB: Double = 0

        var sumY: Double = 0
        var sumY2: Double = 0

        var skinCount = 0

        for y in 0..<targetHeight {
            let row = analysisBase.advanced(by: y * analysisBytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<targetWidth {
                let i = x * 4
                let b = Double(row[i + 0]) / 255.0
                let g = Double(row[i + 1]) / 255.0
                let r = Double(row[i + 2]) / 255.0

                sumR += r
                sumG += g
                sumB += b

                // Rec.709 luma on gamma-coded RGB (deterministic + cheap).
                let yLuma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                sumY += yLuma
                sumY2 += yLuma * yLuma

                let yBin = max(0, min(255, Int((yLuma * 255.0).rounded(.toNearestOrAwayFromZero))))
                histogram[yBin] += 1

                // Quantize to 4 bits per channel.
                let rq = max(0, min(15, Int((r * 15.0).rounded(.toNearestOrAwayFromZero))))
                let gq = max(0, min(15, Int((g * 15.0).rounded(.toNearestOrAwayFromZero))))
                let bq = max(0, min(15, Int((b * 15.0).rounded(.toNearestOrAwayFromZero))))
                let idx = (rq << 8) | (gq << 4) | bq
                rgbBins[idx] += 1

                // Deterministic, simple skin-tone heuristic.
                let maxc = max(r, g, b)
                let minc = min(r, g, b)
                if r > 0.35 && g > 0.20 && b > 0.15 && r > g && g > b && (maxc - minc) > 0.10 {
                    skinCount += 1
                }
            }
        }

        let invCount = 1.0 / Double(max(1, pixelCount))
        let avgR = Float(sumR * invCount)
        let avgG = Float(sumG * invCount)
        let avgB = Float(sumB * invCount)

        let meanY = sumY * invCount
        let varY = max(0.0, (sumY2 * invCount) - (meanY * meanY))
        _ = varY // reserved for future expansion

        // Normalize histogram to 0..1.
        if pixelCount > 0 {
            let inv = Float(1.0 / Double(pixelCount))
            for i in 0..<histogram.count { histogram[i] *= inv }
        }

        let skinLikelihood = Float(Double(skinCount) * invCount)

        // Top-3 bins by count (stable tie-break by index).
        var top: [(idx: Int, count: Int)] = []
        top.reserveCapacity(3)
        for (idx, count) in rgbBins.enumerated() where count > 0 {
            if top.count < 3 {
                top.append((idx, count))
                top.sort { $0.count != $1.count ? $0.count > $1.count : $0.idx < $1.idx }
            } else if let last = top.last, count > last.count || (count == last.count && idx < last.idx) {
                top.append((idx, count))
                top.sort { $0.count != $1.count ? $0.count > $1.count : $0.idx < $1.idx }
                top = Array(top.prefix(3))
            }
        }

        var dominant: [SIMD3<Float>] = top.map { entry in
            let rq = (entry.idx >> 8) & 0xF
            let gq = (entry.idx >> 4) & 0xF
            let bq = entry.idx & 0xF
            // Use bin center.
            let r = (Float(rq) + 0.5) / 16.0
            let g = (Float(gq) + 0.5) / 16.0
            let b = (Float(bq) + 0.5) / 16.0
            return SIMD3<Float>(r, g, b)
        }

        // Always include average color as a fallback/anchor.
        dominant.insert(SIMD3<Float>(avgR, avgG, avgB), at: 0)

        // Remove near-duplicates (very small threshold).
        dominant = dedupe(colors: dominant, epsilon: 0.02)

        return VideoAnalysis(
            dominantColors: dominant,
            lumaHistogram: histogram,
            skinToneLikelihood: min(1.0, max(0.0, skinLikelihood)),
            faces: []
        )
    }

    private func dedupe(colors: [SIMD3<Float>], epsilon: Float) -> [SIMD3<Float>] {
        var result: [SIMD3<Float>] = []
        for c in colors {
            if !result.contains(where: { distance($0, c) < epsilon }) {
                result.append(c)
            }
        }
        return result
    }

    private func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let d = a - b
        return sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
    }
}
