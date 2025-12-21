import XCTest
import MetaVisCore
@testable import MetaVisPerception

final class SpeakerDiarizerContractTests: XCTestCase {

    func test_assigns_single_face_track_as_speaker() {
        let faceId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let sensors = makeSensors(
            videoSamples: [
                .init(
                    time: 1.0,
                    meanLuma: 0,
                    skinLikelihood: 0,
                    dominantColors: [],
                    faces: [
                        .init(trackId: faceId, rect: CGRect(x: 0.4, y: 0.2, width: 0.2, height: 0.2), personId: "P0")
                    ],
                    personMaskPresence: nil,
                    peopleCountEstimate: 1
                ),
                .init(
                    time: 1.25,
                    meanLuma: 0,
                    skinLikelihood: 0,
                    dominantColors: [],
                    faces: [
                        .init(trackId: faceId, rect: CGRect(x: 0.4, y: 0.2, width: 0.2, height: 0.2), personId: "P0")
                    ],
                    personMaskPresence: nil,
                    peopleCountEstimate: 1
                )
            ],
            audioSegments: [
                .init(start: 0.0, end: 10.0, kind: .speechLike, confidence: 0.9)
            ]
        )

        let words: [TranscriptWordV1] = [
            makeWord(id: "w1", text: "hello", startTicks: 60000, endTicks: 65000),
            makeWord(id: "w2", text: "world", startTicks: 65000, endTicks: 70000)
        ]

        let res = SpeakerDiarizer.diarize(words: words, sensors: sensors)
        XCTAssertEqual(res.words.count, 2)
        XCTAssertEqual(res.words[0].speakerId, faceId.uuidString)
        XCTAssertEqual(res.words[1].speakerId, faceId.uuidString)
        XCTAssertEqual(res.words[0].speakerLabel, "T1")
        XCTAssertEqual(res.words[1].speakerLabel, "T1")
        XCTAssertEqual(res.speakerMap.speakers.first?.speakerLabel, "T1")
    }

    func test_stickiness_prevents_oscillation_when_two_faces_present() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!

        // Alternate slight dominance; hysteresis should keep speaker stable.
        let s0 = MasterSensors.VideoSample(
            time: 1.0,
            meanLuma: 0,
            skinLikelihood: 0,
            dominantColors: [],
            faces: [
                .init(trackId: a, rect: CGRect(x: 0.45, y: 0.2, width: 0.20, height: 0.20), personId: "P0"),
                .init(trackId: b, rect: CGRect(x: 0.10, y: 0.2, width: 0.19, height: 0.19), personId: "P1")
            ],
            personMaskPresence: nil,
            peopleCountEstimate: 2
        )
        let s1 = MasterSensors.VideoSample(
            time: 1.25,
            meanLuma: 0,
            skinLikelihood: 0,
            dominantColors: [],
            faces: [
                .init(trackId: a, rect: CGRect(x: 0.45, y: 0.2, width: 0.195, height: 0.195), personId: "P0"),
                .init(trackId: b, rect: CGRect(x: 0.10, y: 0.2, width: 0.20, height: 0.20), personId: "P1")
            ],
            personMaskPresence: nil,
            peopleCountEstimate: 2
        )

        let sensors = makeSensors(
            videoStrideSeconds: 0.25,
            videoSamples: [s0, s1],
            audioSegments: [
                .init(start: 0.0, end: 10.0, kind: .speechLike, confidence: 0.9)
            ]
        )

        let words: [TranscriptWordV1] = (0..<10).map { idx in
            let start = Int64(60000 + (idx * 15000))
            return makeWord(id: "w\(idx)", text: "w", startTicks: start, endTicks: start + 5000)
        }

        let res = SpeakerDiarizer.diarize(words: words, sensors: sensors)
        let speakerIds = res.words.compactMap { $0.speakerId }
        XCTAssertEqual(speakerIds.count, 10)

        let switches = zip(speakerIds, speakerIds.dropFirst()).filter { $0 != $1 }.count
        XCTAssertLessThanOrEqual(switches, 2, "Should not rapidly flip speakers. switches=\(switches)")
    }

    func test_offscreen_words_are_labeled_offscreen() {
        let sensors = makeSensors(
            videoSamples: [
                .init(time: 1.0, meanLuma: 0, skinLikelihood: 0, dominantColors: [], faces: [], personMaskPresence: nil, peopleCountEstimate: 0)
            ],
            audioSegments: [
                .init(start: 0.0, end: 10.0, kind: .speechLike, confidence: 0.9)
            ]
        )

        let words: [TranscriptWordV1] = [
            makeWord(id: "w1", text: "hi", startTicks: 60000, endTicks: 65000)
        ]

        let res = SpeakerDiarizer.diarize(words: words, sensors: sensors)
        XCTAssertEqual(res.words.first?.speakerId, "OFFSCREEN")
        XCTAssertEqual(res.words.first?.speakerLabel, "OFFSCREEN")
    }

    func test_words_outside_speechLike_are_left_unassigned() {
        let faceId = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        let sensors = makeSensors(
            videoSamples: [
                .init(
                    time: 1.0,
                    meanLuma: 0,
                    skinLikelihood: 0,
                    dominantColors: [],
                    faces: [
                        .init(trackId: faceId, rect: CGRect(x: 0.4, y: 0.2, width: 0.2, height: 0.2), personId: "P0")
                    ],
                    personMaskPresence: nil,
                    peopleCountEstimate: 1
                )
            ],
            audioSegments: [
                .init(start: 0.0, end: 0.5, kind: .silence, confidence: 0.9),
                .init(start: 0.5, end: 0.9, kind: .unknown, confidence: 0.9)
            ]
        )

        let words: [TranscriptWordV1] = [
            makeWord(id: "w1", text: "nope", startTicks: 60000, endTicks: 65000)
        ]

        let res = SpeakerDiarizer.diarize(words: words, sensors: sensors)
        XCTAssertNil(res.words.first?.speakerId)
        XCTAssertNil(res.words.first?.speakerLabel)
    }

    // MARK: - Helpers

    private func makeWord(id: String, text: String, startTicks: Int64, endTicks: Int64) -> TranscriptWordV1 {
        TranscriptWordV1(
            schema: "transcript.word.v1",
            wordId: id,
            word: text,
            confidence: 1.0,
            sourceTimeTicks: startTicks,
            sourceTimeEndTicks: endTicks,
            speakerId: nil,
            speakerLabel: nil,
            timelineTimeTicks: startTicks,
            timelineTimeEndTicks: endTicks,
            clipId: nil,
            segmentId: nil
        )
    }

    private func makeSensors(
        videoStrideSeconds: Double = 0.25,
        videoSamples: [MasterSensors.VideoSample],
        audioSegments: [MasterSensors.AudioSegment]
    ) -> MasterSensors {
        MasterSensors(
            schemaVersion: 4,
            source: .init(path: "synthetic.mov", durationSeconds: 10.0, width: 1920, height: 1080, nominalFPS: 30),
            sampling: .init(videoStrideSeconds: videoStrideSeconds, maxVideoSeconds: 10.0, audioAnalyzeSeconds: 10.0),
            videoSamples: videoSamples,
            audioSegments: audioSegments,
            audioFrames: nil,
            audioBeats: nil,
            warnings: [],
            descriptors: nil,
            suggestedStart: nil,
            summary: .init(
                analyzedSeconds: 10.0,
                scene: .init(indoorOutdoor: .init(label: .unknown, confidence: 0.0), lightSource: .init(label: .unknown, confidence: 0.0)),
                audio: .init(approxRMSdBFS: -20, approxPeakDB: -3)
            )
        )
    }
}
