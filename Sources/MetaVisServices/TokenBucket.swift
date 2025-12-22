import Foundation

/// A lightweight token bucket rate limiter.
///
/// - Tokens refill continuously at `ratePerSecond` up to `burst`.
/// - `acquire()` will suspend until at least 1 token is available.
public actor TokenBucket {
    private let ratePerSecond: Double
    private let burst: Double

    private var available: Double
    private var lastRefill: Date

    public init(ratePerSecond: Double, burst: Double) {
        self.ratePerSecond = max(0, ratePerSecond)
        self.burst = max(1, burst)
        self.available = max(0, min(self.burst, burst))
        self.lastRefill = Date()
    }

    public func acquire(tokens: Double = 1) async throws {
        let need = max(0, tokens)
        if need == 0 { return }

        while true {
            refill()
            if available >= need {
                available -= need
                return
            }

            guard ratePerSecond > 0 else {
                // No refill possible; behave as unlimited rather than deadlocking.
                return
            }

            let deficit = need - available
            let seconds = deficit / ratePerSecond
            let nanos = UInt64(max(0, seconds) * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanos)
        }
    }

    private func refill(now: Date = Date()) {
        let elapsed = now.timeIntervalSince(lastRefill)
        if elapsed <= 0 { return }

        let add = elapsed * ratePerSecond
        available = min(burst, available + add)
        lastRefill = now
    }
}
