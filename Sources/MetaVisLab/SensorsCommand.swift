import Foundation
import MetaVisCore
import MetaVisPerception

enum SensorsCommand {

    static func run(args: [String]) async throws {
        guard let sub = args.first else {
            throw NSError(domain: "MetaVisLab", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing subcommand. Try: MetaVisLab sensors ingest --help"]) 
        }

        switch sub {
        case "ingest":
            try await SensorsIngestCommand.run(args: Array(args.dropFirst()))
        case "--help", "-h", "help":
            print(SensorsHelp.text)
        default:
            let msg = "Unknown sensors subcommand: \(sub)"
            print(msg)
            print("")
            print(SensorsHelp.text)
            throw NSError(domain: "MetaVisLab", code: 2, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }
}

enum SensorsHelp {
    static let text = """
    MetaVisLab sensors

    Usage:
    MetaVisLab sensors ingest --input <movie.mov> --out <dir> [--stride <s>] [--max-video-seconds <s>] [--audio-seconds <s>] [--emit-bites] [--allow-large]

    Detector flags (optional):
      --enable <face|segment|audio|warnings|descriptors|autostart>
      --disable <face|segment|audio|warnings|descriptors|autostart>

    Notes:
      - If any --enable is provided, only those detectors are enabled (others default to disabled).
      - If you only use --disable, all detectors default to enabled.
            - Output is written to <out>/sensors.json (see printed schemaVersion).
            - If --emit-bites is provided, output also includes <out>/bites.v1.json.
    """
}

enum SensorsIngestCommand {

    struct Options: Sendable {
        var inputMovieURL: URL
        var outputDirURL: URL
        var strideSeconds: Double
        var maxVideoSeconds: Double
        var audioSeconds: Double
        var emitBites: Bool
        var allowLarge: Bool

        var enableFaces: Bool
        var enableSegmentation: Bool
        var enableAudio: Bool
        var enableWarnings: Bool
        var enableDescriptors: Bool
        var enableAutoStart: Bool
    }

    static func run(args: [String]) async throws {
        if args.first == "--help" || args.first == "-h" {
            print(SensorsHelp.text)
            return
        }
        let options = try parse(args: args)
        try await run(options: options)
    }

    static func run(options: Options) async throws {
        // Preflight: fail fast with a clear message when the input file is missing (common with broken symlinks).
        if options.inputMovieURL.isFileURL {
            let path = options.inputMovieURL.path
            if !FileManager.default.fileExists(atPath: path) {
                var msg = "Input movie not found: \(path)"
                // Helpful hint for the common local fixture.
                if path.lowercased().hasSuffix("keith_talk.mov") {
                    let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                        .appendingPathComponent("Tests/Assets/VideoEdit/keith_talk.mov")
                        .standardizedFileURL
                    if FileManager.default.fileExists(atPath: fixture.path) {
                        msg += "\nHint: Use the fixture at: \(fixture.path)"
                    }
                }
                throw NSError(domain: "MetaVisLab", code: 2, userInfo: [NSLocalizedDescriptionKey: msg])
            }
        }

        try enforceLargeAssetPolicy(inputURL: options.inputMovieURL, allowLarge: options.allowLarge)

        let fm = FileManager.default
        try fm.createDirectory(at: options.outputDirURL, withIntermediateDirectories: true)

        let ingestor = MasterSensorIngestor(
            .init(
                videoStrideSeconds: options.strideSeconds,
                maxVideoSeconds: options.maxVideoSeconds,
                audioAnalyzeSeconds: options.audioSeconds,
                enableFaces: options.enableFaces,
                enableSegmentation: options.enableSegmentation,
                enableAudio: options.enableAudio,
                enableWarnings: options.enableWarnings,
                enableDescriptors: options.enableDescriptors,
                enableSuggestedStart: options.enableAutoStart
            )
        )

        let sensors = try await ingestor.ingest(url: options.inputMovieURL)

        let sensorsURL = options.outputDirURL.appendingPathComponent("sensors.json")
        try JSONWriting.write(sensors, to: sensorsURL)

        if options.emitBites {
            let bites = BiteMapBuilder.build(from: sensors)
            let bitesURL = options.outputDirURL.appendingPathComponent("bites.v1.json")
            try JSONWriting.write(bites, to: bitesURL)
            print("✅ Wrote bites.v1.json: \(bitesURL.path)")
            print("   - schemaVersion: \(bites.schemaVersion)")
            print("   - bites: \(bites.bites.count)")
        }

        print("✅ Wrote sensors.json: \(sensorsURL.path)")
        print("   - schemaVersion: \(sensors.schemaVersion)")
        print("   - analyzedSeconds: \(String(format: "%.3f", sensors.summary.analyzedSeconds))")
        print("   - videoSamples: \(sensors.videoSamples.count)")
        print("   - audioSegments: \(sensors.audioSegments.count)")
        print("   - warnings: \(sensors.warnings.count)")
        print("   - descriptors: \(sensors.descriptors?.count ?? 0)")
        if let s = sensors.suggestedStart {
            print("   - suggestedStart: \(String(format: "%.3f", s.time)) (conf \(String(format: "%.2f", s.confidence)))")
        }
    }

    enum Detector: String, CaseIterable {
        case face
        case segment
        case audio
        case warnings
        case descriptors
        case autostart
    }

    private static func parse(args: [String]) throws -> Options {
        var inputPath: String?
        var outPath: String?

        var strideSeconds: Double = 0.5
        var maxVideoSeconds: Double = 10.0
        var audioSeconds: Double = 10.0
        var emitBites: Bool = false
        var allowLarge: Bool = false

        var sawEnable = false
        var enableSet = Set<Detector>()
        var disableSet = Set<Detector>()

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
            case "--input":
                i += 1; if i < args.count { inputPath = args[i] }
            case "--out":
                i += 1; if i < args.count { outPath = args[i] }
            case "--stride":
                i += 1; if i < args.count { strideSeconds = try parseDouble(args[i], "--stride") }
            case "--max-video-seconds":
                i += 1; if i < args.count { maxVideoSeconds = try parseDouble(args[i], "--max-video-seconds") }
            case "--audio-seconds":
                i += 1; if i < args.count { audioSeconds = try parseDouble(args[i], "--audio-seconds") }
            case "--emit-bites":
                emitBites = true
            case "--allow-large":
                allowLarge = true
            case "--enable":
                i += 1
                guard i < args.count, let d = Detector(rawValue: args[i]) else {
                    throw NSError(domain: "MetaVisLab", code: 2, userInfo: [NSLocalizedDescriptionKey: "--enable requires one of: face|segment|audio|warnings|descriptors|autostart"])
                }
                sawEnable = true
                enableSet.insert(d)
            case "--disable":
                i += 1
                guard i < args.count, let d = Detector(rawValue: args[i]) else {
                    throw NSError(domain: "MetaVisLab", code: 2, userInfo: [NSLocalizedDescriptionKey: "--disable requires one of: face|segment|audio|warnings|descriptors|autostart"])
                }
                disableSet.insert(d)
            default:
                break
            }
            i += 1
        }

        guard let inputPath else {
            throw NSError(domain: "MetaVisLab", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing required flag: --input <movie.mov>"])
        }
        guard let outPath else {
            throw NSError(domain: "MetaVisLab", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing required flag: --out <dir>"])
        }

        func absoluteFileURL(_ path: String) -> URL {
            if path.hasPrefix("/") {
                return URL(fileURLWithPath: path).standardizedFileURL
            }
            let cwd = FileManager.default.currentDirectoryPath
            return URL(fileURLWithPath: cwd)
                .appendingPathComponent(path)
                .standardizedFileURL
        }

        let enabled: Set<Detector> = sawEnable ? enableSet : Set(Detector.allCases)

        func isOn(_ d: Detector) -> Bool {
            if !enabled.contains(d) { return false }
            if disableSet.contains(d) { return false }
            return true
        }

        return Options(
            inputMovieURL: absoluteFileURL(inputPath),
            outputDirURL: absoluteFileURL(outPath),
            strideSeconds: max(0.05, strideSeconds),
            maxVideoSeconds: max(0.0, maxVideoSeconds),
            audioSeconds: max(0.0, audioSeconds),
            emitBites: emitBites,
            allowLarge: allowLarge,
            enableFaces: isOn(.face),
            enableSegmentation: isOn(.segment),
            enableAudio: isOn(.audio),
            enableWarnings: isOn(.warnings),
            enableDescriptors: isOn(.descriptors),
            enableAutoStart: isOn(.autostart)
        )
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
                userInfo: [NSLocalizedDescriptionKey: "Refusing to ingest large asset (\(name), \(sizeBytes) bytes) without --allow-large."]
            )
        }
    }
}
