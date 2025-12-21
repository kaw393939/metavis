import Foundation
import AVFoundation
import MetaVisCore
import MetaVisTimeline
import MetaVisSession
import MetaVisSimulation
import MetaVisExport

enum FITSTimelineCommand {
    struct Options {
        var inputDirURL: URL
        var outputDirURL: URL
        var secondsPerImage: Double
        var transition: Transition
        var colorMode: ColorMode
        var colorExposure: Double
        var colorGamma: Double
        var resolutionHeight: Int
        var frameRate: Int
        var codec: AVVideoCodecType
        var extractEditedEXR: Bool
    }

    enum ColorMode: String {
        case gray
        case turbo
    }

    static func run(args: [String]) async throws {
        let options = try parse(args: args)
        try await run(options: options)
    }

    static func run(options: Options) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: options.outputDirURL, withIntermediateDirectories: true)

        let fitsURLs = try fm.contentsOfDirectory(at: options.inputDirURL, includingPropertiesForKeys: nil)
            .filter {
                let ext = $0.pathExtension.lowercased()
                return ext == "fits" || ext == "fit"
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        guard !fitsURLs.isEmpty else {
            throw NSError(domain: "MetaVisLab", code: 450, userInfo: [NSLocalizedDescriptionKey: "No .fits files found in: \(options.inputDirURL.path)"])
        }

        // 1) Build a Timeline: one clip per FITS still
        // Important: ProjectSession's current reducer does not auto-update timeline.duration.
        // Construct a fully formed Timeline with explicit duration.
        let dur = max(0.1, options.secondsPerImage)
        let trans = options.transition

        var clips: [Clip] = []
        clips.reserveCapacity(fitsURLs.count)

        var t = Time.zero
        for (idx, url) in fitsURLs.enumerated() {
            let assetRef = AssetReference(sourceFn: url.absoluteURL.absoluteString)

            let effects: [FeatureApplication] = {
                switch options.colorMode {
                case .gray:
                    return []
                case .turbo:
                    return [
                        .init(
                            id: "com.metavis.fx.false_color.turbo",
                            parameters: [
                                "exposure": .float(options.colorExposure),
                                "gamma": .float(options.colorGamma)
                            ]
                        )
                    ]
                }
            }()

            let isFirst = (idx == 0)
            let isLast = (idx == fitsURLs.count - 1)
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

        let track = Track(name: "FITS Track", kind: .video, clips: clips)
        let timeline = Timeline(tracks: [track], duration: t)

        let license = ProjectLicense(ownerId: "lab", maxExportResolution: 4320, requiresWatermark: false, allowOpenEXR: options.extractEditedEXR)
        let config = ProjectConfig(name: "FITS Timeline", license: license)
        let session = ProjectSession(initialState: ProjectState(timeline: timeline, config: config))

        // 2) Persist timeline JSON (useful for inspection)
        let state = await session.state
        let timelineURL = options.outputDirURL.appendingPathComponent("timeline.json")
        try JSONWriting.write(state.timeline, to: timelineURL)

        // 3) Export movie
        let engine = try MetalSimulationEngine()
        let exporter = VideoExporter(engine: engine, trace: StdoutTraceSink())
        let outputMovieURL = options.outputDirURL.appendingPathComponent("fits_timeline.mov")
        let quality = QualityProfile(name: "FITSTimeline", fidelity: .high, resolutionHeight: options.resolutionHeight, colorDepth: 10)

        print("⏳ Exporting FITS timeline…")
        try await session.exportMovie(
            using: exporter,
            to: outputMovieURL,
            quality: quality,
            frameRate: options.frameRate,
            codec: options.codec,
            audioPolicy: .forbidden
        )
        print("✅ Exported: \(outputMovieURL.path)")

        // 4) Optional: extract per-clip midpoint frames as EXR (edited output)
        if options.extractEditedEXR {
            let framesDir = options.outputDirURL.appendingPathComponent("edited_exr", isDirectory: true)
            try fm.createDirectory(at: framesDir, withIntermediateDirectories: true)

            print("⏳ Extracting edited EXRs…")

            let timelineSeconds = timeline.duration.seconds

            for (idx, url) in fitsURLs.enumerated() {
                let clipStart = clips[idx].startTime.seconds
                // Use the actual clip start time to account for transition overlaps.
                var mid = clipStart + (dur * 0.5)
                // Clamp to the export duration to avoid requesting frames past EOF.
                if timelineSeconds.isFinite {
                    mid = min(mid, max(0.0, timelineSeconds - (1.0 / Double(max(1, options.frameRate)))))
                }
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
            "-nostdin",
            "-v", "error",
            "-ss", String(format: "%.6f", max(0.0, atSeconds)),
            "-i", inputMovieURL.path,
            "-frames:v", "1",
            "-y",
            outEXRURL.path
        ]

        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        p.waitUntilExit()

        guard p.terminationStatus == 0 else {
            let outMsg = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let errMsg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let msg = ([outMsg, errMsg].filter { !$0.isEmpty }).joined(separator: "\n")
            throw NSError(domain: "MetaVisLab", code: 451, userInfo: [NSLocalizedDescriptionKey: "ffmpeg frame extract failed: \(msg)"])
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
        var transitionName: String = "cut"
        var transitionSeconds: Double = 0.25
        var easingName: String = "linear"
        var colorModeName: String = "gray"
        var colorExposure: Double = 0.0
        var colorGamma: Double = 1.0
        var resolutionHeight: Int = 1080
        var frameRate: Int = 24
        var codec: AVVideoCodecType = .hevc
        var extractEditedEXR = false

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
            case "--color":
                i += 1
                guard i < args.count else { throw usage("Missing value for --color") }
                colorModeName = args[i]
            case "--color-exposure":
                i += 1
                guard i < args.count else { throw usage("Missing value for --color-exposure") }
                colorExposure = Double(args[i]) ?? colorExposure
            case "--color-gamma":
                i += 1
                guard i < args.count else { throw usage("Missing value for --color-gamma") }
                colorGamma = Double(args[i]) ?? colorGamma
            case "--height":
                i += 1
                guard i < args.count else { throw usage("Missing value for --height") }
                resolutionHeight = Int(args[i]) ?? resolutionHeight
            case "--fps":
                i += 1
                guard i < args.count else { throw usage("Missing value for --fps") }
                frameRate = Int(args[i]) ?? frameRate
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
            case "--extract-exr":
                extractEditedEXR = true
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
            // Convenience default for local dev: use repo test assets.
            inputDirURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Tests")
                .appendingPathComponent("Assets")
                .appendingPathComponent("fits")
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
                return .cut
            }
        }()

        let outputDirURL: URL
        if let outDir {
            outputDirURL = URL(fileURLWithPath: outDir)
        } else {
            outputDirURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("test_outputs")
                .appendingPathComponent("fits_timeline")
        }

        guard let colorMode = ColorMode(rawValue: colorModeName.lowercased()) else {
            throw usage("Unknown --color: \(colorModeName) (use gray|turbo)")
        }

        // Clamp into the manifest’s declared ranges to keep behavior predictable.
        colorExposure = min(10.0, max(-10.0, colorExposure))
        colorGamma = min(4.0, max(0.1, colorGamma))

        return Options(
            inputDirURL: inputDirURL,
            outputDirURL: outputDirURL,
            secondsPerImage: secondsPer,
            transition: transition,
            colorMode: colorMode,
            colorExposure: colorExposure,
            colorGamma: colorGamma,
            resolutionHeight: resolutionHeight,
            frameRate: frameRate,
            codec: codec,
            extractEditedEXR: extractEditedEXR
        )
    }
}
