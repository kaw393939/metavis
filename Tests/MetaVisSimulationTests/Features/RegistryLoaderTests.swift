import XCTest
import MetaVisGraphics
@testable import MetaVisSimulation

final class RegistryLoaderTests: XCTestCase {
    func testLoadsManifestsFromGraphicsBundle() throws {
        let loader = FeatureRegistryLoader(bundle: GraphicsBundleHelper.bundle)
        let manifests = try loader.loadManifests()

        XCTAssertFalse(manifests.isEmpty)
        XCTAssertTrue(manifests.contains(where: { $0.id == "com.metavis.fx.smpte_bars" }))
    }

    func testRegistersManifestsIntoRegistry() async throws {
        let registry = FeatureRegistry()
        let loader = FeatureRegistryLoader(bundle: GraphicsBundleHelper.bundle)

        _ = try await loader.load(into: registry)
        let bars = await registry.feature(for: "com.metavis.fx.smpte_bars")
        XCTAssertEqual(bars?.kernelName, "fx_smpte_bars")
    }
}
