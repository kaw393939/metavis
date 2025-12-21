import Foundation
import AVFoundation
import MetaVisCore
import MetaVisQC

enum GeminiAnalyzeCommand {
    static func run(args: [String]) async throws {
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

        try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)

        // Governance: treat input as a deliverable unless explicitly loosened elsewhere.
        let policy = AIUsagePolicy(mode: .textImagesAndVideo, mediaSource: .deliverablesOnly)
        let privacy = PrivacyPolicy(allowRawMediaUpload: false, allowDeliverablesUpload: true)
        let usage = GeminiQC.UsageContext(policy: policy, privacy: privacy)

        let proxyURL = try ensureInlineVideoUnderLimit(inputURL: inputURL, outDir: outURL, maxBytes: policy.maxInlineBytes)

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

    private static func ensureInlineVideoUnderLimit(inputURL: URL, outDir: URL, maxBytes: Int) throws -> URL {
        let dataSize = (try? FileManager.default.attributesOfItem(atPath: inputURL.path)[.size] as? NSNumber)?.intValue ?? 0
        if dataSize > 0 && dataSize <= maxBytes {
            return inputURL
        }

        // Create a small proxy (~360p, low bitrate) to fit inside inline limits.
        let proxyURL = outDir.appendingPathComponent("gemini_proxy_360p_60s.mp4")

        let args: [String] = [
            "ffmpeg",
            "-y",
            "-i", inputURL.path,
            "-t", "60",
            "-vf", "scale='min(640,iw)':-2",
            "-c:v", "libx264",
            "-profile:v", "baseline",
            "-level", "3.0",
            "-pix_fmt", "yuv420p",
            "-b:v", "900k",
            "-maxrate", "1200k",
            "-bufsize", "2400k",
            "-c:a", "aac",
            "-b:a", "96k",
            "-ac", "2",
            "-movflags", "+faststart",
            proxyURL.path
        ]

        print("gemini-analyze: proxying video to fit inline limit (maxInlineBytes=\(maxBytes))")
        try runProcess("/usr/bin/env", args)

        let proxySize = (try? FileManager.default.attributesOfItem(atPath: proxyURL.path)[.size] as? NSNumber)?.intValue ?? 0
        if proxySize <= 0 {
            throw NSError(domain: "MetaVisLab", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed to create proxy video"])
        }
        if proxySize > maxBytes {
            throw NSError(
                domain: "MetaVisLab",
                code: 11,
                userInfo: [NSLocalizedDescriptionKey: "Proxy video is still too large for inline upload (\(proxySize) bytes > \(maxBytes)). Lower bitrate further or implement file-URI upload."]
            )
        }

        return proxyURL
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

    private static func runProcess(_ executable: String, _ args: [String]) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        try proc.run()
        proc.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
            // ffmpeg writes progress to stderr; forward it for debugging.
            print(text)
        }

        if proc.terminationStatus != 0 {
            throw NSError(domain: "MetaVisLab", code: 12, userInfo: [NSLocalizedDescriptionKey: "Process failed: \(args.prefix(1).joined()) (status=\(proc.terminationStatus))"])
        }
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
