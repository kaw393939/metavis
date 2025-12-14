import Foundation
import Metal

public enum ClipReaderProbe {
    public struct ProbeResult: Sendable {
        public let timeSeconds: Double
        public let success: Bool
        public let errorDescription: String?

        public init(timeSeconds: Double, success: Bool, errorDescription: String?) {
            self.timeSeconds = timeSeconds
            self.success = success
            self.errorDescription = errorDescription
        }
    }

    public static func probe(
        device: MTLDevice,
        assetURL: URL,
        times: [Double],
        width: Int,
        height: Int
    ) async -> [ProbeResult] {
        let reader = ClipReader(device: device)

        var results: [ProbeResult] = []
        results.reserveCapacity(times.count)

        for t in times {
            do {
                _ = try await reader.texture(assetURL: assetURL, timeSeconds: t, width: width, height: height)
                results.append(ProbeResult(timeSeconds: t, success: true, errorDescription: nil))
            } catch {
                results.append(ProbeResult(timeSeconds: t, success: false, errorDescription: String(describing: error)))
            }
        }

        return results
    }
}
