import Foundation
import MetaVisCore
import MetaVisPerception

enum AutoSpeakerAudioCommand {

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
        let decoder = JSONDecoder()
        let sensors = try decoder.decode(MasterSensors.self, from: data)

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
            summary: "QA not performed (Sprint 17 v1 deterministic propose only)"
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
                proposalFileName: "audio_proposal.json",
                qaOffAcceptance: qaOff,
                makeInitialProposal: {
                    AutoSpeakerAudioProposalV1.propose(from: sensors, options: .init(seed: options.seed))
                },
                buildEvidence: { cycleIndex, escalation in
                    AutoSpeakerAudioEvidenceSelector.buildEvidencePack(
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
                    let qaResult = try await AutoSpeakerAudioQA.run(
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

        print("✅ Wrote audio_proposal.json: \(options.outputDirURL.appendingPathComponent("audio_proposal.json").path)")
        print("✅ Wrote evidence_pack.json: \(options.outputDirURL.appendingPathComponent("evidence_pack.json").path)")
        print("✅ Wrote acceptance_report.json: \(options.outputDirURL.appendingPathComponent("acceptance_report.json").path)")

        _ = result
    }

    private static func applySuggestedEdits(
        _ edits: [AcceptanceReport.SuggestedEdit],
        to proposal: AutoSpeakerAudioProposalV1.AudioProposal,
        sensors: MasterSensors,
        seed: String
    ) -> AutoSpeakerAudioProposalV1.AudioProposal {
        guard !edits.isEmpty else { return proposal }

        var updated = proposal

        // v1 only supports one whitelisted numeric parameter: chain[0].params.globalGainDB
        let path = "chain[0].params.globalGainDB"
        if let edit = edits.first(where: { $0.path == path }) {
            if updated.chain.indices.contains(0), var params = updated.chain[0].params {
                let current = params["globalGainDB"] ?? 0.0
                let applied = updated.whitelist.applyNumericEdit(path: path, current: current, proposed: edit.value)
                params["globalGainDB"] = applied.value
                updated.chain[0].params = params

                // Recompute proposalId to keep artifact self-consistent.
                updated.proposalId = AutoSpeakerAudioProposalV1.computeProposalId(
                    sensors: sensors,
                    seed: seed,
                    policyVersion: AutoSpeakerAudioProposalV1.policyVersion,
                    chain: updated.chain,
                    flags: updated.flags
                )
                updated.reasoning.append("qa_suggested_edit_applied: \(path)=\(applied.value)")
            }
        }

        return updated
    }

    private static func parse(args: [String]) throws -> Options {
        var sensorsPath: String?
        var outPath: String?
        var inputPath: String?
        var seed: String = "default"
        var qaMaxFrames: Int = 8
        var qaMaxVideoClips: Int = 0
        var qaVideoClipSeconds: Double = 0.0
        var qaMaxAudioClips: Int = 4
        var qaAudioClipSeconds: Double = 2.0
        var qaMode: QAMode = .off
        var qaCycles: Int = 2
        var qaMaxConcurrency: Int = 2

        func parseDouble(_ s: String, _ flag: String) throws -> Double {
            guard let v = Double(s), v.isFinite else {
                throw NSError(domain: "MetaVisLab", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid value for \(flag): \(s)"])
            }
            return v
        }

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
            case "--snippet-seconds":
                // Back-compat alias for --qa-audio-clip-seconds
                i += 1; if i < args.count { qaAudioClipSeconds = try parseDouble(args[i], "--snippet-seconds") }
            case "--qa-max-frames":
                i += 1; if i < args.count { qaMaxFrames = Int(args[i]) ?? qaMaxFrames }
            case "--qa-max-video-clips":
                i += 1; if i < args.count { qaMaxVideoClips = Int(args[i]) ?? qaMaxVideoClips }
            case "--qa-video-clip-seconds":
                i += 1; if i < args.count { qaVideoClipSeconds = try parseDouble(args[i], "--qa-video-clip-seconds") }
            case "--qa-max-audio-clips":
                i += 1; if i < args.count { qaMaxAudioClips = Int(args[i]) ?? qaMaxAudioClips }
            case "--qa-audio-clip-seconds":
                i += 1; if i < args.count { qaAudioClipSeconds = try parseDouble(args[i], "--qa-audio-clip-seconds") }
            case "--qa":
                i += 1
                if i < args.count {
                    let v = args[i]
                    qaMode = QAMode(rawValue: v) ?? .off
                }
            case "--qa-cycles":
                i += 1
                if i < args.count {
                    qaCycles = Int(args[i]) ?? qaCycles
                }
            case "--qa-max-concurrency":
                i += 1
                if i < args.count {
                    qaMaxConcurrency = Int(args[i]) ?? qaMaxConcurrency
                }
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
            maxVideoClips: max(0, qaMaxVideoClips),
            videoClipSeconds: max(0.0, qaVideoClipSeconds),
            maxAudioClips: max(0, qaMaxAudioClips),
            audioClipSeconds: max(0.25, qaAudioClipSeconds)
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
            // Audio clips
            for clip in evidence.assets.audioClips {
                group.addTask {
                    await sem.wait()
                    defer { Task { await sem.signal() } }

                    let outURL = outputRootURL.appendingPathComponent(clip.path)
                    let outDir = outURL.deletingLastPathComponent()
                    try fm.createDirectory(at: outDir, withIntermediateDirectories: true)

                    if fm.fileExists(atPath: outURL.path) {
                        return
                    }

                    print("⏳ Extracting WAV \(clip.path) [\(String(format: "%.3f", clip.startSeconds))..\(String(format: "%.3f", clip.endSeconds))]…")
                    try extractWavSnippet(
                        inputMovieURL: inputMovieURL,
                        outputWavURL: outURL,
                        startSeconds: clip.startSeconds,
                        durationSeconds: max(0.1, clip.endSeconds - clip.startSeconds)
                    )
                    print("✅ Extracted WAV \(clip.path)")
                }
            }

            // Frames (JPEG)
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

    private static func extractWavSnippet(
        inputMovieURL: URL,
        outputWavURL: URL,
        startSeconds: Double,
        durationSeconds: Double
    ) throws {
        // Deterministic-ish WAV extraction: PCM16LE mono 48k.
        let args: [String] = [
            "ffmpeg",
            "-nostdin",
            "-hide_banner",
            "-loglevel", "error",
            "-y",
            "-ss", String(format: "%.3f", max(0.0, startSeconds)),
            "-t", String(format: "%.3f", max(0.0, durationSeconds)),
            "-i", inputMovieURL.path,
            "-vn",
            "-ac", "1",
            "-ar", "48000",
            "-c:a", "pcm_s16le",
            outputWavURL.path
        ]
        try runProcess("/usr/bin/env", args, timeoutSeconds: 30)
    }

    private static func runProcess(_ executable: String, _ args: [String], timeoutSeconds: TimeInterval) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        try proc.run()

        // Drain output continuously to avoid deadlock if the child is chatty.
        let readHandle = pipe.fileHandleForReading
        var collected = Data()
        let lock = NSLock()
        readHandle.readabilityHandler = { h in
            let chunk = h.availableData
            guard !chunk.isEmpty else { return }
            lock.lock()
            // Cap to avoid unbounded memory in pathological cases.
            if collected.count < 256_000 {
                let remaining = max(0, 256_000 - collected.count)
                collected.append(chunk.prefix(remaining))
            }
            lock.unlock()
        }

        let deadline = Date().addingTimeInterval(max(1.0, timeoutSeconds))
        while proc.isRunning {
            if Date() > deadline {
                proc.terminate()
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        readHandle.readabilityHandler = nil
        // Flush remaining output.
        let tail = readHandle.readDataToEndOfFile()
        if !tail.isEmpty {
            lock.lock();
            if collected.count < 256_000 {
                let remaining = max(0, 256_000 - collected.count)
                collected.append(tail.prefix(remaining))
            }
            lock.unlock()
        }

        proc.waitUntilExit()

        let data = collected
        if proc.terminationStatus != 0 {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "MetaVisLab",
                code: 12,
                userInfo: [NSLocalizedDescriptionKey: "Process failed: \(args.prefix(1).joined()) (status=\(proc.terminationStatus))\n\(text)"]
            )
        }
    }

    private static let help = """
    auto-speaker-audio

    Emits a deterministic Sprint-17 AudioProposal from an existing sensors.json.

    Usage:
            MetaVisLab auto-speaker-audio --sensors <sensors.json> --out <dir> [--seed <s>] [--input <movie.mov>]
                                        [--qa off|local-text|gemini] [--qa-cycles <n>]
                                        [--qa-max-frames <n>] [--qa-max-audio-clips <n>] [--qa-audio-clip-seconds <s>]
                                        [--qa-max-concurrency <n>]

    Notes:
            - Evidence selection is deterministic (even when QA is off).
            - If --input is provided, extracts WAV snippets at evidence windows.
            - Gemini QA requires explicit opt-in: RUN_GEMINI_QC=1 and GEMINI_API_KEY.
            - QA runs for 0..N cycles (default N=2 when QA is enabled).
    """
}
