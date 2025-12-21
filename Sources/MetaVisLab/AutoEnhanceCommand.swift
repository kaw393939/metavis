import Foundation
import AVFoundation
import simd

import MetaVisCore
import MetaVisPerception
import MetaVisTimeline
import MetaVisSession
import MetaVisSimulation
import MetaVisExport

enum AutoEnhanceCommand {

    enum QAMode: String, Sendable {
        case off = "off"
        case localText = "local-text"
        case gemini = "gemini"
    }

    enum Codec: String, Sendable {
        case hevc
        case prores4444
        case prores422hq

        var avCodec: AVVideoCodecType {
            switch self {
            case .hevc: return .hevc
            case .prores4444: return .proRes4444
            case .prores422hq: return .proRes422HQ
            }
        }
    }

    struct Options: Sendable {
        var sensorsURL: URL
        var inputMovieURL: URL
        var outputDirURL: URL
        var exportMovieURL: URL

        /// Optional trim for export-only preview.
        /// - If `exportSeconds` is nil, exports full duration.
        /// - If `exportSeconds` is non-nil, exports `exportSeconds` starting at `exportStartSeconds`.
        var exportStartSeconds: Double
        var exportSeconds: Double?

        var seed: String
        var allowLarge: Bool

        var qaMode: QAMode
        var qaCycles: Int

        // Evidence budgets
        var qaMaxFrames: Int
        var qaMaxAudioClips: Int
        var qaAudioClipSeconds: Double
        var qaMaxConcurrency: Int

        // Export settings
        var exportHeight: Int
        var exportFPS: Int
        var exportCodec: Codec

        init(
            sensorsURL: URL,
            inputMovieURL: URL,
            outputDirURL: URL,
            exportMovieURL: URL,
            exportStartSeconds: Double,
            exportSeconds: Double?,
            seed: String,
            allowLarge: Bool,
            qaMode: QAMode,
            qaCycles: Int,
            qaMaxFrames: Int,
            qaMaxAudioClips: Int,
            qaAudioClipSeconds: Double,
            qaMaxConcurrency: Int,
            exportHeight: Int,
            exportFPS: Int,
            exportCodec: Codec
        ) {
            self.sensorsURL = sensorsURL
            self.inputMovieURL = inputMovieURL
            self.outputDirURL = outputDirURL
            self.exportMovieURL = exportMovieURL
            self.exportStartSeconds = exportStartSeconds
            self.exportSeconds = exportSeconds
            self.seed = seed
            self.allowLarge = allowLarge
            self.qaMode = qaMode
            self.qaCycles = qaCycles
            self.qaMaxFrames = qaMaxFrames
            self.qaMaxAudioClips = qaMaxAudioClips
            self.qaAudioClipSeconds = qaAudioClipSeconds
            self.qaMaxConcurrency = qaMaxConcurrency
            self.exportHeight = exportHeight
            self.exportFPS = exportFPS
            self.exportCodec = exportCodec
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
        try enforceLargeAssetPolicy(inputURL: options.inputMovieURL, allowLarge: options.allowLarge)

        let fm = FileManager.default
        try fm.createDirectory(at: options.outputDirURL, withIntermediateDirectories: true)

        let sensorsData = try Data(contentsOf: options.sensorsURL)
        let sensors = try JSONDecoder().decode(MasterSensors.self, from: sensorsData)

        if options.qaMode == .gemini {
            guard ProcessInfo.processInfo.environment["RUN_GEMINI_QC"] == "1" else {
                throw NSError(
                    domain: "MetaVisLab",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Gemini network calls are gated. Re-run with RUN_GEMINI_QC=1 in the environment."]
                )
            }
        }

        // 1) Run color loop
        let colorOut = options.outputDirURL.appendingPathComponent("auto_color", isDirectory: true)
        let colorOptions = AutoColorCorrectCommand.Options(
            sensorsURL: options.sensorsURL,
            outputDirURL: colorOut,
            inputMovieURL: options.inputMovieURL,
            seed: options.seed,
            budgets: EvidencePack.Budgets(
                maxFrames: max(0, options.qaMaxFrames),
                maxVideoClips: 0,
                videoClipSeconds: 0,
                maxAudioClips: 0,
                audioClipSeconds: 0
            ),
            qaMode: mapColorQAMode(options.qaMode),
            qaCycles: max(0, options.qaCycles),
            qaMaxConcurrency: max(1, options.qaMaxConcurrency)
        )

        try await AutoColorCorrectCommand.run(options: colorOptions)

        // 2) Run audio loop
        let audioOut = options.outputDirURL.appendingPathComponent("auto_audio", isDirectory: true)
        let audioOptions = AutoSpeakerAudioCommand.Options(
            sensorsURL: options.sensorsURL,
            outputDirURL: audioOut,
            inputMovieURL: options.inputMovieURL,
            seed: options.seed,
            budgets: EvidencePack.Budgets(
                maxFrames: max(0, min(4, options.qaMaxFrames)),
                maxVideoClips: 0,
                videoClipSeconds: 0,
                maxAudioClips: max(0, options.qaMaxAudioClips),
                audioClipSeconds: max(0.0, options.qaAudioClipSeconds)
            ),
            qaMode: mapAudioQAMode(options.qaMode),
            qaCycles: max(0, options.qaCycles),
            qaMaxConcurrency: max(1, options.qaMaxConcurrency)
        )

        try await AutoSpeakerAudioCommand.run(options: audioOptions)

        // 3) Load final proposals (canonical root artifacts)
        let finalColor = try loadJSON(AutoColorGradeProposalV1.GradeProposal.self, from: colorOut.appendingPathComponent("color_grade_proposal.json"))
        let finalAudio = try loadJSON(AutoSpeakerAudioProposalV1.AudioProposal.self, from: audioOut.appendingPathComponent("audio_proposal.json"))

        // 4) Build timeline with both effects and export
        let assetRef = AssetReference(sourceFn: options.inputMovieURL.absoluteString)

        let asset = AVAsset(url: options.inputMovieURL)
        let assetDurationSeconds = max(0.0, (try await asset.load(.duration)).seconds)

        let previewStart: Double = {
            // If caller explicitly requested a trimmed export but didn't provide a start,
            // use sensors' suggested start when available.
            if options.exportSeconds != nil, options.exportStartSeconds == 0, let suggested = sensors.suggestedStart?.time {
                return max(0.0, min(suggested, assetDurationSeconds))
            }
            return max(0.0, min(options.exportStartSeconds, assetDurationSeconds))
        }()

        let exportDurationSeconds: Double = {
            if let seconds = options.exportSeconds {
                return max(0.0, min(seconds, max(0.0, assetDurationSeconds - previewStart)))
            }
            return assetDurationSeconds
        }()

        let dur = Time(seconds: exportDurationSeconds)

        let gradeFX = FeatureApplication(
            id: finalColor.grade.effectId,
            parameters: finalColor.grade.params.mapValues { .float($0) }
        )

        let exportEndSeconds = previewStart + exportDurationSeconds
        let safeForBeautyCoversExport: Bool = {
            guard let descriptors = sensors.descriptors, !descriptors.isEmpty else { return false }
            // Conservative: require a single safe_for_beauty segment that fully covers the exported time range.
            return descriptors.contains(where: { seg in
                seg.label == .safeForBeauty && seg.start <= previewStart + 1e-9 && seg.end >= exportEndSeconds - 1e-9 && seg.confidence >= 0.50
            })
        }()

        let beautyFX: FeatureApplication? = {
            guard safeForBeautyCoversExport else {
                print("ℹ️ Beauty disabled: sensors do not mark export range as safe_for_beauty")
                return nil
            }
            return FeatureApplication(
                // Face-tracked beauty (mask-driven) when sensors allow.
                id: "com.metavis.fx.face.enhance",
                parameters: [
                    "skinSmoothing": .float(0.35),
                    "intensity": .float(0.80)
                ]
            )
        }()

        let videoClip = Clip(
            name: "Input Video",
            asset: assetRef,
            startTime: .zero,
            duration: dur,
            offset: Time(seconds: previewStart),
            effects: [gradeFX] + (beautyFX.map { [$0] } ?? [])
        )

        let audioEffects: [FeatureApplication] = finalAudio.chain.compactMap { fx in
            guard let id = fx.effectId, !id.isEmpty else { return nil }
            return FeatureApplication(
                id: id,
                parameters: (fx.params ?? [:]).mapValues { .float($0) }
            )
        }

        let audioClip = Clip(
            name: "Input Audio",
            asset: assetRef,
            startTime: .zero,
            duration: dur,
            offset: Time(seconds: previewStart),
            effects: audioEffects
        )

        let videoTrack = Track(name: "Video", kind: .video, clips: [videoClip])
        let audioTrack = Track(name: "Audio", kind: .audio, clips: [audioClip])
        let timeline = Timeline(tracks: [videoTrack, audioTrack], duration: dur)

        // Default license: no watermark; keep this a local lab export.
        let config = ProjectConfig(name: "Auto Enhance")
        let session = ProjectSession(initialState: ProjectState(timeline: timeline, config: config))

        let engine = try MetalSimulationEngine()
        let exporter = VideoExporter(engine: engine)

        // Provide per-frame face rectangles for mask-driven effects (e.g. fx_face_enhance).
        // This stays in MetaVisLab so MetaVisSimulation doesn't depend on MetaVisPerception.
        if safeForBeautyCoversExport {
            let samples = sensors.videoSamples
            let times = samples.map { $0.time }

            let nearestSampleIndex: @Sendable (Double) -> Int? = { t in
                guard !times.isEmpty else { return nil }
                if t <= times[0] { return 0 }
                if t >= times[times.count - 1] { return times.count - 1 }

                var lo = 0
                var hi = times.count - 1
                while lo <= hi {
                    let mid = (lo + hi) / 2
                    let v = times[mid]
                    if v < t {
                        lo = mid + 1
                    } else if v > t {
                        hi = mid - 1
                    } else {
                        return mid
                    }
                }

                // `lo` is the insertion point.
                let a = max(0, lo - 1)
                let b = min(times.count - 1, lo)
                return (abs(times[a] - t) <= abs(times[b] - t)) ? a : b
            }

            let provider: @Sendable (Timeline, Time) -> RenderFrameContext? = { timeline, time in
                var faceRectsByClipID: [UUID: [SIMD4<Float>]] = [:]

                for track in timeline.tracks where track.kind == .video {
                    for clip in track.clips {
                        // Convert timeline time to source time (account for clip offset/trim).
                        let local = (time - clip.startTime) + clip.offset
                        let localSeconds = local.seconds

                        guard let idx = nearestSampleIndex(localSeconds) else {
                            continue
                        }

                        let faces = samples[idx].faces
                        let rects: [SIMD4<Float>] = faces.map { f in
                            let r = f.rect
                            return SIMD4<Float>(Float(r.origin.x), Float(r.origin.y), Float(r.size.width), Float(r.size.height))
                        }
                        faceRectsByClipID[clip.id] = rects
                    }
                }

                return RenderFrameContext(faceRectsByClipID: faceRectsByClipID)
            }

            await exporter.setFrameContextProvider(provider)
        }

        let quality = QualityProfile(name: "AutoEnhance",
                                     fidelity: .high,
                                     resolutionHeight: options.exportHeight,
                                     colorDepth: 10)

        print("⏳ Exporting enhanced movie…")
        print("   → \(options.exportMovieURL.path)")

        try await session.exportMovie(
            using: exporter,
            to: options.exportMovieURL,
            quality: quality,
            frameRate: options.exportFPS,
            codec: options.exportCodec.avCodec,
            audioPolicy: .auto
        )

        // 5) Write a small manifest for humans
        let summary = AutoEnhanceSummary(
            inputMovie: options.inputMovieURL.path,
            outputMovie: options.exportMovieURL.path,
            colorProposalId: finalColor.proposalId,
            audioProposalId: finalAudio.proposalId,
            qaMode: options.qaMode.rawValue
        )
        try JSONWriting.write(summary, to: options.outputDirURL.appendingPathComponent("auto_enhance_summary.json"))

        print("✅ Exported enhanced movie")
        print("✅ Wrote summary: \(options.outputDirURL.appendingPathComponent("auto_enhance_summary.json").path)")
    }

    private struct AutoEnhanceSummary: Codable, Sendable {
        var inputMovie: String
        var outputMovie: String
        var colorProposalId: String
        var audioProposalId: String
        var qaMode: String
    }

    private static func mapColorQAMode(_ mode: QAMode) -> AutoColorCorrectCommand.QAMode {
        switch mode {
        case .off: return .off
        case .localText: return .localText
        case .gemini: return .gemini
        }
    }

    private static func mapAudioQAMode(_ mode: QAMode) -> AutoSpeakerAudioCommand.QAMode {
        switch mode {
        case .off: return .off
        case .localText: return .localText
        case .gemini: return .gemini
        }
    }

    private static func loadJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func enforceLargeAssetPolicy(inputURL: URL, allowLarge: Bool) throws {
        let name = inputURL.lastPathComponent.lowercased()

        let sizeBytes: Int64
        do {
            let values = try inputURL.resourceValues(forKeys: [.fileSizeKey])
            sizeBytes = Int64(values.fileSize ?? 0)
        } catch {
            sizeBytes = 0
        }

        let isLikelyLarge = (sizeBytes >= 1_000_000_000) || name.contains("keith_talk")
        if isLikelyLarge && !allowLarge {
            throw NSError(
                domain: "MetaVisLab",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Refusing to process large asset (\(name), \(sizeBytes) bytes) without --allow-large."]
            )
        }
    }

    private static func absoluteFileURL(_ path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(path)
    }

    private static func parse(args: [String]) throws -> Options {
        func usage(_ message: String) -> NSError {
            NSError(domain: "MetaVisLab", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(message)\n\n" + help])
        }

        var sensorsPath: String?
        var inputPath: String?
        var outPath: String?
        var exportPath: String?

        var exportStartSeconds: Double = 0
        var exportSeconds: Double? = nil

        var seed: String = "default"
        var allowLarge = false

        var qaMode: QAMode = .off
        var qaCycles: Int = 2
        var qaMaxFrames: Int = 6
        var qaMaxAudioClips: Int = 2
        var qaAudioClipSeconds: Double = 8
        var qaMaxConcurrency: Int = 2

        var exportHeight: Int = 1080
        var exportFPS: Int = 24
        var exportCodec: Codec = .hevc

        var i = 0
        while i < args.count {
            let a = args[i]
            switch a {
            case "--sensors":
                i += 1; if i < args.count { sensorsPath = args[i] }
            case "--input":
                i += 1; if i < args.count { inputPath = args[i] }
            case "--out":
                i += 1; if i < args.count { outPath = args[i] }
            case "--export":
                i += 1; if i < args.count { exportPath = args[i] }
            case "--export-start":
                i += 1; if i < args.count { exportStartSeconds = Double(args[i]) ?? exportStartSeconds }
            case "--export-seconds":
                i += 1
                if i < args.count {
                    exportSeconds = Double(args[i])
                }
            case "--seed":
                i += 1; if i < args.count { seed = args[i] }
            case "--allow-large":
                allowLarge = true

            case "--qa":
                i += 1
                if i < args.count {
                    guard let m = QAMode(rawValue: args[i]) else {
                        throw usage("Invalid --qa (expected off|local-text|gemini)")
                    }
                    qaMode = m
                }
            case "--qa-cycles":
                i += 1; if i < args.count { qaCycles = Int(args[i]) ?? qaCycles }
            case "--qa-max-frames":
                i += 1; if i < args.count { qaMaxFrames = Int(args[i]) ?? qaMaxFrames }
            case "--qa-max-audio-clips":
                i += 1; if i < args.count { qaMaxAudioClips = Int(args[i]) ?? qaMaxAudioClips }
            case "--qa-audio-clip-seconds":
                i += 1; if i < args.count { qaAudioClipSeconds = Double(args[i]) ?? qaAudioClipSeconds }
            case "--qa-max-concurrency":
                i += 1; if i < args.count { qaMaxConcurrency = Int(args[i]) ?? qaMaxConcurrency }

            case "--height":
                i += 1; if i < args.count { exportHeight = Int(args[i]) ?? exportHeight }
            case "--fps":
                i += 1; if i < args.count { exportFPS = Int(args[i]) ?? exportFPS }
            case "--codec":
                i += 1
                if i < args.count {
                    guard let c = Codec(rawValue: args[i]) else {
                        throw usage("Invalid --codec (expected hevc|prores4444|prores422hq)")
                    }
                    exportCodec = c
                }
            default:
                throw usage("Unknown arg: \(a)")
            }
            i += 1
        }

        guard let sensorsPath else { throw usage("Missing --sensors") }
        guard let inputPath else { throw usage("Missing --input") }
        guard let outPath else { throw usage("Missing --out") }

        let sensorsURL = absoluteFileURL(sensorsPath)
        let inputMovieURL = absoluteFileURL(inputPath)
        let outputDirURL = absoluteFileURL(outPath)

        let exportMovieURL: URL = {
            if let exportPath {
                return absoluteFileURL(exportPath)
            }
            return outputDirURL.appendingPathComponent("enhanced.mov")
        }()

        return Options(
            sensorsURL: sensorsURL,
            inputMovieURL: inputMovieURL,
            outputDirURL: outputDirURL,
            exportMovieURL: exportMovieURL,
            exportStartSeconds: exportStartSeconds,
            exportSeconds: exportSeconds,
            seed: seed,
            allowLarge: allowLarge,
            qaMode: qaMode,
            qaCycles: qaCycles,
            qaMaxFrames: qaMaxFrames,
            qaMaxAudioClips: qaMaxAudioClips,
            qaAudioClipSeconds: qaAudioClipSeconds,
            qaMaxConcurrency: qaMaxConcurrency,
            exportHeight: exportHeight,
            exportFPS: exportFPS,
            exportCodec: exportCodec
        )
    }

    private static let help = """
MetaVisLab auto-enhance

Runs Auto Color Correct + Auto Speaker Audio and exports an enhanced .mov.

Usage:
  MetaVisLab auto-enhance --sensors <sensors.json> --input <movie.mov> --out <dir>
    [--export <enhanced.mov>]
        [--export-start <seconds>] [--export-seconds <seconds>]
    [--seed <s>]
    [--qa off|local-text|gemini] [--qa-cycles <n>]
    [--qa-max-frames <n>] [--qa-max-audio-clips <n>] [--qa-audio-clip-seconds <s>]
    [--qa-max-concurrency <n>]
    [--height <h>] [--fps <n>] [--codec hevc|prores4444|prores422hq]
    [--allow-large]

Notes:
  - Exports a timeline with com.metavis.fx.grade.simple on the video clip
    and audio.dialogCleanwater.v1 on the audio clip.
    - Use --export-seconds for a fast preview export; when set and --export-start is 0,
        sensors.suggestedStart (if present) is used as the preview start.
  - Gemini QA requires explicit opt-in: RUN_GEMINI_QC=1.
"""
}
