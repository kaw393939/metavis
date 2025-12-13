import XCTest
@testable import MetaVisSimulation

final class PassSchedulerTests: XCTestCase {
    func test_topological_sort_resolves_dependencies() throws {
        let passes = [
            FeaturePass(logicalName: "C", function: "C", inputs: ["b"], output: "c"),
            FeaturePass(logicalName: "A", function: "A", inputs: ["source"], output: "a"),
            FeaturePass(logicalName: "B", function: "B", inputs: ["a"], output: "b")
        ]

        let ordered = try PassScheduler().schedule(passes)
        XCTAssertEqual(ordered.map { $0.logicalName }, ["A", "B", "C"])
    }

    func test_topological_sort_detects_cycle() {
        let passes = [
            FeaturePass(logicalName: "A", function: "A", inputs: ["b"], output: "a"),
            FeaturePass(logicalName: "B", function: "B", inputs: ["a"], output: "b")
        ]

        XCTAssertThrowsError(try PassScheduler().schedule(passes)) { error in
            XCTAssertEqual(error as? PassScheduler.Error, .cycleDetected)
        }
    }
}
