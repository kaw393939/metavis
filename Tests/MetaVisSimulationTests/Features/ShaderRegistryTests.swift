import XCTest
@testable import MetaVisSimulation

final class ShaderRegistryTests: XCTestCase {
    func test_resolve_returns_registered_function() async {
        let registry = ShaderRegistry()
        await registry.register(logicalName: "blur_h", function: "fx_blur_h")
        let resolved = await registry.resolve("blur_h")
        XCTAssertEqual(resolved, "fx_blur_h")
    }

    func test_resolveOrThrow_throws_when_missing() async {
        let registry = ShaderRegistry()
        do {
            _ = try await registry.resolveOrThrow("missing")
            XCTFail("Expected throw")
        } catch {
            // expected
        }
    }
}
