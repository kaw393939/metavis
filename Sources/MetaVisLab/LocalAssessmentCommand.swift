import Foundation
import AVFoundation
import CoreGraphics
import CoreVideo

#if canImport(ImageIO)
import ImageIO
#endif

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

import MetaVisQC
import MetaVisPerception
import MetaVisExport

enum LocalAssessmentCommand {
    struct Options: Sendable {
        var inputMovieURL: URL
        var outputDirURL: URL
        var sampleCount: Int
        var allowLarge: Bool

        var contactSheetColumns: Int
        var contactSheetRows: Int

        var maxDimension: Int

        init(
            inputMovieURL: URL,
            outputDirURL: URL,
            sampleCount: Int,
            allowLarge: Bool,
            contactSheetColumns: Int,
            contactSheetRows: Int,
            maxDimension: Int
        ) {
            self.inputMovieURL = inputMovieURL
            self.outputDirURL = outputDirURL
            self.sampleCount = sampleCount
            self.allowLarge = allowLarge
            self.contactSheetColumns = contactSheetColumns
            self.contactSheetRows = contactSheetRows
            self.maxDimension = maxDimension
        }
    }

    static func run(args: [String]) async throws {
        let options = try parse(args: args)
        try await run(options: options)
    }

    // MARK: - Core

    static func run(options: Options) async throws {
        let inputURL = options.inputMovieURL

        // Safety: avoid automatic heavy analysis.
        try enforceLargeAssetPolicy(inputURL: inputURL, allowLarge: options.allowLarge)

        let fm = FileManager.default
        try fm.createDirectory(at: options.outputDirURL, withIntermediateDirectories: true)

        let framesDir = options.outputDirURL.appendingPathComponent("frames", isDirectory: true)
        try fm.createDirectory(at: framesDir, withIntermediateDirectories: true)

        let asset = AVAsset(url: inputURL)
        let duration = max(0.0, (try await asset.load(.duration)).seconds)

        // 1) Deterministic metadata QC
        let metadata = try await VideoMetadataQC.inspectMovie(at: inputURL)

        // 2) Sample times
        let sampleCount = max(1, options.sampleCount)
        let times = makeSampleTimes(durationSeconds: duration, count: sampleCount)
        let labels = times.enumerated().map { idx, t in "s\(idx)@\(String(format: "%.3f", t))" }

        // 3) Extract frames + faces
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        let faceDetector = FaceDetectionService()
        try await faceDetector.warmUp()

        var samples: [LocalAssessmentReport.Sample] = []
        samples.reserveCapacity(times.count)

        for (idx, t) in times.enumerated() {
            let label = labels[idx]
            let cmTime = CMTime(seconds: max(0, t), preferredTimescale: 600)
            let cg = try generator.copyCGImage(at: cmTime, actualTime: nil)

            let frameName = String(format: "frame_%03d_%.3fs.jpg", idx, t)
            let frameURL = framesDir.appendingPathComponent(frameName)
            try JPEGEncoding.encode(cgImage: cg, to: frameURL, quality: 0.85)

            let pb = try PixelBufferConversion.pixelBuffer(from: cg)
            let faces = (try? await faceDetector.detectFaces(in: pb)) ?? []

            let faceBoxes = faces.map { rect in
                LocalAssessmentReport.FaceRect(x: rect.origin.x, y: rect.origin.y, w: rect.width, h: rect.height)
            }

            samples.append(.init(
                label: label,
                timeSeconds: t,
                frameFile: "frames/\(frameName)",
                faces: faceBoxes
            ))
        }

        await faceDetector.coolDown()

        // 4) Fingerprints + color stats (deterministic local QC)
        let fpSamples: [VideoContentQC.Sample] = zip(times, labels).map { t, label in
            .init(timeSeconds: t, label: label)
        }
        let fingerprints = try await VideoContentQC.fingerprints(movieURL: inputURL, samples: fpSamples)
        var fingerprintByLabel: [String: VideoContentQC.Fingerprint] = [:]
        fingerprintByLabel.reserveCapacity(fingerprints.count)
        for (label, fp) in fingerprints {
            fingerprintByLabel[label] = fp
        }

        let csSamples: [VideoContentQC.ColorStatsSample] = zip(times, labels).map { t, label in
            .init(
                timeSeconds: t,
                label: label,
                minMeanLuma: 0.0,
                maxMeanLuma: 1.0,
                maxChannelDelta: 1.0,
                minLowLumaFraction: 0.0,
                minHighLumaFraction: 0.0
            )
        }
        let colorStats = try await VideoContentQC.validateColorStats(movieURL: inputURL, samples: csSamples, maxDimension: options.maxDimension)
        var colorStatsByLabel: [String: VideoContentQC.ColorStatsResult] = [:]
        colorStatsByLabel.reserveCapacity(colorStats.count)
        for result in colorStats {
            colorStatsByLabel[result.label] = result
        }

        // Merge
        for idx in samples.indices {
            let label = samples[idx].label
            if let fp = fingerprintByLabel[label] {
                samples[idx].fingerprint = .init(
                    meanR: fp.meanR, meanG: fp.meanG, meanB: fp.meanB,
                    stdR: fp.stdR, stdG: fp.stdG, stdB: fp.stdB
                )
            }
            if let cs = colorStatsByLabel[label] {
                samples[idx].colorStats = .init(
                    meanRGB: [cs.meanRGB.x, cs.meanRGB.y, cs.meanRGB.z],
                    meanLuma: cs.meanLuma,
                    lowLumaFraction: cs.lowLumaFraction,
                    highLumaFraction: cs.highLumaFraction,
                    peakBin: cs.peakBin
                )
            }
        }

        // 5) Summary artifacts (thumbnail + contact sheet)
        let mid = (duration > 0.0001) ? min(duration - 0.001, duration * 0.5) : 0.0
        let thumbnailURL = options.outputDirURL.appendingPathComponent("thumbnail.jpg")
        try await ThumbnailSidecarWriter.writeThumbnailJPEG(from: inputURL, to: thumbnailURL, timeSeconds: mid)

        let contactURL = options.outputDirURL.appendingPathComponent("contact_sheet.jpg")
        try await ThumbnailSidecarWriter.writeContactSheetJPEG(
            from: inputURL,
            to: contactURL,
            timesSeconds: times,
            columns: options.contactSheetColumns,
            rows: options.contactSheetRows,
            maxCellDimension: options.maxDimension
        )

        // 6) Write JSON report
        let report = LocalAssessmentReport(
            schemaVersion: 1,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            inputMoviePath: inputURL.path,
            durationSeconds: duration,
            metadata: metadata,
            sampleCount: samples.count,
            samples: samples
        )

        let reportURL = options.outputDirURL.appendingPathComponent("local_report.json")
        try JSONWriting.write(report, to: reportURL)

        print("✅ assess-local complete")
        print("   input: \(inputURL.path)")
        print("   out:   \(options.outputDirURL.path)")
    }

    // MARK: - Parsing

    private static func parse(args: [String]) throws -> Options {
        func usage(_ message: String) -> NSError {
            NSError(domain: "MetaVisLab", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(message)\n\n" + MetaVisLabHelp.text])
        }

        var inputPath: String?
        var outPath: String?
        var samples: Int = 9
        var allowLarge = false
        var cols = 3
        var rows = 3
        var didSetCols = false
        var didSetRows = false
        var maxDimension = 256

        var i = 0
        while i < args.count {
            let a = args[i]
            switch a {
            case "--input":
                i += 1
                guard i < args.count else { throw usage("Missing value for --input") }
                inputPath = args[i]
            case "--out":
                i += 1
                guard i < args.count else { throw usage("Missing value for --out") }
                outPath = args[i]
            case "--samples":
                i += 1
                guard i < args.count else { throw usage("Missing value for --samples") }
                samples = Int(args[i]) ?? samples
            case "--allow-large":
                allowLarge = true
            case "--contact-cols":
                i += 1
                guard i < args.count else { throw usage("Missing value for --contact-cols") }
                cols = Int(args[i]) ?? cols
                didSetCols = true
            case "--contact-rows":
                i += 1
                guard i < args.count else { throw usage("Missing value for --contact-rows") }
                rows = Int(args[i]) ?? rows
                didSetRows = true
            case "--max-dim":
                i += 1
                guard i < args.count else { throw usage("Missing value for --max-dim") }
                maxDimension = Int(args[i]) ?? maxDimension
            case "--help", "-h":
                throw usage("")
            default:
                throw usage("Unknown arg: \(a)")
            }
            i += 1
        }

        guard let inputPath else {
            throw usage("--input is required")
        }

        if !didSetCols && !didSetRows {
            if samples == 9 {
                cols = 3
                rows = 3
            } else {
                cols = min(7, max(1, samples))
                rows = Int(ceil(Double(samples) / Double(cols)))
            }
        }

        let inputURL = URL(fileURLWithPath: inputPath)

        let outputURL: URL
        if let outPath {
            outputURL = URL(fileURLWithPath: outPath)
        } else {
            let base = inputURL.deletingPathExtension().lastPathComponent
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            outputURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("test_outputs")
                .appendingPathComponent("local_assessment")
                .appendingPathComponent("\(base)_\(stamp)")
        }

        return Options(
            inputMovieURL: inputURL,
            outputDirURL: outputURL,
            sampleCount: samples,
            allowLarge: allowLarge,
            contactSheetColumns: cols,
            contactSheetRows: rows,
            maxDimension: maxDimension
        )
    }

    // MARK: - Helpers

    private static func makeSampleTimes(durationSeconds: Double, count: Int) -> [Double] {
        if durationSeconds <= 0.0001 {
            return [0.0]
        }
        if count == 1 {
            return [min(durationSeconds - 0.001, durationSeconds * 0.5)]
        }
        let n = max(2, count)
        // Center-of-bin sampling avoids exact GOP boundaries more often.
        let step = durationSeconds / Double(n)
        return (0..<n).map { i in
            let t = Double(i) * step + step * 0.5
            return min(max(0, t), max(0, durationSeconds - 0.001))
        }
    }

    private static func enforceLargeAssetPolicy(inputURL: URL, allowLarge: Bool) throws {
        let name = inputURL.lastPathComponent.lowercased()

        // Conservative default threshold; user can override.
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
                userInfo: [NSLocalizedDescriptionKey: "Refusing to assess large asset (\(name), \(sizeBytes) bytes) without --allow-large."]
            )
        }
    }
}

// MARK: - Report

struct LocalAssessmentReport: Codable, Sendable {
    struct Fingerprint: Codable, Sendable {
        var meanR: Double
        var meanG: Double
        var meanB: Double
        var stdR: Double
        var stdG: Double
        var stdB: Double
    }

    struct ColorStats: Codable, Sendable {
        var meanRGB: [Float]
        var meanLuma: Float
        var lowLumaFraction: Float
        var highLumaFraction: Float
        var peakBin: Int
    }

    struct FaceRect: Codable, Sendable {
        var x: Double
        var y: Double
        var w: Double
        var h: Double
    }

    struct Sample: Codable, Sendable {
        var label: String
        var timeSeconds: Double
        var frameFile: String
        var faces: [FaceRect]

        var fingerprint: Fingerprint?
        var colorStats: ColorStats?

        init(label: String, timeSeconds: Double, frameFile: String, faces: [FaceRect]) {
            self.label = label
            self.timeSeconds = timeSeconds
            self.frameFile = frameFile
            self.faces = faces
        }
    }

    var schemaVersion: Int
    var createdAt: String
    var inputMoviePath: String
    var durationSeconds: Double
    var metadata: VideoMetadataQC.Report
    var sampleCount: Int
    var samples: [Sample]
}

// MARK: - Encoding helpers

enum JSONWriting {
    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }
}

enum JPEGEncoding {
    static func encode(cgImage: CGImage, to url: URL, quality: Double) throws {
        #if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
        let data = NSMutableData()
        let typeIdentifier = UTType.jpeg.identifier as CFString
        guard let dest = CGImageDestinationCreateWithData(data, typeIdentifier, 1, nil) else {
            throw NSError(domain: "MetaVisLab", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImageDestination"]) 
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "MetaVisLab", code: 11, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize JPEG encoding"]) 
        }
        try (data as Data).write(to: url, options: [.atomic])
        #else
        throw NSError(domain: "MetaVisLab", code: 12, userInfo: [NSLocalizedDescriptionKey: "ImageIO/UTType not available"]) 
        #endif
    }
}

enum PixelBufferConversion {
    static func pixelBuffer(from cgImage: CGImage) throws -> CVPixelBuffer {
        let width = cgImage.width
        let height = cgImage.height

        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA)
        ]

        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
        guard status == kCVReturnSuccess, let pb else {
            throw NSError(domain: "MetaVisLab", code: 20, userInfo: [NSLocalizedDescriptionKey: "CVPixelBufferCreate failed (\(status))"]) 
        }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let base = CVPixelBufferGetBaseAddress(pb) else {
            throw NSError(domain: "MetaVisLab", code: 21, userInfo: [NSLocalizedDescriptionKey: "CVPixelBufferGetBaseAddress failed"]) 
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
        guard let ctx = CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw NSError(domain: "MetaVisLab", code: 22, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGContext for pixel buffer"]) 
        }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pb
    }
}
