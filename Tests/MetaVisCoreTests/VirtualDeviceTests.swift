import XCTest
@testable import MetaVisCore

final class VirtualDeviceTests: XCTestCase {
    
    // Mock Implementation
    actor MockCamera: VirtualDevice {
        let id = UUID()
        let name = "Mock Camera"
        let deviceType: DeviceType = .camera
        
        let knowledgeBase = DeviceKnowledgeBase(description: "A mock camera for testing.")
        
        var properties: [String : NodeValue] = [
            "iso": .float(800.0),
            "shutter": .string("180 deg")
        ]
        
        let actions: [String: ActionDefinition] = [
            "record": ActionDefinition(name: "record", description: "Start Recording")
        ]
        
        var lastAction: String? = nil
        
        func perform(action: String, with params: [String : NodeValue]) async throws -> [String : NodeValue] {
            guard actions.keys.contains(action) else {
                throw NSError(domain: "DeviceError", code: 404, userInfo: [NSLocalizedDescriptionKey: "Action not found"])
            }
            lastAction = action
            return [:]
        }
        
        func setProperty(_ key: String, to value: NodeValue) async throws {
            properties[key] = value
        }
    }
    
    func testMockCompliance() async throws {
        let camera = MockCamera()
        
        // 2. Test Name
        XCTAssertEqual(camera.name, "Mock Camera")
        XCTAssertEqual(camera.deviceType, .camera)
        
        // 2. Check Initial State
        let props = await camera.properties
        XCTAssertEqual(props["iso"], .float(800.0))
        
        // 3. Test Property Mutation
        try await camera.setProperty("iso", to: .float(1600.0))
        let newProps = await camera.properties
        XCTAssertEqual(newProps["iso"], .float(1600.0))
        
        // 4. Test Action
        try await camera.perform(action: "record", with: [:])
        let action = await camera.lastAction
        XCTAssertEqual(action, "record")
    }
}
