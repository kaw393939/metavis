import Foundation
import AVFoundation
import MetaVisCore
import MetaVisTimeline
import MetaVisSession
import MetaVisSimulation
import MetaVisExport

enum EXRTimelineCommand {
    struct Options {
        var inputDirURL: URL
        var outputDirURL: URL
        var secondsPerImage: Double
        var transition: Transition
        var resolutionHeight: Int
        var frameRate: Int32
        var codec: AVVideoCodecType
        var extractEditedEXR: Bool
    }

    static func run(args: [String]) async throws {
        let options = try parse(args: args)
        try await run(options: options)
    }

    static func run(options: Options) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: options.outputDirURL, withIntermediateDirectories: true)

        let exrURLs = try fm.contentsOfDirectory(at: options.inputDirURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "exr" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        guard !exrURLs.isEmpty else {
            throw NSError(domain: "MetaVisLab", code: 400, userInfo: [NSLocalizedDescriptionKey: "No .exr files found in: \(options.inputDirURL.path)"])
        }

        // 1) Build a Timeline: one clip per EXR
        // Important: ProjectSession's current reducer does not auto-update timeline.duration.
        // Construct a fully formed Timeline with explicit duration.
        let dur = max(0.1, options.secondsPerImage)
        let trans = options.transition

        var clips: [Clip] = []
        clips.reserveCapacity(exrURLs.count)

        var t = Time.zero
        for (idx, url) in exrURLs.enumerated() {
            let assetRef = AssetReference(sourceFn: url.absoluteURL.absoluteString)
            let effects: [FeatureApplication] = [
                // Apply a deterministic edit so roundtrip is meaningful.
                .init(id: "com.metavis.fx.tonemap.aces", parameters: ["exposure": .float(1.0)])
            ]

            // Transitions are represented as per-clip fade-in/out.
            // For crossfades, we offset clip start times so clips overlap by transition duration.
            let isFirst = (idx == 0)
            let isLast = (idx == exrURLs.count - 1)
            let transitionIn: Transition? = isFirst ? nil : trans
            let transitionOut: Transition? = isLast ? nil : trans

            clips.append(
                Clip(
                    name: String(format: "%02d_%@", idx, url.deletingPathExtension().lastPathComponent),
                    asset: assetRef,
                    startTime: t,
                    duration: Time(seconds: dur),
                    offset: .zero,
                    transitionIn: transitionIn,
                    transitionOut: transitionOut,
                    effects: effects
                )
            )

            // Make adjacent clips overlap during transition so the compiler sees both as active.
            if trans.duration.seconds > 0, !isLast {
                t = t + Time(seconds: max(0.0, dur - trans.duration.seconds))
            } else {
                t = t + Time(seconds: dur)
            }
        }

        let track = Track(name: "EXR Track", kind: .video, clips: clips)
        let timeline = Timeline(tracks: [track], duration: t)

        let license = ProjectLicense(ownerId: "lab", maxExportResolution: 4320, requiresWatermark: false, allowOpenEXR: true)
        let config = ProjectConfig(name: "EXR Timeline", license: license)
        let session = ProjectSession(initialState: ProjectState(timeline: timeline, config: config))

        // 2) Persist timeline JSON (useful for inspection)
        let state = await session.state
        let timelineURL = options.outputDirURL.appendingPathComponent("timeline.json")
        try JSONWriting.write(state.timeline, to: timelineURL)

        // 3) Export movie
        let engine = try MetalSimulationEngine()
        let exporter = VideoExporter(engine: engine, trace: StdoutTraceSink())
        let outputMovieURL = options.outputDirURL.appendingPathComponent("exr_timeline.mov")
        let quality = QualityProfile(name: "EXRTimeline", fidelity: .high, resolutionHeight: options.resolutionHeight, colorDepth: 10)

        print("⏳ Exporting EXR timeline…")
        try await session.exportMovie(
            using: exporter,
            to: outputMovieURL,
            quality: quality,
            frameRate: options.frameRate,
            codec: options.codec,
            audioPolicy: .forbidden
        )
        print("✅ Exported: \(outputMovieURL.path)")

        // 4) Roundtrip: extract per-clip midpoint frames as EXR (edited output)
        if options.extractEditedEXR {
            let framesDir = options.outputDirURL.appendingPathComponent("edited_exr", isDirectory: true)
            try fm.createDirectory(at: framesDir, withIntermediateDirectories: true)

            for (idx, url) in exrURLs.enumerated() {
                let mid = (Double(idx) * dur) + (dur * 0.5)
                let outEXR = framesDir.appendingPathComponent(String(format: "%02d_%@_edited.exr", idx, url.deletingPathExtension().lastPathComponent))
                try runFFmpegExtractEXR(inputMovieURL: outputMovieURL, atSeconds: mid, outEXRURL: outEXR)
            }
            print("✅ Extracted edited EXRs: \(framesDir.path)")
        }
    }

    // MARK: - FFmpeg

    private static func runFFmpegExtractEXR(inputMovieURL: URL, atSeconds: Double, outEXRURL: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [
            "ffmpeg",
            "-v", "error",
            "-ss", String(format: "%.6f", max(0.0, atSeconds)),
            "-i", inputMovieURL.path,
            "-frames:v", "1",
            "-y",
            outEXRURL.path
        ]

        let err = Pipe()
        p.standardError = err
        try p.run()
        p.waitUntilExit()

        guard p.terminationStatus == 0 else {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "MetaVisLab", code: 401, userInfo: [NSLocalizedDescriptionKey: "ffmpeg frame extract failed: \(msg)"])
        }
    }

    // MARK: - Parsing

    private static func parse(args: [String]) throws -> Options {
        func usage(_ message: String) -> NSError {
            NSError(domain: "MetaVisLab", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(message)\n\n" + MetaVisLabHelp.text])
        }

        var inputDir: String?
        var outDir: String?
        var secondsPer: Double = 2.0
        var transitionName: String = "crossfade"
        var transitionSeconds: Double = 0.25
        var easingName: String = "linear"
        var resolutionHeight: Int = 1080
        var frameRate: Int32 = 24
        var codec: AVVideoCodecType = .hevc
        var extractEditedEXR = true

        var i = 0
        while i < args.count {
            let a = args[i]
            switch a {
            case "--input-dir":
                i += 1
                guard i < args.count else { throw usage("Missing value for --input-dir") }
                inputDir = args[i]
            case "--out":
                i += 1
                guard i < args.count else { throw usage("Missing value for --out") }
                outDir = args[i]
            case "--seconds-per":
                i += 1
                guard i < args.count else { throw usage("Missing value for --seconds-per") }
                secondsPer = Double(args[i]) ?? secondsPer
            case "--transition":
                i += 1
                guard i < args.count else { throw usage("Missing value for --transition") }
                transitionName = args[i]
            case "--transition-seconds":
                i += 1
                guard i < args.count else { throw usage("Missing value for --transition-seconds") }
                transitionSeconds = Double(args[i]) ?? transitionSeconds
            case "--easing":
                i += 1
                guard i < args.count else { throw usage("Missing value for --easing") }
                easingName = args[i]
            case "--height":
                i += 1
                guard i < args.count else { throw usage("Missing value for --height") }
                resolutionHeight = Int(args[i]) ?? resolutionHeight
            case "--fps":
                i += 1
                guard i < args.count else { throw usage("Missing value for --fps") }
                frameRate = Int32(args[i]) ?? frameRate
            case "--codec":
                i += 1
                guard i < args.count else { throw usage("Missing value for --codec") }
                let v = args[i].lowercased()
                switch v {
                case "hevc": codec = .hevc
                case "prores4444": codec = .proRes4444
                case "prores422hq": codec = .proRes422HQ
                default:
                    throw usage("Unknown --codec: \(args[i]) (use hevc|prores4444|prores422hq)")
                }
            case "--no-extract-exr":
                extractEditedEXR = false
            case "--help", "-h":
                print(MetaVisLabHelp.text)
                throw MetaVisLabExit.success
            default:
                throw usage("Unknown arg: \(a)")
            }
            i += 1
        }

        let inputDirURL: URL
        if let inputDir {
            inputDirURL = URL(fileURLWithPath: inputDir)
        } else {
            // Convenience default for local dev: use repo assets.
            inputDirURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("assets")
                .appendingPathComponent("exr")
        }

        let easing: EasingCurve = {
            switch easingName.lowercased() {
            case "linear": return .linear
            case "easein": return .easeIn
            case "easeout": return .easeOut
            case "easeinout": return .easeInOut
            default: return .linear
            }
        }()

        let transition: Transition = {
            let d = Time(seconds: max(0.0, transitionSeconds))
            switch transitionName.lowercased() {
            case "cut", "none":
                return .cut
            case "crossfade":
                return .crossfade(duration: d, easing: easing)
            case "dip", "diptoblack":
                return .dipToBlack(duration: d)
            default:
                return .crossfade(duration: d, easing: easing)
            }
        }()
        let outputDirURL: URL
        if let outDir {
            outputDirURL = URL(fileURLWithPath: outDir)
        } else {
            outputDirURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("test_outputs")
                .appendingPathComponent("exr_timeline")
        }

        return Options(
            inputDirURL: inputDirURL,
            outputDirURL: outputDirURL,
            secondsPerImage: secondsPer,
            transition: transition,
            resolutionHeight: resolutionHeight,
            frameRate: frameRate,
            codec: codec,
            extractEditedEXR: extractEditedEXR
        )
    }
}
