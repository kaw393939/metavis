import Foundation
import CryptoKit

enum FrameHashing {
    /// Interprets `data` as tightly-packed `Float32` RGBA pixels.
    static func sha256DownsampledRGBA8Hex(
        floatRGBAData data: Data,
        width: Int,
        height: Int,
        downsampleTo targetSize: Int = 64
    ) -> String {
        precondition(width > 0 && height > 0)
        precondition(targetSize > 0)
        precondition(width % targetSize == 0 && height % targetSize == 0, "downsampleTo must evenly divide dimensions")

        let floats: [Float] = data.withUnsafeBytes { raw in
            let ptr = raw.bindMemory(to: Float.self)
            return Array(ptr)
        }
        precondition(floats.count == width * height * 4)

        let scaleX = width / targetSize
        let scaleY = height / targetSize

        var bytes = [UInt8]()
        bytes.reserveCapacity(targetSize * targetSize * 4)

        func clamp01(_ x: Float) -> Float {
            if x < 0 { return 0 }
            if x > 1 { return 1 }
            return x
        }

        for ty in 0..<targetSize {
            for tx in 0..<targetSize {
                var sumR: Float = 0
                var sumG: Float = 0
                var sumB: Float = 0
                var sumA: Float = 0

                let x0 = tx * scaleX
                let y0 = ty * scaleY
                for y in y0..<(y0 + scaleY) {
                    for x in x0..<(x0 + scaleX) {
                        let i = (y * width + x) * 4
                        sumR += floats[i + 0]
                        sumG += floats[i + 1]
                        sumB += floats[i + 2]
                        sumA += floats[i + 3]
                    }
                }

                let denom = Float(scaleX * scaleY)
                let r = clamp01(sumR / denom)
                let g = clamp01(sumG / denom)
                let b = clamp01(sumB / denom)
                let a = clamp01(sumA / denom)

                bytes.append(UInt8((r * 255.0).rounded()))
                bytes.append(UInt8((g * 255.0).rounded()))
                bytes.append(UInt8((b * 255.0).rounded()))
                bytes.append(UInt8((a * 255.0).rounded()))
            }
        }

        let digest = SHA256.hash(data: Data(bytes))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
