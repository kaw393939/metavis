import Foundation

/// Small orchestration helpers for `PerceptionDevice`.
///
/// Primary use-cases:
/// - Device perf tests and microbenchmarks.
/// - Simple uniform call sites (warm-up / infer loops) without knowing device-specific method names.
public enum PerceptionDeviceHarnessV1 {

    /// Measures average latency (ms) for repeated `infer` calls.
    ///
    /// - Note: This is intentionally a small helper (not a full benchmarking framework).
    @available(macOS 13.0, iOS 16.0, *)
    public static func averageInferMillis<Dev: PerceptionDevice>(
        device: Dev,
        input: Dev.Input,
        iterations: Int
    ) async throws -> Double {
        let iters = max(1, iterations)

        // One warm call to pay setup costs (Vision model init, CoreML graph caches, etc.).
        _ = try await device.infer(input)

        let clock = ContinuousClock()
        let start = clock.now
        for _ in 0..<iters {
            _ = try await device.infer(input)
        }
        let elapsed = clock.now - start

        let c = elapsed.components
        let seconds = Double(c.seconds) + (Double(c.attoseconds) / 1_000_000_000_000_000_000.0)
        return (seconds / Double(iters)) * 1000.0
    }
}
