import Foundation

/// A small, deterministic feedback-loop runner that orchestrates:
/// - proposal generation
/// - evidence selection (budgeted)
/// - optional evidence asset extraction
/// - optional QA evaluation
/// - optional escalation (targeted evidence only)
/// - bounded edit application
/// - audit artifact writing
public enum FeedbackLoopOrchestrator {

    public struct Options: Sendable {
        public var outputDirURL: URL
        public var inputMovieURL: URL?
        public var seed: String
        public var qaEnabled: Bool
        public var qaCycles: Int
        public var qaMaxConcurrency: Int

        public init(
            outputDirURL: URL,
            inputMovieURL: URL?,
            seed: String,
            qaEnabled: Bool,
            qaCycles: Int,
            qaMaxConcurrency: Int
        ) {
            self.outputDirURL = outputDirURL
            self.inputMovieURL = inputMovieURL
            self.seed = seed
            self.qaEnabled = qaEnabled
            self.qaCycles = qaCycles
            self.qaMaxConcurrency = qaMaxConcurrency
        }
    }

    public struct QARunResult: Sendable {
        public var report: AcceptanceReport
        public var prompt: String?
        public var rawResponse: String?

        public init(report: AcceptanceReport, prompt: String? = nil, rawResponse: String? = nil) {
            self.report = report
            self.prompt = prompt
            self.rawResponse = rawResponse
        }
    }

    public struct Result<Proposal: Sendable & Codable>: Sendable {
        public var proposal: Proposal
        public var finalEvidence: EvidencePack?
        public var finalAcceptance: AcceptanceReport

        public init(proposal: Proposal, finalEvidence: EvidencePack?, finalAcceptance: AcceptanceReport) {
            self.proposal = proposal
            self.finalEvidence = finalEvidence
            self.finalAcceptance = finalAcceptance
        }
    }

    public struct Hooks<Proposal: Sendable & Codable>: Sendable {
        public var proposalFileName: String
        public var qaOffAcceptance: AcceptanceReport

        /// Deterministic initial proposal.
        public var makeInitialProposal: @Sendable () -> Proposal

        /// Deterministic evidence selection.
        public var buildEvidence: @Sendable (_ cycleIndex: Int, _ escalation: AcceptanceReport.RequestedEvidenceEscalation?) -> EvidencePack

        /// Optional extraction of evidence assets (frames/audio/video). If nil, no extraction occurs.
        public var extractEvidenceAssets: (@Sendable (_ evidence: EvidencePack, _ inputMovieURL: URL, _ outputRootURL: URL, _ maxConcurrency: Int) async throws -> Void)?

        /// QA evaluation (called only when qaEnabled=true).
        public var runQA: @Sendable (_ proposal: Proposal, _ evidence: EvidencePack) async throws -> QARunResult

        /// Apply bounded edits to produce the next-cycle proposal.
        public var applySuggestedEdits: @Sendable (_ edits: [AcceptanceReport.SuggestedEdit], _ proposal: Proposal) -> Proposal

        public init(
            proposalFileName: String,
            qaOffAcceptance: AcceptanceReport,
            makeInitialProposal: @escaping @Sendable () -> Proposal,
            buildEvidence: @escaping @Sendable (_ cycleIndex: Int, _ escalation: AcceptanceReport.RequestedEvidenceEscalation?) -> EvidencePack,
            extractEvidenceAssets: (@Sendable (_ evidence: EvidencePack, _ inputMovieURL: URL, _ outputRootURL: URL, _ maxConcurrency: Int) async throws -> Void)?,
            runQA: @escaping @Sendable (_ proposal: Proposal, _ evidence: EvidencePack) async throws -> QARunResult,
            applySuggestedEdits: @escaping @Sendable (_ edits: [AcceptanceReport.SuggestedEdit], _ proposal: Proposal) -> Proposal
        ) {
            self.proposalFileName = proposalFileName
            self.qaOffAcceptance = qaOffAcceptance
            self.makeInitialProposal = makeInitialProposal
            self.buildEvidence = buildEvidence
            self.extractEvidenceAssets = extractEvidenceAssets
            self.runQA = runQA
            self.applySuggestedEdits = applySuggestedEdits
        }
    }

    public static func run<Proposal: Sendable & Codable>(
        options: Options,
        hooks: Hooks<Proposal>,
        fileSystem: any FileSystemAdapter = DiskFileSystemAdapter()
    ) async throws -> Result<Proposal> {
        try fileSystem.createDirectory(at: options.outputDirURL, withIntermediateDirectories: true)

        let cycles = options.qaEnabled ? max(0, options.qaCycles) : 0
        let totalCycles = max(1, options.qaEnabled ? max(1, cycles) : 1)

        var currentProposal = hooks.makeInitialProposal()
        var finalEvidence: EvidencePack?
        var finalAcceptance: AcceptanceReport = hooks.qaOffAcceptance

        for cycleIndex in 0..<totalCycles {
            let cycleDir = options.outputDirURL.appendingPathComponent("cycle_\(cycleIndex)", isDirectory: true)
            try fileSystem.createDirectory(at: cycleDir, withIntermediateDirectories: true)

            var evidence = hooks.buildEvidence(cycleIndex, nil)

            if let inputMovieURL = options.inputMovieURL, let extractor = hooks.extractEvidenceAssets {
                try await extractor(evidence, inputMovieURL, options.outputDirURL, options.qaMaxConcurrency)
            }

            try fileSystem.write(JSONWriting.encode(currentProposal), to: cycleDir.appendingPathComponent(hooks.proposalFileName))
            try fileSystem.write(JSONWriting.encode(evidence), to: cycleDir.appendingPathComponent("evidence_pack.json"))

            var acceptance: AcceptanceReport
            if options.qaEnabled {
                let qa1 = try await hooks.runQA(currentProposal, evidence)
                acceptance = qa1.report

                if let prompt = qa1.prompt {
                    if let data = prompt.data(using: .utf8) {
                        try fileSystem.write(data, to: cycleDir.appendingPathComponent("qa_prompt.txt"))
                    }
                }
                if let raw = qa1.rawResponse {
                    if let data = raw.data(using: .utf8) {
                        try fileSystem.write(data, to: cycleDir.appendingPathComponent("qa_response_raw.txt"))
                    }
                }
            } else {
                acceptance = hooks.qaOffAcceptance
            }

            try fileSystem.write(JSONWriting.encode(acceptance), to: cycleDir.appendingPathComponent("acceptance_report.json"))

            // Escalation ladder: budgeted + targeted evidence only. If QA requests escalation, rebuild evidence and re-run QA once.
            if options.qaEnabled,
               !acceptance.accepted,
               let esc = acceptance.requestedEvidenceEscalation,
               (esc.extendOneAudioClipToSeconds != nil || (esc.addFramesAtSeconds?.isEmpty == false)) {
                let escDir = cycleDir.appendingPathComponent("escalation_0", isDirectory: true)
                try fileSystem.createDirectory(at: escDir, withIntermediateDirectories: true)

                let escalated = hooks.buildEvidence(cycleIndex, esc)

                if let inputMovieURL = options.inputMovieURL, let extractor = hooks.extractEvidenceAssets {
                    try await extractor(escalated, inputMovieURL, options.outputDirURL, options.qaMaxConcurrency)
                }

                try fileSystem.write(JSONWriting.encode(escalated), to: escDir.appendingPathComponent("evidence_pack.json"))

                let qa2 = try await hooks.runQA(currentProposal, escalated)
                if let prompt = qa2.prompt {
                    if let data = prompt.data(using: .utf8) {
                        try fileSystem.write(data, to: escDir.appendingPathComponent("qa_prompt.txt"))
                    }
                }
                if let raw = qa2.rawResponse {
                    if let data = raw.data(using: .utf8) {
                        try fileSystem.write(data, to: escDir.appendingPathComponent("qa_response_raw.txt"))
                    }
                }
                let acceptance2 = qa2.report
                try fileSystem.write(JSONWriting.encode(acceptance2), to: escDir.appendingPathComponent("acceptance_report.json"))

                // Promote post-escalation artifacts.
                evidence = escalated
                acceptance = acceptance2
                try fileSystem.write(JSONWriting.encode(acceptance2), to: cycleDir.appendingPathComponent("acceptance_report.json"))
            }

            finalEvidence = evidence
            finalAcceptance = acceptance

            if !options.qaEnabled { break }
            if acceptance.accepted { break }
            if cycleIndex >= totalCycles - 1 { break }

            currentProposal = hooks.applySuggestedEdits(acceptance.suggestedEdits, currentProposal)
        }

        // Write final canonical artifacts at the root for easy consumption.
        try fileSystem.write(JSONWriting.encode(currentProposal), to: options.outputDirURL.appendingPathComponent(hooks.proposalFileName))
        if let finalEvidence {
            try fileSystem.write(JSONWriting.encode(finalEvidence), to: options.outputDirURL.appendingPathComponent("evidence_pack.json"))
        }
        try fileSystem.write(JSONWriting.encode(finalAcceptance), to: options.outputDirURL.appendingPathComponent("acceptance_report.json"))

        return Result(proposal: currentProposal, finalEvidence: finalEvidence, finalAcceptance: finalAcceptance)
    }
}
