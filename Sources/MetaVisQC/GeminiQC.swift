import Foundation
import AVFoundation
import MetaVisServices
import MetaVisCore

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

#if canImport(ImageIO)
import ImageIO
#endif

import CoreGraphics

public enum GeminiQC {
    public struct KeyFrame: Sendable {
        public var timeSeconds: Double
        public var label: String
        public init(timeSeconds: Double, label: String) {
            self.timeSeconds = timeSeconds
            self.label = label
        }
    }

    public struct Verdict: Sendable, Codable, Equatable {
        public var accepted: Bool
        public var rawText: String
        public var model: String?

        public init(accepted: Bool, rawText: String, model: String? = nil) {
            self.accepted = accepted
            self.rawText = rawText
            self.model = model
        }
    }

    public struct UsageContext: Sendable {
        public var policy: AIUsagePolicy
        public var privacy: PrivacyPolicy

        public init(policy: AIUsagePolicy = .localOnlyDefault, privacy: PrivacyPolicy = PrivacyPolicy()) {
            self.policy = policy
            self.privacy = privacy
        }
    }

    /// Extract a few keyframes and ask Gemini to validate the expected content.
    ///
    /// This is intended as an *additional* acceptance layer on top of deterministic `VideoQC` checks.
    public static func acceptMulticlipExport(
        movieURL: URL,
        keyFrames: [KeyFrame],
        expectedNarrative: String,
        requireKey: Bool = true,
        usage: UsageContext = UsageContext()
    ) async throws -> Verdict {
        DotEnvLoader.loadIfPresent()

        // Default posture: local-only unless explicitly enabled by policy.
        if !usage.policy.allowsNetworkRequests(privacy: usage.privacy) {
            return Verdict(accepted: true, rawText: "SKIPPED (AIUsagePolicy disallows network/media)", model: nil)
        }

        // If no key is present and caller doesn't require it, skip.
        let hasKey = getenv("GEMINI_API_KEY") != nil || getenv("API__GOOGLE_API_KEY") != nil || getenv("GOOGLE_API_KEY") != nil
        if !hasKey {
            if requireKey {
                throw GeminiError.misconfigured("GEMINI_API_KEY (or API__GOOGLE_API_KEY) not present in environment")
            }
            return Verdict(accepted: true, rawText: "SKIPPED (no GEMINI_API_KEY)", model: nil)
        }

        var notes: [String] = []
        var evidence = GeminiPromptBuilder.Evidence()

        // Local hard gate: if the deliverable looks like a black screen, do not upload media.
        // This keeps Gemini QC from consuming/accepting meaningless evidence.
        if usage.policy.allowsImages(privacy: usage.privacy) || usage.policy.allowsVideo(privacy: usage.privacy) {
            let gate = await localMediaGate(movieURL: movieURL, keyFrames: keyFrames)
            if gate.shouldBlockMediaUpload {
                return Verdict(
                    accepted: false,
                    rawText: "REJECTED (local QC gate): \(gate.reason)",
                    model: nil
                )
            }
            if !gate.notes.isEmpty {
                notes.append(contentsOf: gate.notes)
            }
        }

        // Attach keyframe JPEGs only when explicitly allowed by policy + privacy.
        if usage.policy.allowsImages(privacy: usage.privacy) {
            let images = try extractJPEGs(assetURL: movieURL, frames: keyFrames)
            for img in images {
                guard let data = Data(base64Encoded: img.jpegBase64) else {
                    continue
                }
                evidence.inline.append(.init(
                    label: "FRAME: \(img.label) @ \(String(format: "%.3f", img.timeSeconds))s",
                    mimeType: "image/jpeg",
                    data: data
                ))
            }
        } else {
            notes.append("Images not attached (policy/privacy)")
        }

        // Attach video evidence only when explicitly allowed.
        if usage.policy.allowsVideo(privacy: usage.privacy) {
            do {
                let data = try Data(contentsOf: movieURL)
                if data.count <= usage.policy.maxInlineBytes {
                    let mime = mimeTypeForMovie(url: movieURL)
                    evidence.inline.append(.init(
                        label: "VIDEO: \(GeminiPromptBuilder.redactedFileName(from: movieURL, policy: usage.policy)) (\(data.count) bytes)",
                        mimeType: mime,
                        data: data
                    ))
                } else {
                    notes.append("Video not attached: file is \(data.count) bytes > maxInlineBytes=\(usage.policy.maxInlineBytes). Use file URIs (gs:// or https://) or implement Files API upload.")
                }
            } catch {
                notes.append("Video not attached: failed to read movie bytes")
            }
        } else {
            notes.append("Video not attached (policy/privacy)")
        }

        let metrics = await readDeterministicMetrics(movieURL: movieURL)

        let config = try GeminiConfig.fromEnvironment()
        let client = GeminiClient(config: config)

        let context = GeminiPromptBuilder.PromptContext(
            expectedNarrative: expectedNarrative,
            keyFrameLabels: keyFrames.map { $0.label },
            policy: usage.policy,
            privacy: usage.privacy,
            modelHint: config.model,
            metrics: metrics
        )

        let prompt = GeminiPromptBuilder.buildPrompt(context, notes: notes)
        let body = GeminiPromptBuilder.buildRequest(prompt: prompt, evidence: evidence)

        let response = try await client.generateContent(body)
        let text = response.primaryText ?? ""

        // Parse minimal JSON acceptance
        let accepted = parseAcceptedFlag(from: text) ?? false
        return Verdict(accepted: accepted, rawText: text, model: config.model)
    }

    private struct LocalGateResult {
        var shouldBlockMediaUpload: Bool
        var reason: String
        var notes: [String]
    }

    private static func localMediaGate(movieURL: URL, keyFrames: [KeyFrame]) async -> LocalGateResult {
        // Conservative: only gate when we can confidently say it's essentially black.
        let times = keyFrames.map { VideoContentQC.ColorStatsSample(
            timeSeconds: $0.timeSeconds,
            label: $0.label,
            minMeanLuma: 0.0,
            maxMeanLuma: 1.0,
            maxChannelDelta: 1.0,
            minLowLumaFraction: 0.0,
            minHighLumaFraction: 0.0
        ) }

        do {
            let results = try await VideoContentQC.validateColorStats(movieURL: movieURL, samples: times)
            // Gate thresholds: mean luma near 0 and nearly all pixels in low bins.
            // (We use tolerant thresholds to avoid false positives on dark content.)
            let looksBlack = results.contains { r in
                r.meanLuma < 0.01 && r.lowLumaFraction > 0.98
            }

            if looksBlack {
                return LocalGateResult(
                    shouldBlockMediaUpload: true,
                    reason: "deliverable appears near-black at one or more keyframes (meanLuma < 0.01, lowLumaFraction > 0.98)",
                    notes: ["LOCAL_QC: blocked media upload due to near-black frames"]
                )
            }

            return LocalGateResult(
                shouldBlockMediaUpload: false,
                reason: "",
                notes: []
            )
        } catch {
            // If we can't compute stats, don't block by default; just record a note.
            return LocalGateResult(
                shouldBlockMediaUpload: false,
                reason: "",
                notes: ["LOCAL_QC: unable to compute color stats for gate (\(error))"]
            )
        }
    }

    private struct EncodedFrame {
        var timeSeconds: Double
        var label: String
        var jpegBase64: String
    }

    private static func extractJPEGs(assetURL: URL, frames: [KeyFrame]) throws -> [EncodedFrame] {
        let asset = AVURLAsset(url: assetURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 512, height: 512)

        var out: [EncodedFrame] = []
        for frame in frames {
            let time = CMTime(seconds: frame.timeSeconds, preferredTimescale: 600)
            var actual = CMTime.zero
            let cg = try generator.copyCGImage(at: time, actualTime: &actual)
            let jpeg = try jpegData(from: cg, quality: 0.75)
            out.append(EncodedFrame(timeSeconds: frame.timeSeconds, label: frame.label, jpegBase64: jpeg.base64EncodedString()))
        }
        return out
    }

    private static func jpegData(from cgImage: CGImage, quality: CGFloat) throws -> Data {
        #if canImport(ImageIO)
        let data = NSMutableData()
        #if canImport(UniformTypeIdentifiers)
        let typeIdentifier = UTType.jpeg.identifier as CFString
        #else
        let typeIdentifier = "public.jpeg" as CFString
        #endif
        guard let dest = CGImageDestinationCreateWithData(data, typeIdentifier, 1, nil) else {
            throw NSError(domain: "MetaVisQC", code: 20, userInfo: [NSLocalizedDescriptionKey: "Failed to create JPEG destination"]) 
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "MetaVisQC", code: 21, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize JPEG"]) 
        }
        return data as Data
        #else
        throw NSError(domain: "MetaVisQC", code: 22, userInfo: [NSLocalizedDescriptionKey: "ImageIO not available"]) 
        #endif
    }

    private static func parseAcceptedFlag(from text: String) -> Bool? {
        // Simple robust extraction: find first { ... } and decode as JSON.
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return nil }
        let json = String(text[start...end])
        guard let data = json.data(using: .utf8) else { return nil }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let accepted = obj["accepted"] as? Bool {
            return accepted
        }
        return nil
    }

    private static func mimeTypeForMovie(url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "mp4", "m4v":
            return "video/mp4"
        case "mov", "qt":
            return "video/quicktime"
        default:
            return "video/quicktime"
        }
    }

    private static func readDeterministicMetrics(movieURL: URL) async -> GeminiPromptBuilder.PromptContext.DeterministicMetrics {
        #if canImport(AVFoundation)
        let asset = AVURLAsset(url: movieURL)
        do {
            let duration = try await asset.load(.duration)
            let seconds = duration.isNumeric ? duration.seconds : nil

            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else {
                return .init(durationSeconds: seconds)
            }

            let fps = Double(try await track.load(.nominalFrameRate))
            let size = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let rect = CGRect(origin: .zero, size: size).applying(transform)
            let w = Int(abs(rect.width).rounded())
            let h = Int(abs(rect.height).rounded())

            return .init(
                durationSeconds: seconds,
                nominalFPS: fps.isFinite && fps > 0 ? fps : nil,
                width: (w > 0 ? w : nil),
                height: (h > 0 ? h : nil)
            )
        } catch {
            return .init()
        }
        #else
        return .init()
        #endif
    }
}
