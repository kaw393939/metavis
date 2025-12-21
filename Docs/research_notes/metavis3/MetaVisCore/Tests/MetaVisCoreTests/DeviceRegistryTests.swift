import XCTest
@testable import MetaVisCore

// Mock Light Device for Polymorphism Testing
struct MockLightDevice: VirtualDevice, Codable {
    var id: UUID
    var name: String
    var type: DeviceType = .light
    var state: DeviceState = .offline
    var parameters: [String: DeviceParameterValue] = [:]
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.parameters["intensity"] = .float(1.0)
    }
    
    mutating func set(parameter: String, value: DeviceParameterValue) {
        parameters[parameter] = value
    }
    
    func execute(action: String) async throws {}
}

final class DeviceRegistryTests: XCTestCase {
    
    func testRegistryInitialization() {
        let registry = DeviceRegistry()
        XCTAssertTrue(registry.devices.isEmpty)
    }
    
    func testAddAndRetrieveDevices() {
        var registry = DeviceRegistry()
        let camera = CameraDevice(name: "Cam A", deviceId: "cam-1")
        let light = MockLightDevice(name: "Light A")
        
        registry.add(camera)
        registry.add(light)
        
        XCTAssertEqual(registry.devices.count, 2)
        XCTAssertNotNil(registry.get(id: camera.id))
        XCTAssertNotNil(registry.get(id: light.id))
    }
    
    func testPolymorphicEncodingDecoding() throws {
        var registry = DeviceRegistry()
        let camera = CameraDevice(name: "Cinema Cam", deviceId: "red-v-raptor")
        let light = MockLightDevice(name: "Key Light")
        
        // Set some specific values to verify persistence
        var mutableCam = camera
        mutableCam.set(parameter: "iso", value: .int(1600))
        registry.add(mutableCam)
        registry.add(light)
        
        // Encode
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(registry)
        
        // Decode
        let decoder = JSONDecoder()
        // We need to register the types so the registry knows how to decode them
        // This is a common pattern for polymorphic decoding
        DeviceRegistry.register(type: CameraDevice.self, for: .camera)
        DeviceRegistry.register(type: MockLightDevice.self, for: .light)
        
        let decodedRegistry = try decoder.decode(DeviceRegistry.self, from: data)
        
        XCTAssertEqual(decodedRegistry.devices.count, 2)
        
        // Verify Camera
        guard let decodedCam = decodedRegistry.get(id: camera.id) as? CameraDevice else {
            XCTFail("Failed to decode CameraDevice")
            return
        }
        XCTAssertEqual(decodedCam.name, "Cinema Cam")
        XCTAssertEqual(decodedCam.parameters["iso"]?.asInt, 1600)
        
        // Verify Light
        guard let decodedLight = decodedRegistry.get(id: light.id) as? MockLightDevice else {
            XCTFail("Failed to decode MockLightDevice")
            return
        }
        XCTAssertEqual(decodedLight.name, "Key Light")
    }
    
    func testUnknownDeviceTypeGracefulFailure() throws {
        // Manually construct JSON with an unknown type
        let json = """
        {
            "devices": [
                {
                    "type": "unknown_future_device",
                    "data": {
                        "id": "00000000-0000-0000-0000-000000000000",
                        "name": "Future Tech",
                        "type": "unknown_future_device",
                        "state": "offline",
                        "parameters": {}
                    }
                }
            ]
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let registry = try decoder.decode(DeviceRegistry.self, from: json)
        
        // Should either ignore it or load it as a generic "UnknownDevice"
        // For robustness, we prefer ignoring or wrapping, but not crashing.
        // Let's assert it handles it safely (e.g., count is 0 if we skip, or 1 if we have a fallback)
        // Decision: We now fallback to UnknownDevice, so count should be 1.
        XCTAssertEqual(registry.devices.count, 1)
        if let firstDevice = registry.devices.first?.value {
            XCTAssertTrue(firstDevice is UnknownDevice)
        } else {
            XCTFail("Registry should contain one device")
        }
    }
    
    func testPerformanceLargeRegistry() throws {
        var registry = DeviceRegistry()
        let count = 1000
        
        for i in 0..<count {
            registry.add(CameraDevice(name: "Cam \(i)", deviceId: "id-\(i)"))
        }
        
        DeviceRegistry.register(type: CameraDevice.self, for: .camera)
        
        measure {
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(registry)
                let decoder = JSONDecoder()
                let _ = try decoder.decode(DeviceRegistry.self, from: data)
            } catch {
                XCTFail("Performance test failed: \(error)")
            }
        }
    }
}
