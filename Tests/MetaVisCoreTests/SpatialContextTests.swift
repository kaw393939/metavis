import XCTest
@testable import MetaVisCore

final class SpatialContextTests: XCTestCase {
    
    func testDefaults() {
        let context = SpatialContext()
        XCTAssertEqual(context.location, .sanFrancisco)
        XCTAssertEqual(context.environment.name, "Studio Clean")
    }
    
    func testCodable() throws {
        let original = SpatialContext(
            environment: .outdoorSunny,
            location: LocationData.tokyo,
            timeOfDay: Date(timeIntervalSince1970: 1000)
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SpatialContext.self, from: data)
        
        XCTAssertEqual(decoded.location, LocationData.tokyo)
        XCTAssertEqual(decoded.environment.name, "Outdoor Sunny")
        // Date comparison might have tiny precision diffs, so check nearly equal
        XCTAssertEqual(decoded.timeOfDay.timeIntervalSince1970, 1000, accuracy: 0.001)
    }
}
