import XCTest
@testable import MetaVisCore

final class UnknownDeviceTests: XCTestCase {
    
    func testInitialization() {
        let id = UUID()
        let device = UnknownDevice(id: id, name: "Mystery Box", type: .unknown)
        
        XCTAssertEqual(device.id, id)
        XCTAssertEqual(device.name, "Mystery Box")
        XCTAssertEqual(device.type, .unknown)
        XCTAssertEqual(device.state, .offline)
    }
    
    func testParameterStorage() {
        var device = UnknownDevice(name: "Test")
        device.set(parameter: "foo", value: .int(42))
        
        XCTAssertEqual(device.parameters["foo"]?.asInt, 42)
    }
    
    func testExecutionNoOp() async throws {
        let device = UnknownDevice(name: "Test")
        // Should not throw
        try await device.execute(action: "explode")
    }
    
    func testCodable() throws {
        var device = UnknownDevice(name: "Persisted Unknown")
        device.set(parameter: "version", value: .string("v99"))
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(device)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(UnknownDevice.self, from: data)
        
        XCTAssertEqual(decoded.name, "Persisted Unknown")
        XCTAssertEqual(decoded.parameters["version"]?.asString, "v99")
    }
}
