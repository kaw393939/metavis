import XCTest
import MetaVisCore
import MetaVisSimulation

final class RenderDeviceTests: XCTestCase {

    func testCatalogReportsMetalCapabilities() {
        let catalog = RenderDeviceCatalog()
        let caps = catalog.availableCapabilities()

        XCTAssertFalse(caps.isEmpty)
        XCTAssertTrue(caps.contains(where: { $0.kind == .metalLocal }))
        XCTAssertTrue(caps.contains(where: { $0.supportsWatermark }))
    }

    func testCatalogBestCapabilitiesSelectsCompatibleDevice() {
        let catalog = RenderDeviceCatalog()

        let quality = QualityProfile(name: "Test", fidelity: .high, resolutionHeight: 2160, colorDepth: 10)
        let caps = catalog.bestCapabilities(for: quality)

        XCTAssertEqual(caps?.kind, .metalLocal)
        XCTAssertNotNil(caps)
    }

    func testCatalogBestCapabilitiesReturnsNilWhenResolutionTooHigh() {
        let catalog = RenderDeviceCatalog()

        let quality = QualityProfile(name: "TooBig", fidelity: .master, resolutionHeight: 99999, colorDepth: 10)
        let caps = catalog.bestCapabilities(for: quality)

        XCTAssertNil(caps)
    }

    func testCatalogBestCapabilitiesHonorsWatermarkRequirement() {
        let catalog = RenderDeviceCatalog()

        let quality = QualityProfile(name: "NeedsWM", fidelity: .high, resolutionHeight: 1080, colorDepth: 8)
        let watermark = WatermarkSpec.diagonalStripesDefault
        let caps = catalog.bestCapabilities(for: quality, watermark: watermark)

        XCTAssertNotNil(caps)
        XCTAssertTrue(caps?.supportsWatermark ?? false)
    }
}
