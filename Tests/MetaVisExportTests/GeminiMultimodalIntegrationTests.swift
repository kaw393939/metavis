import XCTest
import Foundation
import MetaVisCore
import MetaVisQC
import MetaVisServices

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

#if canImport(ImageIO)
import ImageIO
#endif

final class GeminiMultimodalIntegrationTests: XCTestCase {

    func test_gemini_generateContent_with_inlineImage_and_optionalVideo() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["RUN_GEMINI_QC"] == "1" else {
            throw XCTSkip("Set RUN_GEMINI_QC=1 to enable real Gemini multimodal integration test")
        }

        guard hasGeminiKey() else {
            throw XCTSkip("Missing GEMINI_API_KEY (or API__GOOGLE_API_KEY/GOOGLE_API_KEY)")
        }

        let png = try makeTestPNGData()

        var evidence = GeminiPromptBuilder.Evidence(
            inline: [
                .init(label: "TEST_IMAGE: 64x64 solid red PNG", mimeType: "image/png", data: png)
            ],
            fileUris: []
        )

        #if canImport(AVFoundation)
        if env["RUN_GEMINI_QC_SEND_VIDEO"] == "1" {
            if let videoData = try? makeTinyMOVData(width: 64, height: 64, fps: 10, frameCount: 10) {
                evidence.inline.append(.init(label: "TEST_VIDEO: 64x64 ~1s MOV", mimeType: "video/quicktime", data: videoData))
            }
        }
        #endif

        let policy = AIUsagePolicy(mode: .textImagesAndVideo, mediaSource: .deliverablesOnly)
        let privacy = PrivacyPolicy(allowRawMediaUpload: false, allowDeliverablesUpload: true)

        let context = GeminiPromptBuilder.PromptContext(
            expectedNarrative: "This is a test-only multimodal request. If you can read the image/video, respond with conservative checks.",
            keyFrameLabels: ["TEST_IMAGE", "TEST_VIDEO"],
            policy: policy,
            privacy: privacy,
            modelHint: nil
        )

        let prompt = GeminiPromptBuilder.buildPrompt(context, notes: [
            "Integration test: verify inline_data works.",
            "Return JSON only."
        ])

        let body = GeminiPromptBuilder.buildRequest(prompt: prompt, evidence: evidence)

        let config = try GeminiConfig.fromEnvironment()
        let client = GeminiClient(config: config)
        let response = try await client.generateContent(body)

        let text = response.primaryText ?? ""
        XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty Gemini response")

        // Be tolerant: LLMs sometimes wrap JSON. Just require we can find an `accepted` boolean.
        guard let accepted = extractAcceptedBoolean(from: text) else {
            XCTFail("Gemini response did not contain a parseable `accepted` boolean. Raw: \n\(text)")
            return
        }

        // Do not assert accepted == true/false; this is an integration transport test.
        XCTAssertNotNil(accepted)
    }
}

private func hasGeminiKey() -> Bool {
    getenv("GEMINI_API_KEY") != nil || getenv("API__GOOGLE_API_KEY") != nil || getenv("GOOGLE_API_KEY") != nil
}

private func extractAcceptedBoolean(from text: String) -> Bool? {
    let pattern = "\\\"accepted\\\"\\s*:\\s*(true|false)"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
    guard match.numberOfRanges >= 2, let boolRange = Range(match.range(at: 1), in: text) else { return nil }
    let str = String(text[boolRange]).lowercased()
    switch str {
    case "true": return true
    case "false": return false
    default: return nil
    }
}

private func makeTestPNGData() throws -> Data {
    #if canImport(ImageIO)
    let width = 64
    let height = 64
    let bytesPerRow = width * 4

    var rgba = [UInt8](repeating: 0, count: height * bytesPerRow)
    for y in 0..<height {
        for x in 0..<width {
            let i = y * bytesPerRow + x * 4
            rgba[i + 0] = 255 // R
            rgba[i + 1] = 0   // G
            rgba[i + 2] = 0   // B
            rgba[i + 3] = 255 // A
        }
    }

    let cs = CGColorSpaceCreateDeviceRGB()
    guard let provider = CGDataProvider(data: Data(rgba) as CFData) else {
        throw NSError(domain: "GeminiMultimodalIntegrationTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create data provider"]) 
    }

    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard let cg = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: bytesPerRow,
        space: cs,
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    ) else {
        throw NSError(domain: "GeminiMultimodalIntegrationTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"]) 
    }

    let data = NSMutableData()
    #if canImport(UniformTypeIdentifiers)
    let typeIdentifier = UTType.png.identifier as CFString
    #else
    let typeIdentifier = "public.png" as CFString
    #endif

    guard let dest = CGImageDestinationCreateWithData(data, typeIdentifier, 1, nil) else {
        throw NSError(domain: "GeminiMultimodalIntegrationTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG destination"]) 
    }

    CGImageDestinationAddImage(dest, cg, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "GeminiMultimodalIntegrationTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize PNG"]) 
    }

    return data as Data
    #else
    throw NSError(domain: "GeminiMultimodalIntegrationTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "ImageIO not available"]) 
    #endif
}

#if canImport(AVFoundation)
private func makeTinyMOVData(width: Int, height: Int, fps: Int, frameCount: Int) throws -> Data {
    let dir = FileManager.default.temporaryDirectory
    let url = dir.appendingPathComponent("gemini_multimodal_test_\(UUID().uuidString).mov")
    defer { try? FileManager.default.removeItem(at: url) }

    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

    let settings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height
    ]

    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = false

    let attrs: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height
    ]
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attrs)

    guard writer.canAdd(input) else {
        throw NSError(domain: "GeminiMultimodalIntegrationTests", code: 20, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input"]) 
    }
    writer.add(input)

    guard writer.startWriting() else {
        throw writer.error ?? NSError(domain: "GeminiMultimodalIntegrationTests", code: 21, userInfo: [NSLocalizedDescriptionKey: "startWriting failed"]) 
    }
    writer.startSession(atSourceTime: .zero)

    let frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, fps)))

    for frameIndex in 0..<frameCount {
        while !input.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.001)
        }

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixelBuffer)
        guard let pb = pixelBuffer else {
            throw NSError(domain: "GeminiMultimodalIntegrationTests", code: 22, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate pixel buffer"]) 
        }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        if let base = CVPixelBufferGetBaseAddress(pb) {
            // Fill with a changing color pattern.
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
            let buf = base.assumingMemoryBound(to: UInt8.self)
            let r = UInt8((frameIndex * 17) % 255)
            let g = UInt8((frameIndex * 31) % 255)
            let b = UInt8((frameIndex * 47) % 255)
            for y in 0..<height {
                for x in 0..<width {
                    let i = y * bytesPerRow + x * 4
                    buf[i + 0] = b
                    buf[i + 1] = g
                    buf[i + 2] = r
                    buf[i + 3] = 255
                }
            }
        }

        let pts = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
        adaptor.append(pb, withPresentationTime: pts)
    }

    input.markAsFinished()
    writer.finishWriting { }

    if writer.status == .failed {
        throw writer.error ?? NSError(domain: "GeminiMultimodalIntegrationTests", code: 23, userInfo: [NSLocalizedDescriptionKey: "finishWriting failed"]) 
    }

    return try Data(contentsOf: url)
}
#endif
