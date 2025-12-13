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

    public struct Verdict: Sendable {
        public var accepted: Bool
        public var rawText: String
    }

    /// Extract a few keyframes and ask Gemini to validate the expected content.
    ///
    /// This is intended as an *additional* acceptance layer on top of deterministic `VideoQC` checks.
    public static func acceptMulticlipExport(
        movieURL: URL,
        keyFrames: [KeyFrame],
        expectedNarrative: String,
        requireKey: Bool = true
    ) async throws -> Verdict {
        DotEnvLoader.loadIfPresent()

        // If no key is present and caller doesn't require it, skip.
        let hasKey = getenv("GEMINI_API_KEY") != nil || getenv("API__GOOGLE_API_KEY") != nil || getenv("GOOGLE_API_KEY") != nil
        if !hasKey {
            if requireKey {
                throw GeminiError.misconfigured("GEMINI_API_KEY (or API__GOOGLE_API_KEY) not present in environment")
            }
            return Verdict(accepted: true, rawText: "SKIPPED (no GEMINI_API_KEY)")
        }

        let images = try extractJPEGs(assetURL: movieURL, frames: keyFrames)

        // Compose a strict prompt and demand JSON.
        let prompt = """
You are a strict QA system for a video export pipeline.

EXPECTED NARRATIVE:
\(expectedNarrative)

You will be given several labeled keyframes from a rendered export. Validate that the content matches the expected narrative.

Return ONLY valid JSON with this schema:
{
  \"accepted\": true|false,
  \"checks\": [ { \"label\": string, \"pass\": true|false, \"reason\": string } ],
  \"summary\": string
}

Acceptance rules:
- accepted=true ONLY if every check pass=true.
- Be conservative: if uncertain, fail.
"""

        // Build a multimodal request with inline JPEG data (smaller/faster than PNG).
        var parts: [GeminiGenerateContentRequest.Part] = [.text(prompt)]
        for img in images {
            parts.append(.text("FRAME: \(img.label) @ \(String(format: "%.3f", img.timeSeconds))s"))
            parts.append(.inlineData(mimeType: "image/jpeg", dataBase64: img.jpegBase64))
        }

        let config = try GeminiConfig.fromEnvironment()
        let client = GeminiClient(config: config)

        let body = GeminiGenerateContentRequest(contents: [
            .init(role: "user", parts: parts)
        ])
        let response = try await client.generateContent(body)
        let text = response.primaryText ?? ""

        // Parse minimal JSON acceptance
        let accepted = parseAcceptedFlag(from: text) ?? false
        return Verdict(accepted: accepted, rawText: text)
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
}
