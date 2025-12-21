import Foundation
import XCTest

@testable import MetaVisLab
import MetaVisCore
import MetaVisPerception

final class FeedbackLoopOrchestratorE2ETests: XCTestCase {

    func test_autoColorCorrectCommand_usesFeedbackLoop_QAOff_isDeterministic() async throws {
        let fm = FileManager.default
        let baseOut = URL(fileURLWithPath: fm.currentDirectoryPath)
            .appendingPathComponent("test_outputs/_e2e_feedbackloop_autocolor")

        let out1 = baseOut.appendingPathComponent("run1")
        let out2 = baseOut.appendingPathComponent("run2")

        try? fm.removeItem(at: baseOut)
        try fm.createDirectory(at: out1, withIntermediateDirectories: true)
        try fm.createDirectory(at: out2, withIntermediateDirectories: true)

        let sensorsURL1 = out1.appendingPathComponent("sensors.json")
        let sensorsURL2 = out2.appendingPathComponent("sensors.json")

        let url = URL(fileURLWithPath: "Tests/Assets/VideoEdit/keith_talk.mov")
        let sensors = try await MasterSensorIngestor().ingest(url: url)
        try JSONWriting.write(sensors, to: sensorsURL1)
        try JSONWriting.write(sensors, to: sensorsURL2)

        let opts1 = AutoColorCorrectCommand.Options(
            sensorsURL: sensorsURL1,
            outputDirURL: out1,
            inputMovieURL: nil,
            seed: "seed",
            budgets: EvidencePack.Budgets(maxFrames: 6, maxVideoClips: 0, videoClipSeconds: 0.0, maxAudioClips: 0, audioClipSeconds: 0.0),
            qaMode: .off,
            qaCycles: 2,
            qaMaxConcurrency: 2
        )
        let opts2 = AutoColorCorrectCommand.Options(
            sensorsURL: sensorsURL2,
            outputDirURL: out2,
            inputMovieURL: nil,
            seed: "seed",
            budgets: EvidencePack.Budgets(maxFrames: 6, maxVideoClips: 0, videoClipSeconds: 0.0, maxAudioClips: 0, audioClipSeconds: 0.0),
            qaMode: .off,
            qaCycles: 2,
            qaMaxConcurrency: 2
        )

        try await AutoColorCorrectCommand.run(options: opts1)
        try await AutoColorCorrectCommand.run(options: opts2)

        let p1 = try Data(contentsOf: out1.appendingPathComponent("color_grade_proposal.json"))
        let p2 = try Data(contentsOf: out2.appendingPathComponent("color_grade_proposal.json"))
        XCTAssertEqual(p1, p2)

        let e1 = try Data(contentsOf: out1.appendingPathComponent("evidence_pack.json"))
        let e2 = try Data(contentsOf: out2.appendingPathComponent("evidence_pack.json"))
        XCTAssertEqual(e1, e2)

        let a1 = try Data(contentsOf: out1.appendingPathComponent("acceptance_report.json"))
        let a2 = try Data(contentsOf: out2.appendingPathComponent("acceptance_report.json"))
        XCTAssertEqual(a1, a2)
    }

    func test_autoSpeakerAudioCommand_usesFeedbackLoop_localText_runsWithoutMediaExtraction() async throws {
        let fm = FileManager.default
        let baseOut = URL(fileURLWithPath: fm.currentDirectoryPath)
            .appendingPathComponent("test_outputs/_e2e_feedbackloop_autospeaker")
            .appendingPathComponent(UUID().uuidString)

        let out1 = baseOut.appendingPathComponent("run1")
        let out2 = baseOut.appendingPathComponent("run2")

        try fm.createDirectory(at: out1, withIntermediateDirectories: true)
        try fm.createDirectory(at: out2, withIntermediateDirectories: true)

        let sensorsURL1 = out1.appendingPathComponent("sensors.json")
        let sensorsURL2 = out2.appendingPathComponent("sensors.json")
        let url = URL(fileURLWithPath: "Tests/Assets/VideoEdit/keith_talk.mov")
        let sensors = try await MasterSensorIngestor().ingest(url: url)
        try JSONWriting.write(sensors, to: sensorsURL1)
        try JSONWriting.write(sensors, to: sensorsURL2)

        func runOnce(out: URL, sensorsURL: URL) async throws {
            let opts = AutoSpeakerAudioCommand.Options(
                sensorsURL: sensorsURL,
                outputDirURL: out,
                inputMovieURL: nil,
                seed: "seed",
                budgets: EvidencePack.Budgets(maxFrames: 0, maxVideoClips: 0, videoClipSeconds: 0.0, maxAudioClips: 2, audioClipSeconds: 2.0),
                qaMode: .off,
                qaCycles: 2,
                qaMaxConcurrency: 2
            )
            try await AutoSpeakerAudioCommand.run(options: opts)
        }

        try await runOnce(out: out1, sensorsURL: sensorsURL1)
        try await runOnce(out: out2, sensorsURL: sensorsURL2)

        let p1 = try Data(contentsOf: out1.appendingPathComponent("audio_proposal.json"))
        let p2 = try Data(contentsOf: out2.appendingPathComponent("audio_proposal.json"))
        XCTAssertEqual(p1, p2)

        let e1 = try Data(contentsOf: out1.appendingPathComponent("evidence_pack.json"))
        let e2 = try Data(contentsOf: out2.appendingPathComponent("evidence_pack.json"))
        XCTAssertEqual(e1, e2)

        let a1 = try Data(contentsOf: out1.appendingPathComponent("acceptance_report.json"))
        let a2 = try Data(contentsOf: out2.appendingPathComponent("acceptance_report.json"))
        XCTAssertEqual(a1, a2)

        let proposal = try JSONDecoder().decode(AutoSpeakerAudioProposalV1.AudioProposal.self, from: p1)
        XCTAssertFalse(proposal.proposalId.isEmpty)

        if let first = proposal.chain.first {
            XCTAssertEqual(first.effectId, "audio.dialogCleanwater.v1")
            let gain = first.params?["globalGainDB"]
            XCTAssertNotNil(gain)
            if let gain {
                XCTAssertGreaterThanOrEqual(gain, -6.0)
                XCTAssertLessThanOrEqual(gain, 6.0)
            }
        }
    }
}
