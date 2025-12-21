import Foundation
import MetaVisCore
import MetaVisPerception

enum AutoColorCorrectCommand {

    enum QAMode: String, Sendable {
        case off = "off"
        case localText = "local-text"
        case gemini = "gemini"
    }

    struct Options: Sendable {
        var sensorsURL: URL
        var outputDirURL: URL
        var inputMovieURL: URL?
        var seed: String
        var budgets: EvidencePack.Budgets
        var qaMode: QAMode
        var qaCycles: Int
        var qaMaxConcurrency: Int

        init(
            sensorsURL: URL,
            outputDirURL: URL,
            inputMovieURL: URL?,
            seed: String,
            budgets: EvidencePack.Budgets,
            qaMode: QAMode,
            qaCycles: Int,
            qaMaxConcurrency: Int
        ) {
            self.sensorsURL = sensorsURL
            self.outputDirURL = outputDirURL
            self.inputMovieURL = inputMovieURL
            self.seed = seed
            self.budgets = budgets
            self.qaMode = qaMode
            self.qaCycles = qaCycles
            self.qaMaxConcurrency = qaMaxConcurrency
        }
    }

    static func run(args: [String]) async throws {
        if args.first == "--help" || args.first == "-h" {
            print(help)
            return
        }
        let options = try parse(args: args)
        try await run(options: options)
    }

    static func run(options: Options) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: options.outputDirURL, withIntermediateDirectories: true)

        let data = try Data(contentsOf: options.sensorsURL)
        let sensors = try JSONDecoder().decode(MasterSensors.self, from: data)

        let qaEnabled = options.qaMode != .off
        if options.qaMode == .gemini {
            guard ProcessInfo.processInfo.environment["RUN_GEMINI_QC"] == "1" else {
                throw NSError(
                    domain: "MetaVisLab",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Gemini network calls are gated. Re-run with RUN_GEMINI_QC=1 in the environment."]
                )
            }
        }

        let qaOff = AcceptanceReport(
            accepted: true,
            qualityAccepted: true,
            qaPerformed: false,
            summary: "QA not performed (Sprint 16 v1 deterministic propose only)"
        )

        let result = try await FeedbackLoopOrchestrator.run(
            options: .init(
                outputDirURL: options.outputDirURL,
                inputMovieURL: options.inputMovieURL,
                seed: options.seed,
                qaEnabled: qaEnabled,
                qaCycles: options.qaCycles,
                qaMaxConcurrency: options.qaMaxConcurrency
            ),
            hooks: .init(
                proposalFileName: "color_grade_proposal.json",
                qaOffAcceptance: qaOff,
                makeInitialProposal: {
                    AutoColorGradeProposalV1.propose(from: sensors, options: .init(seed: options.seed))
                },
                buildEvidence: { cycleIndex, escalation in
                    AutoColorEvidenceSelector.buildEvidencePack(
                        from: sensors,
                        options: .init(seed: options.seed, cycleIndex: cycleIndex, budgets: options.budgets, escalation: escalation)
                    )
                },
                extractEvidenceAssets: { evidence, inputMovieURL, outputRootURL, maxConcurrency in
                    try await extractEvidenceAssets(
                        evidence: evidence,
                        inputMovieURL: inputMovieURL,
                        outputRootURL: outputRootURL,
                        maxConcurrency: maxConcurrency
                    )
                },
                runQA: { proposal, evidence in
                    let qaResult = try await AutoColorCorrectQA.run(
                        mode: options.qaMode,
                        sensors: sensors,
                        proposal: proposal,
                        evidence: evidence,
                        evidenceAssetRootURL: options.outputDirURL
                    )
                    return FeedbackLoopOrchestrator.QARunResult(
                        report: qaResult.report,
                        prompt: qaResult.prompt,
                        rawResponse: qaResult.rawResponse
                    )
                },
                applySuggestedEdits: { edits, proposal in
                    applySuggestedEdits(edits, to: proposal, sensors: sensors, seed: options.seed)
                }
            )
        )

        print("✅ Wrote color_grade_proposal.json: \(options.outputDirURL.appendingPathComponent("color_grade_proposal.json").path)")
        print("✅ Wrote evidence_pack.json: \(options.outputDirURL.appendingPathComponent("evidence_pack.json").path)")
        print("✅ Wrote acceptance_report.json: \(options.outputDirURL.appendingPathComponent("acceptance_report.json").path)")

        _ = result
    }

    private static func applySuggestedEdits(
        _ edits: [AcceptanceReport.SuggestedEdit],
        to proposal: AutoColorGradeProposalV1.GradeProposal,
        sensors: MasterSensors,
        seed: String
    ) -> AutoColorGradeProposalV1.GradeProposal {
        guard !edits.isEmpty else { return proposal }

        var updated = proposal
        var params = updated.grade.params

        let editable: [(path: String, key: String)] = [
            ("grade.params.exposure", "exposure"),
            ("grade.params.contrast", "contrast"),
            ("grade.params.saturation", "saturation"),
            ("grade.params.temperature", "temperature"),
            ("grade.params.tint", "tint")
        ]

        for (path, key) in editable {
            guard let edit = edits.first(where: { $0.path == path }) else { continue }
            let current = params[key] ?? 0.0
            let applied = updated.whitelist.applyNumericEdit(path: path, current: current, proposed: edit.value)
            params[key] = applied.value
            if applied.violation == nil {
                updated.reasoning.append("qa_suggested_edit_applied: \(path)=\(applied.value)")
            } else {
                updated.reasoning.append("qa_suggested_edit_bounded: \(path)=\(applied.value) violation=\(applied.violation!)")
            }
        }

        updated.grade.params = params
        updated.proposalId = AutoColorGradeProposalV1.computeProposalId(
            sensors: sensors,
            seed: seed,
            policyVersion: AutoColorGradeProposalV1.policyVersion,
            grade: updated.grade,
            flags: updated.flags
        )

        return updated
    }

    private static func parse(args: [String]) throws -> Options {
        var sensorsPath: String?
        var outPath: String?
        var inputPath: String?
        var seed: String = "default"
        var qaMaxFrames: Int = 8
        var qaMode: QAMode = .off
        var qaCycles: Int = 2
        var qaMaxConcurrency: Int = 2

        var i = 0
        while i < args.count {
            let a = args[i]
            switch a {
            case "--sensors":
                i += 1; if i < args.count { sensorsPath = args[i] }
            case "--out":
                i += 1; if i < args.count { outPath = args[i] }
            case "--input":
                i += 1; if i < args.count { inputPath = args[i] }
            case "--seed":
                i += 1; if i < args.count { seed = args[i] }
            case "--qa-max-frames":
                i += 1; if i < args.count { qaMaxFrames = Int(args[i]) ?? qaMaxFrames }
            case "--qa":
                i += 1
                if i < args.count {
                    qaMode = QAMode(rawValue: args[i]) ?? .off
                }
            case "--qa-cycles":
                i += 1
                if i < args.count { qaCycles = Int(args[i]) ?? qaCycles }
            case "--qa-max-concurrency":
                i += 1
                if i < args.count { qaMaxConcurrency = Int(args[i]) ?? qaMaxConcurrency }
            default:
                break
            }
            i += 1
        }

        guard let sensorsPath else {
            print(help)
            throw NSError(domain: "MetaVisLab", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing required flag: --sensors <sensors.json>"])
        }
        guard let outPath else {
            print(help)
            throw NSError(domain: "MetaVisLab", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing required flag: --out <dir>"])
        }

        func absoluteFileURL(_ path: String) -> URL {
            if path.hasPrefix("/") {
                return URL(fileURLWithPath: path).standardizedFileURL
            }
            let cwd = FileManager.default.currentDirectoryPath
            return URL(fileURLWithPath: cwd).appendingPathComponent(path).standardizedFileURL
        }

        let budgets = EvidencePack.Budgets(
            maxFrames: max(0, qaMaxFrames),
            maxVideoClips: 0,
            videoClipSeconds: 0.0,
            maxAudioClips: 0,
            audioClipSeconds: 0.0
        )

        return Options(
            sensorsURL: absoluteFileURL(sensorsPath),
            outputDirURL: absoluteFileURL(outPath),
            inputMovieURL: inputPath.map(absoluteFileURL(_:)),
            seed: seed,
            budgets: budgets,
            qaMode: qaMode,
            qaCycles: qaCycles,
            qaMaxConcurrency: max(1, qaMaxConcurrency)
        )
    }

    private static func extractEvidenceAssets(
        evidence: EvidencePack,
        inputMovieURL: URL,
        outputRootURL: URL,
        maxConcurrency: Int
    ) async throws {
        let fm = FileManager.default
        let sem = AsyncSemaphore(value: max(1, maxConcurrency))

        try await withThrowingTaskGroup(of: Void.self) { group in
            for frame in evidence.assets.frames {
                group.addTask {
                    await sem.wait()
                    defer { Task { await sem.signal() } }

                    let outURL = outputRootURL.appendingPathComponent(frame.path)
                    let outDir = outURL.deletingLastPathComponent()
                    try fm.createDirectory(at: outDir, withIntermediateDirectories: true)

                    if fm.fileExists(atPath: outURL.path) {
                        return
                    }

                    print("⏳ Extracting FRAME \(frame.path) @\(String(format: "%.3f", frame.timeSeconds))s…")
                    try extractJpegFrame(
                        inputMovieURL: inputMovieURL,
                        outputJpegURL: outURL,
                        timeSeconds: frame.timeSeconds
                    )
                    print("✅ Extracted FRAME \(frame.path)")
                }
            }

            try await group.waitForAll()
        }
    }

    private static func extractJpegFrame(
        inputMovieURL: URL,
        outputJpegURL: URL,
        timeSeconds: Double
    ) throws {
        let args: [String] = [
            "ffmpeg",
            "-nostdin",
            "-hide_banner",
            "-loglevel", "error",
            "-y",
            "-ss", String(format: "%.3f", max(0.0, timeSeconds)),
            "-i", inputMovieURL.path,
            "-frames:v", "1",
            "-q:v", "2",
            outputJpegURL.path
        ]
        try runProcess("/usr/bin/env", args, timeoutSeconds: 30)
    }

    private static func runProcess(_ executable: String, _ args: [String], timeoutSeconds: TimeInterval) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        try proc.run()

        // Drain pipes continuously to avoid deadlocks.
        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading

        var outData = Data()
        var errData = Data()

        let drainQueue = DispatchQueue(label: "metavislab.autocolor.drain")
        let group = DispatchGroup()

        group.enter()
        drainQueue.async {
            while true {
                let chunk = try? outHandle.read(upToCount: 4096)
                if let chunk, !chunk.isEmpty {
                    outData.append(chunk)
                    continue
                }
                break
            }
            group.leave()
        }

        group.enter()
        drainQueue.async {
            while true {
                let chunk = try? errHandle.read(upToCount: 4096)
                if let chunk, !chunk.isEmpty {
                    errData.append(chunk)
                    continue
                }
                break
            }
            group.leave()
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while proc.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }

        if proc.isRunning {
            proc.terminate()
            throw NSError(domain: "MetaVisLab", code: 3, userInfo: [NSLocalizedDescriptionKey: "Process timed out: \(args.joined(separator: " "))"])
        }

        group.wait()

        if proc.terminationStatus != 0 {
            let stderr = String(data: errData, encoding: .utf8) ?? ""
            let stdout = String(data: outData, encoding: .utf8) ?? ""
            let msg = "Process failed (\(proc.terminationStatus)): \(args.joined(separator: " "))\nSTDOUT:\n\(stdout)\nSTDERR:\n\(stderr)"
            throw NSError(domain: "MetaVisLab", code: 4, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    private static let help = """
    MetaVisLab auto-color-correct

    Usage:
      MetaVisLab auto-color-correct --sensors <sensors.json> --out <dir> [--seed <s>] [--input <movie.mov>]
                                   [--qa off|local-text|gemini] [--qa-cycles <n>] [--qa-max-frames <n>] [--qa-max-concurrency <n>]

    Notes:
      - Deterministic grade proposal using com.metavis.fx.grade.simple (no IDT/ODT changes).
      - If --input is provided, JPEG frames are extracted via ffmpeg for QA evidence.
      - Gemini QA requires explicit opt-in: RUN_GEMINI_QC=1
    """
}
