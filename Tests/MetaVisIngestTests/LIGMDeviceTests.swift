import XCTest
import MetaVisCore
@testable import MetaVisIngest

final class LIGMDeviceTests: XCTestCase {
    
    func testGenerateAction() async throws {
        let device = LIGMDevice()
        
        let result = try await device.perform(action: "generate", with: [
            "prompt": .string("A cinematic shot of a robot")
        ])
        
        guard case .string(let id) = result["assetId"],
              case .string(let url) = result["sourceUrl"] else {
            XCTFail("Missing outputs")
            return
        }
        
        XCTAssertFalse(id.isEmpty)
        XCTAssertTrue(url.contains("A%20cinematic%20shot"))
    }

    func testGenerateRoutesToNoisePlugin() async throws {
        let device = LIGMDevice()

        let result = try await device.perform(action: "generate", with: [
            "prompt": .string("Starfield noise")
        ])

        guard case .string(let id) = result["assetId"],
              case .string(let url) = result["sourceUrl"] else {
            XCTFail("Missing outputs")
            return
        }

        XCTAssertFalse(id.isEmpty)
        XCTAssertTrue(url.hasPrefix("ligm://video/starfield"))
    }
}
