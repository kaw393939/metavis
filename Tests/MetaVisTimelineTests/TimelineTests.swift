import XCTest
import MetaVisCore
@testable import MetaVisTimeline

final class TimelineTests: XCTestCase {
    
    func testClipCalculations() {
        let start = Time(seconds: 1.0)
        let duration = Time(seconds: 2.5)
        
        let clip = Clip(
            name: "Test Clip",
            asset: AssetReference(sourceFn: "file://test.mov"),
            startTime: start,
            duration: duration
        )
        
        // 1.0 + 2.5 = 3.5
        XCTAssertEqual(clip.endTime.seconds, 3.5)
    }
    
    func testSerialization() throws {
        let clip = Clip(
            name: "Clip 1",
            asset: AssetReference(sourceFn: "ligm://pattern"),
            startTime: .zero,
            duration: Time(seconds: 5),
            effects: [
                FeatureApplication(id: "com.metavis.fx.blur.gaussian", parameters: ["radius": .float(8.0)])
            ]
        )
        
        let track = Track(name: "Video 1", kind: .video, clips: [clip])
        let timeline = Timeline(tracks: [track])
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(timeline)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Timeline.self, from: data)
        
        XCTAssertEqual(decoded.tracks.count, 1)
        XCTAssertEqual(decoded.tracks[0].clips[0].name, "Clip 1")
                XCTAssertEqual(decoded.tracks[0].kind, .video)
                XCTAssertEqual(decoded.tracks[0].clips[0].effects.count, 1)
    }

        func testDecodingMissingClipEffectsDefaultsToEmpty() throws {
                // Simulate older persisted JSON that predates `Clip.effects`.
                let json = """
                {
                    "id": "00000000-0000-0000-0000-000000000000",
                    "name": "Clip 1",
                    "asset": { "id": "22222222-2222-2222-2222-222222222222", "sourceFn": "ligm://pattern" },
                    "startTime": { "value": { "numerator": 0, "denominator": 1 } },
                    "duration": { "value": { "numerator": 5, "denominator": 1 } },
                    "offset": { "value": { "numerator": 0, "denominator": 1 } }
                }
                """

                let data = try XCTUnwrap(json.data(using: .utf8))
                let decoded = try JSONDecoder().decode(Clip.self, from: data)
                XCTAssertEqual(decoded.effects, [])
        }

        func testDecodingMissingTrackKindDefaultsToVideo() throws {
                // Simulate older persisted JSON that predates `Track.kind`.
                let json = """
                {
                    "id": "00000000-0000-0000-0000-000000000000",
                    "tracks": [
                        {
                            "id": "11111111-1111-1111-1111-111111111111",
                            "name": "V1",
                            "clips": []
                        }
                    ],
                    "duration": { "value": { "numerator": 0, "denominator": 1 } }
                }
                """

                let data = try XCTUnwrap(json.data(using: .utf8))
                let decoded = try JSONDecoder().decode(Timeline.self, from: data)
                XCTAssertEqual(decoded.tracks.count, 1)
                XCTAssertEqual(decoded.tracks[0].kind, .video)
        }
}
