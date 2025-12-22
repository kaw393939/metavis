import Foundation
import AVFoundation
import MetaVisCore
import MetaVisTimeline
import MetaVisExport
import MetaVisSimulation
import MetaVisQC

enum GeminiAnalyzeCommand {
    static func run(args: [String], io: IOContext = .default()) async throws {
        var inputPath: String?
        var outDir: String?

        var i = 0
        while i < args.count {
            switch args[i] {
            case "--input":
                i += 1
                inputPath = (i < args.count) ? args[i] : nil
            case "--out":
                i += 1
                outDir = (i < args.count) ? args[i] : nil
            case "--help", "-h":
                print(help)
                return
            default:
                break
            }
            i += 1
        }

        guard ProcessInfo.processInfo.environment["RUN_GEMINI_QC"] == "1" else {
            throw NSError(
                domain: "MetaVisLab",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Gemini network calls are gated. Re-run with RUN_GEMINI_QC=1 in the environment."]
            )
        }

        guard let inputPath else {
            print(help)
            throw NSError(domain: "MetaVisLab", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing --input <movie>"])
        }
        guard let outDir else {
            print(help)
            throw NSError(domain: "MetaVisLab", code: 4, userInfo: [NSLocalizedDescriptionKey: "Missing --out <dir>"])
        }

        let inputURL = URL(fileURLWithPath: inputPath)
        let outURL = URL(fileURLWithPath: outDir)

        try io.prepare()

        try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)

        // Governance: treat input as a deliverable unless explicitly loosened elsewhere.
        let policy = AIUsagePolicy(mode: .textImagesAndVideo, mediaSource: .deliverablesOnly)
        let privacy = PrivacyPolicy(allowRawMediaUpload: false, allowDeliverablesUpload: true)
        let usage = GeminiQC.UsageContext(policy: policy, privacy: privacy)

        let proxyURL = try await ensureInlineVideoUnderLimit(inputURL: inputURL, outDir: outURL, maxBytes: policy.maxInlineBytes)

        let duration = await probeDurationSeconds(url: proxyURL)
        let keyFrames = buildDefaultKeyFrames(durationSeconds: duration)

        let expectedNarrative = """
        You are a strict, conservative QC assistant.

        Analyze the attached 60s deliverable video and keyframes.

                Return JSON only (no markdown, no backticks, no code fences).
                The response MUST start with '{' and end with '}'.
                Use this exact shape (include every field; no extra top-level keys):
        {
                    \"accepted\": true|false,
                    \"qualityAccepted\": true|false,
                    \"summary\": {\"oneSentence\": string},
          \"audio\": {
            \"speechPresent\": true|false,
            \"speakerCountEstimate\": number,
            \"speechIntelligibility\": \"poor\"|\"ok\"|\"good\",
            \"clippingEvidence\": \"none\"|\"possible\"|\"likely\",
            \"backgroundNoise\": \"low\"|\"medium\"|\"high\",
            \"notes\": [string]
          },
          \"video\": {
            \"subjectCountEstimate\": number,
            \"framingStability\": \"stable\"|\"mostly_stable\"|\"jumpy\",
            \"jumpCutsOrTransitions\": \"none\"|\"some\"|\"many\",
            \"lighting\": \"good\"|\"mixed\"|\"problematic\",
            \"notes\": [string]
          },
          \"pipelineCalibrationHints\": {
            \"audio_clip_risk_should_fire\": true|false,
            \"audio_noise_risk_should_fire\": true|false,
            \"speech_like_segmentation_should_be_stable\": true|false,
            \"framing_jump_risk_should_fire\": true|false,
            \"notes\": [string]
          }
        }

                Semantics:
                - Set accepted=true if you can evaluate from the provided evidence (even if quality is bad).
                - Set qualityAccepted=true only if the clip meets a strict creator-quality bar.
                - If evidence is insufficient, set accepted=false and qualityAccepted=false and explain in notes.
        """

        print("gemini-analyze: input=\(inputURL.lastPathComponent)")
        print("gemini-analyze: proxy=\(proxyURL.lastPathComponent)")
        print("gemini-analyze: keyFrames=\(keyFrames.map { $0.label }.joined(separator: ", "))")

        let verdict = try await GeminiQC.acceptMulticlipExport(
            movieURL: proxyURL,
            keyFrames: keyFrames,
            expectedNarrative: expectedNarrative,
            requireKey: true,
            usage: usage
        )

        let outFile = outURL.appendingPathComponent("gemini_analysis.json")
        let rawFile = outURL.appendingPathComponent("gemini_analysis_raw.txt")
        let verdictFile = outURL.appendingPathComponent("gemini_verdict.json")

        try verdict.rawText.data(using: .utf8)?.write(to: rawFile)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(verdict)
            try data.write(to: verdictFile, options: [.atomic])
        } catch {}

        let cleaned = extractFirstJSONObject(from: verdict.rawText) ?? verdict.rawText
        try cleaned.data(using: .utf8)?.write(to: outFile)

        print("gemini-analyze: wrote \(outFile.path)")
        print("gemini-analyze: accepted=\(verdict.accepted)")
    }

    private static func extractFirstJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        guard let end = text.lastIndex(of: "}") else { return nil }
        guard start < end else { return nil }
        return String(text[start...end])
    }

    private static func ensureInlineVideoUnderLimit(inputURL: URL, outDir: URL, maxBytes: Int) async throws -> URL {
        let dataSize = (try? FileManager.default.attributesOfItem(atPath: inputURL.path)[.size] as? NSNumber)?.intValue ?? 0
        if dataSize > 0 && dataSize <= maxBytes {
            return inputURL
        }

        print("gemini-analyze: proxying video to fit inline limit (maxInlineBytes=\(maxBytes))")

        // Create a small proxy (~60s, ~360p, low bitrate) to fit inside inline limits.
        // This path must not rely on external binaries.
        let proxyURL = outDir.appendingPathComponent("gemini_proxy_360p_60s.mp4")

        let asset = AVURLAsset(url: inputURL)
        var durationSeconds: Double = 60.0
        do {
            let d = try await asset.load(.duration)
            durationSeconds = max(0.0, d.isNumeric ? d.seconds : 0.0)
        } catch {
            durationSeconds = 60.0
        }
        let exportSeconds = max(0.5, min(60.0, durationSeconds > 0 ? durationSeconds : 60.0))

        let assetRef = AssetReference(sourceFn: inputURL.absoluteString)
        let clipDuration = Time(seconds: exportSeconds)
        let clip = Clip(name: "Proxy", asset: assetRef, startTime: .zero, duration: clipDuration, offset: .zero)

        // Include both video + audio so Gemini can evaluate speech/quality when available.
        let timeline = Timeline(
            tracks: [
                Track(name: "Video", kind: .video, clips: [clip]),
                Track(name: "Audio", kind: .audio, clips: [clip])
            ],
            duration: clipDuration
        )

        // Export using engine pipeline.
        let engine = try MetalSimulationEngine()
        try await engine.configure()

        let trace = StdoutTraceSink()
        let exporter = VideoExporter(engine: engine, trace: trace)

        // Try a few increasingly aggressive settings to fit the inline budget.
        let attempts: [(height: Int, videoBitrate: Int, audioBitrate: Int)] = [
            (360, 900_000, 96_000),
            (360, 600_000, 64_000),
            (240, 450_000, 48_000)
        ]

        for (idx, a) in attempts.enumerated() {
            let quality = QualityProfile(name: "GeminiProxy\(a.height)", fidelity: .draft, resolutionHeight: a.height, colorDepth: 8)
            let encoding = EncodingProfile.proxy(frameRate: 24, maxVideoBitRate: a.videoBitrate, audioBitRate: a.audioBitrate)

            // Ensure we're not appending to a previous attempt.
            if FileManager.default.fileExists(atPath: proxyURL.path) {
                try? FileManager.default.removeItem(at: proxyURL)
            }

            try await exporter.export(
                timeline: timeline,
                to: proxyURL,
                quality: quality,
                frameRate: 24,
                codec: .hevc,
                encodingProfile: encoding,
                audioPolicy: .auto,
                governance: .none
            )

            let proxySize = (try? FileManager.default.attributesOfItem(atPath: proxyURL.path)[.size] as? NSNumber)?.intValue ?? 0
            if proxySize > 0 && proxySize <= maxBytes {
                if idx > 0 {
                    print("gemini-analyze: proxy fit budget after \(idx + 1) attempts (bytes=\(proxySize))")
                }
                return proxyURL
            }
        }

        let proxySize = (try? FileManager.default.attributesOfItem(atPath: proxyURL.path)[.size] as? NSNumber)?.intValue ?? 0
        throw NSError(
            domain: "MetaVisLab",
            code: 11,
            userInfo: [NSLocalizedDescriptionKey: "Proxy video is still too large for inline upload (\(proxySize) bytes > \(maxBytes)). Reduce the budget, implement chunked upload, or add a more aggressive proxy profile."]
        )
    }

    private static func probeDurationSeconds(url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        do {
            let dur = try await asset.load(.duration)
            return max(0.0, dur.seconds)
        } catch {
            return 60.0
        }
    }

    private static func buildDefaultKeyFrames(durationSeconds: Double) -> [GeminiQC.KeyFrame] {
        let d = max(0.0, durationSeconds)
        let safeEnd = max(0.5, min(59.0, d > 0 ? (d - 0.5) : 59.0))

        // A few evenly spaced snapshots over the first minute.
        let times: [(Double, String)] = [
            (0.5, "START"),
            (10.0, "T10"),
            (20.0, "T20"),
            (30.0, "T30"),
            (40.0, "T40"),
            (50.0, "T50"),
            (safeEnd, "END")
        ]

        return times.map { GeminiQC.KeyFrame(timeSeconds: min($0.0, safeEnd), label: $0.1) }
    }

    private static let help = """
    gemini-analyze

    Runs a Gemini multimodal analysis for a short deliverable clip.

    Usage:
      RUN_GEMINI_QC=1 GEMINI_API_KEY=... MetaVisLab gemini-analyze --input <movie.mov> --out <dir>

    Output:
      Writes <out>/gemini_analysis.json

    Notes:
      If the input is larger than the inline upload limit (default 20MB), a 60s ~360p proxy is generated and uploaded instead.
    """
}
