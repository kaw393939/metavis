import Foundation
import MetaVisCore
import MetaVisExport
import MetaVisPerception

enum DiarizeCommand {
    static func run(args: [String]) async throws {
        if args.first == "--help" || args.first == "-h" || args.contains("--help") || args.contains("-h") || args.first == nil {
            print(help)
            return
        }

        let options = try parseArgs(args)
        try FileManager.default.createDirectory(at: options.outputDirURL, withIntermediateDirectories: true)

        let sensors = try loadJSON(MasterSensors.self, from: options.sensorsURL)
        let words = try loadTranscriptWordsJSONL(from: options.transcriptURL)

        // Pivot: prefer ECAPA-TDNN embedding diarization when configured.
        // Fallback to Sticky Fusion baseline when not configured or when extraction/model fails.
        let diarizedWords: [TranscriptWordV1]
        let diarizedMap: SpeakerDiarizer.SpeakerMapV1
        do {
            let env = ProcessInfo.processInfo.environment
            let mode = (env["METAVIS_DIARIZE_MODE"] ?? "").lowercased()
            if mode == "ecapa" {
                let modelPath: String
                if let p = env["METAVIS_ECAPA_MODEL"], !p.isEmpty {
                    modelPath = p
                } else {
                    // Convenience default for local development / tests.
                    let cwd = FileManager.default.currentDirectoryPath
                    let fallback = URL(fileURLWithPath: cwd).appendingPathComponent("assets/models/speaker/Embedding.mlmodelc").path
                    if FileManager.default.fileExists(atPath: fallback) {
                        modelPath = fallback
                    } else {
                        throw NSError(domain: "MetaVisLab", code: 2, userInfo: [NSLocalizedDescriptionKey: "METAVIS_DIARIZE_MODE=ecapa requires METAVIS_ECAPA_MODEL=<.mlmodelc path> (or place assets/models/speaker/Embedding.mlmodelc in the repo)"])
                    }
                }
                let inputName = env["METAVIS_ECAPA_INPUT"]
                let outputName = env["METAVIS_ECAPA_OUTPUT"]
                let dim: Int? = (env["METAVIS_ECAPA_DIM"]).flatMap { Int($0) }
                let sampleRate: Double = (env["METAVIS_ECAPA_SR"]).flatMap { Double($0) }.map { max(1000.0, $0) } ?? 16_000
                let windowSeconds: Double = (env["METAVIS_ECAPA_WINDOW"]).flatMap { Double($0) }.map { max(0.5, $0) } ?? 3.0

                let modelURL = URL(fileURLWithPath: modelPath)
                let movieURL = URL(fileURLWithPath: sensors.source.path)

                // FluidInference's speaker-diarization-coreml provides a pyannote-style pipeline:
                //   FBank.mlmodelc + Embedding.mlmodelc
                // Some other public speaker-embedding models (e.g. ECAPA variants) take raw PCM.
                // If the configured model name indicates one of these, select accordingly.
                let embeddingModel: any SpeakerEmbeddingModel
                if modelURL.lastPathComponent.lowercased().contains("embedding") {
                    let cwd = FileManager.default.currentDirectoryPath
                    let defaultFBank = URL(fileURLWithPath: cwd).appendingPathComponent("assets/models/speaker/FBank.mlmodelc").path
                    let fbankPath = env["METAVIS_ECAPA_FBANK_MODEL"]
                        ?? (FileManager.default.fileExists(atPath: defaultFBank) ? defaultFBank : modelURL.deletingLastPathComponent().appendingPathComponent("FBank.mlmodelc").path)
                    let fbankURL = URL(fileURLWithPath: fbankPath)
                    embeddingModel = try PyannoteFBankEmbeddingCoreMLSpeakerEmbeddingModel(
                        fbankModelURL: fbankURL,
                        embeddingModelURL: modelURL,
                        sampleRate: sampleRate
                    )
                } else {
                    embeddingModel = try ECAPATDNNCoreMLSpeakerEmbeddingModel(
                        modelURL: modelURL,
                        inputName: inputName,
                        outputName: outputName,
                        windowSeconds: windowSeconds,
                        sampleRate: sampleRate,
                        embeddingDimension: dim
                    )
                }

                let hopSeconds: Double = (env["METAVIS_ECAPA_HOP"]).flatMap { Double($0) }.map { max(0.05, $0) } ?? 0.5
                let defaultSimThreshold: Float
                if embeddingModel.name.contains("pyannote") || embeddingModel.windowSeconds >= 9.0 {
                    defaultSimThreshold = 0.60
                } else if embeddingModel.name.contains("ecapa") {
                    defaultSimThreshold = 0.70
                } else {
                    defaultSimThreshold = 0.80
                }
                let simThreshold: Float = (env["METAVIS_ECAPA_SIM"]).flatMap { Float($0) }.map { min(0.999, max(0.0, $0)) } ?? defaultSimThreshold
                let cooccurrenceThreshold: Double = (env["METAVIS_ECAPA_COOCCUR"]).flatMap { Double($0) }.map { min(1.0, max(0.0, $0)) } ?? 0.8

                var diarizeOptions = AudioEmbeddingSpeakerDiarizer.Options()
                diarizeOptions.windowSeconds = embeddingModel.windowSeconds
                diarizeOptions.hopSeconds = hopSeconds
                diarizeOptions.clusterSimilarityThreshold = simThreshold
                diarizeOptions.cooccurrenceThreshold = cooccurrenceThreshold
                // Real waveform ECAPA models can produce unstable embeddings on near-silence / padded tails,
                // which tends to create spurious extra clusters. Gate out low-energy windows by default.
                if embeddingModel.name.contains("ecapa") {
                    diarizeOptions.minWindowRMS = 0.003
                }

                let res = try AudioEmbeddingSpeakerDiarizer.diarize(
                    words: words,
                    sensors: sensors,
                    movieURL: movieURL,
                    embeddingModel: embeddingModel
                    , options: diarizeOptions
                )
                diarizedWords = res.words
                diarizedMap = res.speakerMap
            } else {
                let baseline = SpeakerDiarizer.diarize(words: words, sensors: sensors)
                diarizedWords = baseline.words
                diarizedMap = baseline.speakerMap
            }
        } catch {
            // Baseline fallback: keep pipeline usable even if the embedding model isn't available yet.
            let baseline = SpeakerDiarizer.diarize(words: words, sensors: sensors)
            diarizedWords = baseline.words
            diarizedMap = baseline.speakerMap
        }

        // 1) Write updated transcript.words.v1.jsonl
        let outWordsURL = options.outputDirURL.appendingPathComponent("transcript.words.v1.jsonl")
        try writeTranscriptWordsJSONL(to: outWordsURL, words: diarizedWords)

        // 1b) Write governed attribution confidence sidecar.
        let attributionURL = options.outputDirURL.appendingPathComponent("transcript.attribution.v1.jsonl")
        let attributions = buildAttributionRecords(words: diarizedWords, sensors: sensors)
        try writeTranscriptAttributionsJSONL(to: attributionURL, records: attributions)

        // 2) Write captions.vtt with <v Speaker> tags.
        let cues = cuesFromWords(diarizedWords)
        let captionsURL = options.outputDirURL.appendingPathComponent("captions.vtt")
        try await CaptionSidecarWriter.writeWebVTT(to: captionsURL, cues: cues)

        // 3) Write speaker map.
        let mapURL = options.outputDirURL.appendingPathComponent("speaker_map.v1.json")
        var deterministicMap = diarizedMap
        deterministicMap.createdAt = Date(timeIntervalSince1970: 0)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        let mapData = try enc.encode(deterministicMap)
        try mapData.write(to: mapURL, options: [.atomic])

        // 4) Write temporal context (v1).
        let temporalURL = options.outputDirURL.appendingPathComponent("temporal.context.v1.json")
        let temporal = TemporalContextAggregator.aggregate(sensors: sensors, words: diarizedWords)
        let temporalData = try enc.encode(temporal)
        try temporalData.write(to: temporalURL, options: [.atomic])

        // 5) Write identity bindings (v1).
        let bindingsURL = options.outputDirURL.appendingPathComponent("identity.bindings.v1.json")
        let bindings = IdentityBindingGraphBuilder.build(sensors: sensors, words: diarizedWords)
        let bindingsData = try enc.encode(bindings)
        try bindingsData.write(to: bindingsURL, options: [.atomic])

        // 5b) Write identity timeline spine (v1).
        let timelineURL = options.outputDirURL.appendingPathComponent("identity.timeline.v1.json")
        let timeline = IdentityTimelineBuilder.build(
            sensors: sensors,
            diarizedWords: diarizedWords,
            attributions: attributions,
            bindings: bindings
        )
        let timelineData = try enc.encode(timeline)
        try timelineData.write(to: timelineURL, options: [.atomic])

        // 6) Write bounded semantic frames for LLM consumption (v2).
        let semanticURL = options.outputDirURL.appendingPathComponent("semantic.frame.v2.jsonl")
        let semanticFrames = SemanticFrameV2Builder.buildAll(
            sensors: sensors,
            diarizedWords: diarizedWords,
            bindings: bindings
        )
        try writeSemanticFramesV2JSONL(to: semanticURL, frames: semanticFrames)

        print("diarize: wrote \(outWordsURL.lastPathComponent), \(attributionURL.lastPathComponent), \(captionsURL.lastPathComponent), \(mapURL.lastPathComponent), \(temporalURL.lastPathComponent), \(bindingsURL.lastPathComponent), \(timelineURL.lastPathComponent), \(semanticURL.lastPathComponent)")
    }

    private static func writeSemanticFramesV2JSONL(to url: URL, frames: [SemanticFrameV2]) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        var out = ""
        out.reserveCapacity(frames.count * 256)
        for f in frames {
            let data = try enc.encode(f)
            out.append(String(decoding: data, as: UTF8.self))
            out.append("\n")
        }
        try out.write(to: url, atomically: true, encoding: .utf8)
    }

    private struct Options {
        var sensorsURL: URL
        var transcriptURL: URL
        var outputDirURL: URL
    }

    private static func parseArgs(_ args: [String]) throws -> Options {
        var sensorsPath: String?
        var transcriptPath: String?
        var outPath: String?

        var i = 0
        while i < args.count {
            let a = args[i]
            switch a {
            case "--sensors":
                i += 1
                if i < args.count { sensorsPath = args[i] }
            case "--transcript":
                i += 1
                if i < args.count { transcriptPath = args[i] }
            case "--out":
                i += 1
                if i < args.count { outPath = args[i] }
            default:
                break
            }
            i += 1
        }

        guard let sensorsPath, !sensorsPath.isEmpty else {
            throw NSError(domain: "MetaVisLab", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing required flag: --sensors <sensors.json>"])
        }
        guard let transcriptPath, !transcriptPath.isEmpty else {
            throw NSError(domain: "MetaVisLab", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing required flag: --transcript <transcript.words.v1.jsonl>"])
        }
        guard let outPath, !outPath.isEmpty else {
            throw NSError(domain: "MetaVisLab", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing required flag: --out <dir>"])
        }

        return Options(
            sensorsURL: URL(fileURLWithPath: sensorsPath),
            transcriptURL: URL(fileURLWithPath: transcriptPath),
            outputDirURL: URL(fileURLWithPath: outPath, isDirectory: true)
        )
    }

    private static func loadJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func loadTranscriptWordsJSONL(from url: URL) throws -> [TranscriptWordV1] {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let lines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var out: [TranscriptWordV1] = []
        out.reserveCapacity(lines.count)

        let dec = JSONDecoder()
        for line in lines {
            guard let data = line.data(using: .utf8) else { continue }
            out.append(try dec.decode(TranscriptWordV1.self, from: data))
        }
        return out
    }

    private static func writeTranscriptWordsJSONL(to url: URL, words: [TranscriptWordV1]) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]

        var out = Data()
        out.reserveCapacity(words.count * 160)

        for w in words {
            let line = try enc.encode(w)
            out.append(line)
            out.append(0x0A)
        }

        try out.write(to: url, options: [.atomic])
    }

    private static func buildAttributionRecords(words: [TranscriptWordV1], sensors: MasterSensors) -> [TranscriptAttributionV1] {
        func ticksForTiming(_ w: TranscriptWordV1) -> (start: Int64, end: Int64) {
            let start = w.timelineTimeTicks ?? w.sourceTimeTicks
            let end = w.timelineTimeEndTicks ?? w.sourceTimeEndTicks
            return (start: start, end: max(start, end))
        }

        func midSeconds(startTicks: Int64, endTicks: Int64) -> Double {
            let midTicks = startTicks + (max(Int64(0), endTicks - startTicks) / 2)
            return Double(midTicks) / 60000.0
        }

        // Video sample lookup window: half stride with a small minimum to tolerate drift.
        let stride = max(0.01, sensors.sampling.videoStrideSeconds)
        let sampleWindow = max(0.12, (stride / 2.0) + 0.02)

        func nearestSample(at t: Double) -> (sample: MasterSensors.VideoSample?, dt: Double) {
            var best: MasterSensors.VideoSample?
            var bestDt = Double.greatestFiniteMagnitude
            for s in sensors.videoSamples {
                let dt = abs(s.time - t)
                if dt < bestDt {
                    bestDt = dt
                    best = s
                }
            }
            return (best, bestDt)
        }

        func faceScore(_ f: MasterSensors.Face) -> Double {
            let r = f.rect
            let area = max(0.0, Double(r.width * r.height))
            let cx = Double(r.midX)
            let cy = Double(r.midY)
            let dx = cx - 0.5
            let dy = cy - 0.5
            let dist = sqrt(dx * dx + dy * dy) // 0..~0.707
            let center = max(0.0, 1.0 - (dist / 0.70710678))
            // Area dominates; center proximity is a weak tiebreaker.
            return area + (0.05 * center)
        }

        func attributionConfidence(for w: TranscriptWordV1) -> ConfidenceRecordV1 {
            guard let speakerId = w.speakerId else {
                return ConfidenceRecordV1(
                    score: 0.0,
                    grade: .INVALID,
                    sources: [.audio],
                    reasons: [.audio_silence],
                    evidenceRefs: [],
                    policyId: nil
                )
            }

            func speechLikeConfidence(at t: Double) -> Double? {
                // Choose the highest-confidence speechLike segment that covers this time.
                var best: Double? = nil
                for seg in sensors.audioSegments {
                    guard seg.kind == .speechLike else { continue }
                    guard t >= seg.start, t <= seg.end else { continue }
                    let c = max(0.0, min(1.0, seg.confidence))
                    if best == nil || c > best! { best = c }
                }
                return best
            }

            let timing = ticksForTiming(w)
            let t = midSeconds(startTicks: timing.start, endTicks: timing.end)

            let (sample, dt) = nearestSample(at: t)
            let faces: [MasterSensors.Face]
            if let sample, dt <= sampleWindow {
                faces = sample.faces
            } else {
                faces = []
            }

            if speakerId == "OFFSCREEN" {
                if faces.isEmpty {
                    return ConfidenceRecordV1.evidence(
                        score: 0.55,
                        sources: [.vision],
                        reasons: [.no_face_detected, .offscreen_forced],
                        evidenceRefs: []
                    )
                }
                return ConfidenceRecordV1.evidence(
                    score: 0.55,
                    sources: [.audio],
                    reasons: [.low_audio_similarity, .offscreen_forced],
                    evidenceRefs: []
                )
            }

            // speakerId values are diarization speaker IDs (often audio cluster IDs like C1/C2).
            // Confidence here is for attribution to that speakerId, not for binding to a specific face.
            // We still expose binding uncertainty as reasons when multiple faces are present.
            let segConf = speechLikeConfidence(at: t)
            if segConf == nil {
                // Not in a speech-like region: attribution is likely unstable.
                var reasons: [ReasonCodeV1] = [.audio_silence]
                if faces.isEmpty { reasons.append(.no_face_detected) }
                return ConfidenceRecordV1.evidence(
                    score: 0.30,
                    sources: [.audio],
                    reasons: reasons,
                    evidenceRefs: []
                )
            }

            let c = segConf ?? 0.0
            let baseScore: Float
            if c >= 0.85 {
                baseScore = 0.92
            } else if c >= 0.70 {
                baseScore = 0.88
            } else {
                baseScore = 0.82
            }

            var reasons: [ReasonCodeV1] = []
            var sources: [ConfidenceSourceV1] = [.audio]
            var evidenceRefs: [EvidenceRefV1] = [.metric("audioSegment.confidence", value: c)]

            if faces.isEmpty {
                // Can't bind to on-screen identity at this moment.
                reasons.append(.no_face_detected)
            } else {
                sources = [.fused]
                evidenceRefs.append(.metric("video.faces.count", value: Double(faces.count)))
                if faces.count >= 2 {
                    reasons.append(.multiple_faces_competing)
                    reasons.append(.speaker_binding_missing)
                }
            }

            return ConfidenceRecordV1.evidence(
                score: baseScore,
                sources: sources,
                reasons: reasons,
                evidenceRefs: evidenceRefs
            )
        }

        return words.map { w in
            TranscriptAttributionV1(
                wordId: w.wordId,
                speakerId: w.speakerId,
                speakerLabel: w.speakerLabel,
                attributionConfidence: attributionConfidence(for: w)
            )
        }
    }

    private static func writeTranscriptAttributionsJSONL(to url: URL, records: [TranscriptAttributionV1]) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]

        var out = Data()
        out.reserveCapacity(records.count * 220)

        for r in records {
            let line = try enc.encode(r)
            out.append(line)
            out.append(0x0A)
        }

        try out.write(to: url, options: [.atomic])
    }

    private struct TimedWord {
        var text: String
        var startTicks: Int64
        var endTicks: Int64
        var speaker: String?
    }

    private static func cuesFromWords(_ words: [TranscriptWordV1]) -> [CaptionCue] {
        // Convert diarized transcript words to caption cues.
        // We reuse the basic chunking rules from transcript generation, but we also flush on speaker changes.
        let timed: [TimedWord] = words.compactMap { w in
            let start = w.timelineTimeTicks ?? w.sourceTimeTicks
            let end = w.timelineTimeEndTicks ?? w.sourceTimeEndTicks
            let s = min(start, end)
            let e = max(start, end)
            let text = w.word.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { return nil }
            return TimedWord(text: text, startTicks: s, endTicks: e, speaker: w.speakerLabel)
        }

        guard !timed.isEmpty else { return [] }

        var cues: [CaptionCue] = []
        cues.reserveCapacity(max(8, timed.count / 8))

        var currentWords: [TimedWord] = []
        currentWords.reserveCapacity(16)

        func flushCue() {
            guard let first = currentWords.first, let last = currentWords.last else { return }
            let start = Double(first.startTicks) / 60000.0
            let end = max(start, Double(last.endTicks) / 60000.0)
            let text = currentWords.map { $0.text }.joined(separator: " ")
            let speaker = currentWords.first?.speaker
            cues.append(CaptionCue(startSeconds: start, endSeconds: end, text: text, speaker: speaker))
            currentWords.removeAll(keepingCapacity: true)
        }

        var lastEndTicks: Int64? = nil
        var lastSpeaker: String? = nil

        for w in timed {
            if currentWords.isEmpty {
                currentWords.append(w)
                lastEndTicks = w.endTicks
                lastSpeaker = w.speaker
                continue
            }

            let firstStartTicks = currentWords.first?.startTicks ?? w.startTicks
            let cueDurationTicks = max(Int64(0), w.endTicks - firstStartTicks)
            let cueDurationSeconds = Double(cueDurationTicks) / 60000.0

            let gapTicks = (lastEndTicks ?? w.startTicks) > w.startTicks ? 0 : (w.startTicks - (lastEndTicks ?? w.startTicks))
            let gapSeconds = Double(gapTicks) / 60000.0

            let tooLong = cueDurationSeconds >= 4.0
            let tooManyWords = currentWords.count >= 12
            let bigGap = gapSeconds >= 0.8
            let endsSentence = (currentWords.last?.text.last).map { ".!?".contains($0) } ?? false
            let speakerChanged = (lastSpeaker ?? "") != (w.speaker ?? "")

            if tooLong || tooManyWords || bigGap || endsSentence || speakerChanged {
                flushCue()
            }

            currentWords.append(w)
            lastEndTicks = w.endTicks
            lastSpeaker = w.speaker
        }

        flushCue()
        return cues
    }

    static let help = """
    diarize

    Usage:
      MetaVisLab diarize --sensors <sensors.json> --transcript <transcript.words.v1.jsonl> --out <dir>

        ECAPA (embedding) mode:
            Set environment variables:
                METAVIS_DIARIZE_MODE=ecapa
                METAVIS_ECAPA_MODEL=<path to .mlmodelc>
                                METAVIS_ECAPA_INPUT=<coreml input feature name> (optional, if omitted, the first multiarray input is used)
                                METAVIS_ECAPA_OUTPUT=<coreml output feature name> (optional, if omitted, the first multiarray output is used)
                                METAVIS_ECAPA_DIM=<embedding dimension> (optional, if omitted, inferred from the output multiarray constraints when available)
                                METAVIS_ECAPA_SR=<audio sample rate> (optional, default: 16000)
                                METAVIS_ECAPA_FBANK_MODEL=<.mlmodelc path>   (optional; required for Embedding.mlmodelc; default: assets/models/speaker/FBank.mlmodelc or sibling FBank.mlmodelc)
                                METAVIS_ECAPA_WINDOW=<embedding window size in seconds> (optional, default: 3.0)
                                METAVIS_ECAPA_SIM=<cosine similarity threshold> (optional, default: 0.80; higher = more speakers)
                                METAVIS_ECAPA_HOP=<seconds between windows> (optional, default: 0.50)
                                METAVIS_ECAPA_COOCCUR=<0..1> (optional, default: 0.80)

                        Real ECAPA model build (macOS):
                                scripts/build_ecapa_coreml_macos.sh

    Outputs:
      <out>/transcript.words.v1.jsonl   (speakerId/speakerLabel populated)
      <out>/captions.vtt                (WebVTT with <v Speaker> tags)
      <out>/speaker_map.v1.json         (stable mapping of speakerId -> speakerLabel)
    """
}
