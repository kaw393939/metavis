import XCTest
@testable import MetaVisCore

final class CameraDeviceTests: XCTestCase {
    
    func testWebcamInitialization() {
        let webcam = CameraDevice(name: "MacBook Air Webcam", deviceId: "built-in-webcam")
        
        XCTAssertEqual(webcam.name, "MacBook Air Webcam")
        XCTAssertEqual(webcam.type, .camera)
        XCTAssertEqual(webcam.state, .offline)
        
        // Check default parameters
        XCTAssertEqual(webcam.parameters["iso"], .int(400))
        XCTAssertEqual(webcam.parameters["shutter_angle"], .float(180.0))
    }
    
    func testiPhoneCameraInitialization() {
        let iphone = CameraDevice(name: "iPhone 15 Pro", deviceId: "iphone-15-pro-max")
        
        XCTAssertEqual(iphone.name, "iPhone 15 Pro")
        XCTAssertEqual(iphone.type, .camera)
        
        // iPhone might have different defaults or capabilities
        XCTAssertEqual(iphone.parameters["lens"], .string("24mm"))
    }
    
    func testParameterUpdates() {
        var camera = CameraDevice(name: "Test Cam", deviceId: "test-id")
        
        // Change ISO
        camera.set(parameter: "iso", value: .int(800))
        XCTAssertEqual(camera.parameters["iso"]?.asInt, 800)
        
        // Change Shutter
        camera.set(parameter: "shutter_angle", value: .float(90.0))
        XCTAssertEqual(camera.parameters["shutter_angle"]?.asFloat, 90.0)
    }
    
    func testRecordAction() async throws {
        let camera = CameraDevice(name: "Action Cam", deviceId: "action-id")
        
        // This should not throw
        try await camera.execute(action: "start_recording")
        try await camera.execute(action: "stop_recording")
    }
}
