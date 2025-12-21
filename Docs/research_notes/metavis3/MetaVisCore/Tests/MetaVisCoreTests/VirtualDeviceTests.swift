import XCTest
@testable import MetaVisCore

// Mock implementation for testing
struct MockCameraDevice: VirtualDevice {
    var id: UUID
    var name: String
    var type: DeviceType = .camera
    var state: DeviceState = .offline
    var parameters: [String: DeviceParameterValue] = [:]
    
    init(name: String) {
        self.id = UUID()
        self.name = name
    }
    
    mutating func set(parameter: String, value: DeviceParameterValue) {
        parameters[parameter] = value
    }
    
    func execute(action: String) async throws {
        // Mock action
    }
}

final class VirtualDeviceTests: XCTestCase {
    
    func testDeviceInitialization() {
        let device = MockCameraDevice(name: "Main Camera")
        XCTAssertEqual(device.name, "Main Camera")
        XCTAssertEqual(device.type, .camera)
        XCTAssertNotNil(device.id)
    }
    
    func testDeviceParameters() {
        var device = MockCameraDevice(name: "Cam A")
        device.set(parameter: "iso", value: .int(800))
        
        XCTAssertEqual(device.parameters["iso"], .int(800))
        XCTAssertEqual(device.parameters["iso"]?.asInt, 800)
    }
    
    func testDeviceState() {
        var device = MockCameraDevice(name: "Cam B")
        XCTAssertEqual(device.state, .offline)
        
        device.state = .online
        XCTAssertEqual(device.state, .online)
    }
    
    func testDeviceTypeEquality() {
        XCTAssertEqual(DeviceType.camera, DeviceType.camera)
        XCTAssertNotEqual(DeviceType.camera, DeviceType.light)
    }
}
