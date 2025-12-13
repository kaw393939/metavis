import XCTest
@testable import MetaVisServices

final class LocalLLMTests: XCTestCase {
    
    func testServiceMock() async throws {
        let service = LocalLLMService()
        let request = LLMRequest(userQuery: "make it blue", context: "{}")
        
        // The mock is hardcoded to respond to "blue" with an intent
        let response = try await service.generate(request: request)
        
        XCTAssertTrue(response.text.count > 0)
        XCTAssertNotNil(response.intentJSON)
        XCTAssertTrue(response.intentJSON?.contains("color_grade") ?? false)
    }
    
    func testIntentParser() {
        let parser = IntentParser()
        
        let validJSON = """
        Okay, I will change the shirt.
        ```json
        {
            "action": "color_grade",
            "target": "shirt",
            "params": { "hue": 0.5 }
        }
        ```
        """
        
        let intent = parser.parse(response: validJSON)
        XCTAssertNotNil(intent)
        XCTAssertEqual(intent?.action, .colorGrade)
        XCTAssertEqual(intent?.target, "shirt")
        XCTAssertEqual(intent?.params["hue"], 0.5)
    }
    
    func testIntentParserRaw() {
        let parser = IntentParser()
        let rawJSON = """
        { "action": "cut", "target": "clip", "params": {} }
        """
        
        let intent = parser.parse(response: rawJSON)
        XCTAssertEqual(intent?.action, .cut)
    }
}
