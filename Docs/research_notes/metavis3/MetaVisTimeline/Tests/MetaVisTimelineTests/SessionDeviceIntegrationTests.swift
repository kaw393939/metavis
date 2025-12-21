import XCTest
import MetaVisCore
@testable import MetaVisTimeline

final class SessionDeviceIntegrationTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Register types for polymorphic decoding
        DeviceRegistry.register(type: CameraDevice.self, for: .camera)
    }
    
    func testSessionInitializationHasEmptyRegistry() {
        let session = MetaVisSession()
        XCTAssertTrue(session.devices.devices.isEmpty, "New session should have empty device registry")
    }
    
    func testAddingDeviceToSession() {
        var session = MetaVisSession()
        let camera = CameraDevice(name: "Session Cam", deviceId: "cam-session-1")
        
        session.devices.add(camera)
        
        XCTAssertEqual(session.devices.devices.count, 1)
        XCTAssertNotNil(session.devices.get(id: camera.id))
    }
    
    func testSessionPersistenceWithDevices() throws {
        var session = MetaVisSession()
        let camera = CameraDevice(name: "Persisted Cam", deviceId: "cam-p-1")
        var mutableCam = camera
        mutableCam.set(parameter: "iso", value: .int(3200))
        
        session.devices.add(mutableCam)
        
        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(session)
        
        // Decode
        let decoder = JSONDecoder()
        let decodedSession = try decoder.decode(MetaVisSession.self, from: data)
        
        // Verify
        XCTAssertEqual(decodedSession.devices.devices.count, 1)
        
        guard let decodedCam = decodedSession.devices.get(id: camera.id) as? CameraDevice else {
            XCTFail("Failed to retrieve camera from decoded session")
            return
        }
        
        XCTAssertEqual(decodedCam.name, "Persisted Cam")
        XCTAssertEqual(decodedCam.parameters["iso"]?.asInt, 3200)
    }
    
    func testPerformanceSessionWithManyDevices() {
        var session = MetaVisSession()
        let count = 1000
        
        for i in 0..<count {
            session.devices.add(CameraDevice(name: "Cam \(i)", deviceId: "id-\(i)"))
        }
        
        measure {
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(session)
                let decoder = JSONDecoder()
                let _ = try decoder.decode(MetaVisSession.self, from: data)
            } catch {
                XCTFail("Performance test failed: \(error)")
            }
        }
    }
}
