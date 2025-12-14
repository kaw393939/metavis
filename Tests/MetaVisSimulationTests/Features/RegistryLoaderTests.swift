import XCTest
import MetaVisGraphics
@testable import MetaVisSimulation

final class RegistryLoaderTests: XCTestCase {
    func testLoadsManifestsFromGraphicsBundle() throws {
        let loader = FeatureRegistryLoader(bundle: GraphicsBundleHelper.bundle)
        let manifests = try loader.loadManifests()

        XCTAssertFalse(manifests.isEmpty)
        XCTAssertTrue(manifests.contains(where: { $0.id == "com.metavis.fx.smpte_bars" }))
        XCTAssertTrue(manifests.contains(where: { $0.id == "audio.dialogCleanwater.v1" && $0.domain == .audio }))
        XCTAssertTrue(manifests.contains(where: { $0.id == "mv.retime" && $0.domain == .intrinsic }))
        XCTAssertTrue(manifests.contains(where: { $0.id == "mv.colorGrade" && $0.domain == .intrinsic }))
    }

    func testRegistersManifestsIntoRegistry() async throws {
        let registry = FeatureRegistry()
        let loader = FeatureRegistryLoader(bundle: GraphicsBundleHelper.bundle)

        _ = try await loader.load(into: registry)
        let bars = await registry.feature(for: "com.metavis.fx.smpte_bars")
        XCTAssertEqual(bars?.kernelName, "fx_smpte_bars")

        let retime = await registry.feature(for: "mv.retime")
        XCTAssertEqual(retime?.domain, .intrinsic)
    }
}
