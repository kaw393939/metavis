import XCTest
@testable import MetaVisCore

final class SpatialContextTests: XCTestCase {
    
    func testInitialization() {
        let coord = GeoCoordinate(latitude: 37.3346, longitude: -122.0090)
        let place = PlaceInfo(name: "Apple Park", city: "Cupertino")
        let env = EnvironmentalConditions(weather: "Sunny", temperature: 25.0)
        
        let context = SpatialContext(
            coordinate: coord,
            altitude: 100.0,
            heading: 180.0,
            place: place,
            sceneType: .outdoor,
            environment: env
        )
        
        XCTAssertEqual(context.coordinate?.latitude, 37.3346)
        XCTAssertEqual(context.place?.name, "Apple Park")
        XCTAssertEqual(context.sceneType, .outdoor)
        XCTAssertEqual(context.environment?.weather, "Sunny")
    }
    
    func testCodable() throws {
        let coord = GeoCoordinate(latitude: 48.8584, longitude: 2.2945)
        let context = SpatialContext(coordinate: coord, sceneType: .urban)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(context)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SpatialContext.self, from: data)
        
        XCTAssertEqual(decoded.coordinate?.latitude, 48.8584)
        XCTAssertEqual(decoded.sceneType, .urban)
    }
    
    func testEquality() {
        let c1 = SpatialContext(sceneType: .indoor)
        let c2 = SpatialContext(sceneType: .indoor)
        let c3 = SpatialContext(sceneType: .outdoor)
        
        XCTAssertEqual(c1, c2)
        XCTAssertNotEqual(c1, c3)
    }
}
