import XCTest

final class PerfSweepGovernanceTests: XCTestCase {

    func testPerfSweepGovernanceEnforcedOptIn() throws {
        // This is a lightweight policy gate: it doesn't run GPU work.
        // Enable it in CI by setting METAVIS_ENFORCE_PERF_SWEEP_POLICY_TIERS=1.
        guard ProcessInfo.processInfo.environment["METAVIS_ENFORCE_PERF_SWEEP_POLICY_TIERS"] == "1" else {
            throw XCTSkip("Set METAVIS_ENFORCE_PERF_SWEEP_POLICY_TIERS=1 to enforce perf sweep governance")
        }

        XCTAssertEqual(
            ProcessInfo.processInfo.environment["METAVIS_PERF_SWEEP_POLICIES"],
            "1",
            "Governance requires METAVIS_PERF_SWEEP_POLICIES=1 (run consumer/creator/studio tiers)"
        )

        let repeatsRaw = ProcessInfo.processInfo.environment["METAVIS_PERF_SWEEP_REPEATS"] ?? "1"
        let repeats = Int(repeatsRaw) ?? 1
        XCTAssertGreaterThanOrEqual(
            repeats,
            3,
            "Governance requires METAVIS_PERF_SWEEP_REPEATS>=3 to reduce noise (got \(repeatsRaw))"
        )
    }
}
