import Foundation

enum PerfLogger {

    struct PerfEvent: Codable {
        enum Status: String, Codable {
            case ok
            case failed
            case skipped
        }

        var timestampISO8601: String
        var runID: String

        var suite: String
        var test: String

        var label: String
        var width: Int
        var height: Int
        var frames: Int

        var avgMs: Double?
        var peakRSSDeltaMB: Double?

        // Optional correctness tracking (non-breaking extensions).
        // Used by perf sweeps when METAVIS_PERF_QC_BASELINES=1.
        var qcFingerprintHash: String?
        var qcMeanRGB: [Double]?
        var qcStdRGB: [Double]?
        var qcSamples: Int?
        var qcBaselineDistance: Double?
        var qcBaselineStatus: String?

        // Optional color certification metrics (e.g., Macbeth chart).
        var deltaE2000Avg: Double?
        var deltaE2000Max: Double?
        var deltaEWorstPatch: String?

        // Optional: Studio LUT GPU-vs-CPU reference match metrics.
        var lutMeanAbsErr: Double?
        var lutMaxAbsErr: Double?
        var lutWorstPatch: String?

        // Optional: OCIO re-bake vs committed LUT match metrics.
        var ocioBakeName: String?
        var ocioBakeMeanAbsErr: Double?
        var ocioBakeMaxAbsErr: Double?

        var status: Status
        var message: String?

        var osVersion: String
        var processArch: String
    }

    private static let lock = NSLock()
    private static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.withoutEscapingSlashes]
        return enc
    }()

    static func isEnabled() -> Bool {
        ProcessInfo.processInfo.environment["METAVIS_PERF_LOG"] == "1"
    }

    static func runID() -> String {
        if let v = ProcessInfo.processInfo.environment["METAVIS_PERF_RUN_ID"], !v.isEmpty {
            return v
        }
        // ISO8601-like but filesystem-friendly.
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: Date())
    }

    static func defaultLogPath() -> String {
        // Package root in `swift test` is typically currentDirectoryPath.
        let cwd = FileManager.default.currentDirectoryPath
        return (cwd as NSString).appendingPathComponent("test_outputs/perf/perf.jsonl")
    }

    static func logPath() -> String {
        if let p = ProcessInfo.processInfo.environment["METAVIS_PERF_LOG_PATH"], !p.isEmpty {
            return p
        }
        return defaultLogPath()
    }

    static func makeBaseEvent(
        suite: String,
        test: String,
        label: String,
        width: Int,
        height: Int,
        frames: Int
    ) -> PerfEvent {
        let iso = ISO8601DateFormatter().string(from: Date())
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let arch = archString()

        return PerfEvent(
            timestampISO8601: iso,
            runID: runID(),
            suite: suite,
            test: test,
            label: label,
            width: width,
            height: height,
            frames: frames,
            avgMs: nil,
            peakRSSDeltaMB: nil,
            qcFingerprintHash: nil,
            qcMeanRGB: nil,
            qcStdRGB: nil,
            qcSamples: nil,
            qcBaselineDistance: nil,
            qcBaselineStatus: nil,
            deltaE2000Avg: nil,
            deltaE2000Max: nil,
            deltaEWorstPatch: nil,
            lutMeanAbsErr: nil,
            lutMaxAbsErr: nil,
            lutWorstPatch: nil,
            ocioBakeName: nil,
            ocioBakeMeanAbsErr: nil,
            ocioBakeMaxAbsErr: nil,
            status: .ok,
            message: nil,
            osVersion: os,
            processArch: arch
        )
    }

    static func write(_ event: PerfEvent) {
        guard isEnabled() else { return }

        lock.lock()
        defer { lock.unlock() }

        let path = logPath()
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        guard let data = try? encoder.encode(event) else { return }
        guard var line = String(data: data, encoding: .utf8) else { return }
        line.append("\n")

        if FileManager.default.fileExists(atPath: path) {
            if let fh = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
                defer { try? fh.close() }
                _ = try? fh.seekToEnd()
                if let d = line.data(using: .utf8) {
                    try? fh.write(contentsOf: d)
                }
            }
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    static func writeMarkdownSummary(_ markdown: String, fileName: String = "last_run.md") {
        guard isEnabled() else { return }
        let cwd = FileManager.default.currentDirectoryPath
        let path = (cwd as NSString).appendingPathComponent("test_outputs/perf/\(fileName)")
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? markdown.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private static func archString() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
