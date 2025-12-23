import Foundation
import CoreVideo

enum PerfColorBaselines {

    struct Fingerprint: Codable, Equatable {
        var meanRGB: [Double] // [r,g,b]
        var stdRGB: [Double]  // [r,g,b]
        var samples: Int
        var hash: String
    }

    static func isEnabled() -> Bool {
        ProcessInfo.processInfo.environment["METAVIS_PERF_QC_BASELINES"] == "1"
    }

    static func isWriteEnabled() -> Bool {
        ProcessInfo.processInfo.environment["METAVIS_PERF_QC_BASELINES_WRITE"] == "1"
    }

    static func isStrict() -> Bool {
        ProcessInfo.processInfo.environment["METAVIS_PERF_QC_STRICT"] == "1"
    }

    static func maxDistance() -> Double {
        Double(ProcessInfo.processInfo.environment["METAVIS_PERF_QC_DISTANCE_MAX"] ?? "") ?? 0.02
    }

    static func defaultBaselinesPath() -> String {
        // Package root in `swift test` is typically currentDirectoryPath.
        let cwd = FileManager.default.currentDirectoryPath
        return (cwd as NSString).appendingPathComponent("Tests/MetaVisSimulationTests/Perf/perf_color_baselines.json")
    }

    static func baselinesPath() -> String {
        if let p = ProcessInfo.processInfo.environment["METAVIS_PERF_QC_BASELINES_PATH"], !p.isEmpty {
            return p
        }
        return defaultBaselinesPath()
    }

    private static func normalizeLabel(_ label: String) -> String {
        // Drops trailing repeat suffix like "#3".
        guard let hashIdx = label.lastIndex(of: "#") else { return label }
        let suffix = label[label.index(after: hashIdx)...]
        if suffix.allSatisfy({ $0.isNumber }) {
            return String(label[..<hashIdx])
        }
        return label
    }

    static func baselineKey(
        suite: String,
        baselineLabel: String,
        width: Int,
        height: Int,
        policy: String
    ) -> String {
        let normalized = normalizeLabel(baselineLabel)
        return "\(suite)|\(normalized)|policy=\(policy)|\(width)x\(height)"
    }

    static func loadBaselines() -> [String: Fingerprint] {
        let path = baselinesPath()
        guard FileManager.default.fileExists(atPath: path) else { return [:] }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [:] }
        return (try? JSONDecoder().decode([String: Fingerprint].self, from: data)) ?? [:]
    }

    static func saveBaselines(_ baselines: [String: Fingerprint]) {
        let path = baselinesPath()
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? enc.encode(baselines) else { return }
        try? data.write(to: URL(fileURLWithPath: path), options: [.atomic])
    }

    static func computeFingerprint(pixelBuffer: CVPixelBuffer, targetSamples: Int = 2048) -> Fingerprint? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return nil }

        let fmt = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard fmt == kCVPixelFormatType_64RGBAHalf else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddr = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let strideU16 = bytesPerRow / MemoryLayout<UInt16>.size
        let base = baseAddr.assumingMemoryBound(to: UInt16.self)

        let pixelCount = width * height
        let desired = max(64, min(targetSamples, pixelCount))
        let step = max(1, pixelCount / desired)

        var sumR = 0.0, sumG = 0.0, sumB = 0.0
        var sumSqR = 0.0, sumSqG = 0.0, sumSqB = 0.0

        var taken = 0
        var p = 0
        while taken < desired {
            let idx = p % pixelCount
            let x = idx % width
            let y = idx / width
            let row = base.advanced(by: y * strideU16)
            let px = row.advanced(by: x * 4)

            let r = Double(Float(Float16(bitPattern: px[0])))
            let g = Double(Float(Float16(bitPattern: px[1])))
            let b = Double(Float(Float16(bitPattern: px[2])))

            sumR += r; sumG += g; sumB += b
            sumSqR += r * r; sumSqG += g * g; sumSqB += b * b

            taken += 1
            p += step
        }

        let n = Double(max(1, taken))
        let meanR = sumR / n
        let meanG = sumG / n
        let meanB = sumB / n

        let varR = max(0.0, (sumSqR / n) - (meanR * meanR))
        let varG = max(0.0, (sumSqG / n) - (meanG * meanG))
        let varB = max(0.0, (sumSqB / n) - (meanB * meanB))

        let stdR = sqrt(varR)
        let stdG = sqrt(varG)
        let stdB = sqrt(varB)

        let q = quantizedSignature(meanR: meanR, meanG: meanG, meanB: meanB, stdR: stdR, stdG: stdG, stdB: stdB)
        let h = fnv1a64Hex(q)

        return Fingerprint(meanRGB: [meanR, meanG, meanB], stdRGB: [stdR, stdG, stdB], samples: taken, hash: h)
    }

    static func distance(_ a: Fingerprint, _ b: Fingerprint) -> Double {
        // Simple Euclidean distance over mean/std (6D).
        let am = a.meanRGB
        let bm = b.meanRGB
        let asd = a.stdRGB
        let bsd = b.stdRGB

        guard am.count == 3, bm.count == 3, asd.count == 3, bsd.count == 3 else { return Double.infinity }

        var s = 0.0
        for i in 0..<3 {
            s += (am[i] - bm[i]) * (am[i] - bm[i])
            s += (asd[i] - bsd[i]) * (asd[i] - bsd[i])
        }
        return sqrt(s)
    }

    private static func quantizedSignature(meanR: Double, meanG: Double, meanB: Double, stdR: Double, stdG: Double, stdB: Double) -> String {
        // Quantize to reduce floating jitter; stable across minor numeric noise.
        func q(_ v: Double) -> Int { Int((v * 10_000.0).rounded()) }
        return "m:\(q(meanR)),\(q(meanG)),\(q(meanB))|s:\(q(stdR)),\(q(stdG)),\(q(stdB))"
    }

    private static func fnv1a64Hex(_ s: String) -> String {
        let bytes = Array(s.utf8)
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        for b in bytes {
            hash ^= UInt64(b)
            hash &*= prime
        }
        return String(format: "%016llx", hash)
    }
}
