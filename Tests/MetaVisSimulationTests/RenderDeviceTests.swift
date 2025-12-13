import XCTest
import MetaVisSimulation

final class RenderDeviceTests: XCTestCase {

    func testCatalogReportsMetalCapabilities() {
        let catalog = RenderDeviceCatalog()
        let caps = catalog.availableCapabilities()

        XCTAssertFalse(caps.isEmpty)
        XCTAssertTrue(caps.contains(where: { $0.kind == .metalLocal }))
        XCTAssertTrue(caps.contains(where: { $0.supportsWatermark }))
    }
}
