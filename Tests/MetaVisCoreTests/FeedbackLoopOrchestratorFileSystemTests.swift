import XCTest
import MetaVisCore

final class FeedbackLoopOrchestratorFileSystemTests: XCTestCase {
    private struct DummyProposal: Codable, Sendable, Equatable {
        var value: Int
    }

    func testRunUsesProvidedFileSystemAdapter() async throws {
        let fs = InMemoryFileSystemAdapter()
        let out = URL(fileURLWithPath: "/virtual/out")

        let budgets = EvidencePack.Budgets(maxFrames: 0, maxVideoClips: 0, videoClipSeconds: 0, maxAudioClips: 0, audioClipSeconds: 0)
        let budgetsUsed = EvidencePack.BudgetsUsed(frames: 0, videoClips: 0, audioClips: 0, totalAudioSeconds: 0, totalVideoSeconds: 0)

        let options = FeedbackLoopOrchestrator.Options(
            outputDirURL: out,
            inputMovieURL: nil,
            seed: "seed",
            qaEnabled: false,
            qaCycles: 0,
            qaMaxConcurrency: 1
        )

        let hooks = FeedbackLoopOrchestrator.Hooks<DummyProposal>(
            proposalFileName: "proposal.json",
            qaOffAcceptance: AcceptanceReport(accepted: true, qualityAccepted: true, qaPerformed: false, summary: "qa disabled"),
            makeInitialProposal: { DummyProposal(value: 1) },
            buildEvidence: { cycleIndex, _ in
                EvidencePack(
                    manifest: EvidencePack.Manifest(
                        cycleIndex: cycleIndex,
                        seed: "seed",
                        policyVersion: "test",
                        budgetsConfigured: budgets,
                        budgetsUsed: budgetsUsed,
                        timestampsSelected: [],
                        selectionNotes: []
                    ),
                    assets: EvidencePack.Assets(),
                    textSummary: ""
                )
            },
            extractEvidenceAssets: nil,
            runQA: { _, _ in
                FeedbackLoopOrchestrator.QARunResult(
                    report: AcceptanceReport(accepted: true, qualityAccepted: true, qaPerformed: true, summary: "ok")
                )
            },
            applySuggestedEdits: { _, proposal in proposal }
        )

        _ = try await FeedbackLoopOrchestrator.run(options: options, hooks: hooks, fileSystem: fs)

        let proposalURL = out.appendingPathComponent("proposal.json")
        let acceptanceURL = out.appendingPathComponent("acceptance_report.json")

        let hasProposal = fs.containsFile(proposalURL)
        let hasAcceptance = fs.containsFile(acceptanceURL)
        XCTAssertTrue(hasProposal)
        XCTAssertTrue(hasAcceptance)
    }
}
