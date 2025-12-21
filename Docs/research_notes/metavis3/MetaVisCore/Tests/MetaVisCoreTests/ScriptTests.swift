import XCTest
@testable import MetaVisCore

final class ScriptTests: XCTestCase {
    
    func testScriptInitialization() {
        let script = Script(language: "en", source: .manual)
        XCTAssertEqual(script.language, "en")
        XCTAssertEqual(script.source, .manual)
        XCTAssertTrue(script.lines.isEmpty)
    }
    
    func testDialogueLine() {
        let start = RationalTime(value: 0, timescale: 24)
        let duration = RationalTime(value: 24, timescale: 24)
        let word = ScriptWord(text: "Hello", startTime: start, duration: duration, confidence: 0.9)
        
        let line = DialogueLine(
            text: "Hello World",
            startTime: start,
            duration: duration,
            rawSpeakerLabel: "SPEAKER_01",
            words: [word]
        )
        
        XCTAssertEqual(line.text, "Hello World")
        XCTAssertEqual(line.endTime, start + duration)
        XCTAssertEqual(line.words.count, 1)
        XCTAssertEqual(line.rawSpeakerLabel, "SPEAKER_01")
    }
    
    func testScriptCodable() {
        var script = Script()
        let line = DialogueLine(
            text: "Test",
            startTime: .zero,
            duration: RationalTime(value: 1, timescale: 1)
        )
        script.lines.append(line)
        
        do {
            let data = try JSONEncoder().encode(script)
            let decoded = try JSONDecoder().decode(Script.self, from: data)
            XCTAssertEqual(decoded.id, script.id)
            XCTAssertEqual(decoded.lines.count, 1)
            XCTAssertEqual(decoded.lines.first?.text, "Test")
        } catch {
            XCTFail("Codable failed: \(error)")
        }
    }
}
