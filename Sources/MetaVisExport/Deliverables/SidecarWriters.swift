import Foundation
import AVFoundation

#if canImport(ImageIO)
import ImageIO
#endif

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum CaptionSidecarWriter {
    public static func writeWebVTT(to url: URL) async throws {
        let contents = "WEBVTT\n\n"
        try contents.data(using: .utf8)?.write(to: url, options: [.atomic])
    }

    public static func writeSRT(to url: URL) async throws {
        // Valid empty SRT: just no cues.
        let contents = ""
        try contents.data(using: .utf8)?.write(to: url, options: [.atomic])
    }
}

public enum ThumbnailSidecarWriter {
    public static func writeThumbnailJPEG(from movieURL: URL, to url: URL, timeSeconds: Double) async throws {
        let asset = AVAsset(url: movieURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: max(0, timeSeconds), preferredTimescale: 600)
        let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
        try encodeJPEG(cgImage: cgImage, to: url, quality: 0.85)
    }

    public static func writeContactSheetJPEG(
        from movieURL: URL,
        to url: URL,
        timesSeconds: [Double],
        columns: Int,
        rows: Int,
        maxCellDimension: Int? = nil
    ) async throws {
        let columns = max(1, columns)
        let rows = max(1, rows)
        let count = columns * rows

        let asset = AVAsset(url: movieURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        if let maxCellDimension, maxCellDimension > 0 {
            generator.maximumSize = CGSize(width: maxCellDimension, height: maxCellDimension)
        }

        let duration = max(0.0, (try await asset.load(.duration)).seconds)
        let times: [CMTime]
        if duration <= 0.0001 || count == 1 {
            times = [CMTime(seconds: 0, preferredTimescale: 600)]
        } else {
            let sanitized = timesSeconds.filter { $0.isFinite }.map { max(0.0, min(duration - 0.001, $0)) }
            let chosen = Array(sanitized.prefix(count))
            if chosen.isEmpty {
                times = [CMTime(seconds: 0, preferredTimescale: 600)]
            } else {
                times = chosen.map { CMTime(seconds: $0, preferredTimescale: 600) }
            }
        }

        var images: [CGImage] = []
        images.reserveCapacity(times.count)
        for t in times {
            let cg = try generator.copyCGImage(at: t, actualTime: nil)
            images.append(cg)
        }

        guard let first = images.first else {
            throw NSError(domain: "MetaVisExport", code: 20, userInfo: [NSLocalizedDescriptionKey: "No frames for contact sheet"])
        }

        let cellWidth = first.width
        let cellHeight = first.height
        let sheetWidth = cellWidth * columns
        let sheetHeight = cellHeight * rows

        #if canImport(CoreGraphics)
        guard let ctx = CGContext(
            data: nil,
            width: sheetWidth,
            height: sheetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "MetaVisExport", code: 21, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGContext"])
        }

        ctx.interpolationQuality = .high
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight))

        for idx in 0..<min(images.count, count) {
            let col = idx % columns
            let row = idx / columns
            let x = col * cellWidth
            // CoreGraphics origin is bottom-left.
            let y = sheetHeight - (row + 1) * cellHeight
            ctx.draw(images[idx], in: CGRect(x: x, y: y, width: cellWidth, height: cellHeight))
        }

        guard let composed = ctx.makeImage() else {
            throw NSError(domain: "MetaVisExport", code: 22, userInfo: [NSLocalizedDescriptionKey: "Failed to compose contact sheet"])
        }
        try encodeJPEG(cgImage: composed, to: url, quality: 0.85)
        #else
        throw NSError(domain: "MetaVisExport", code: 23, userInfo: [NSLocalizedDescriptionKey: "CoreGraphics not available"])
        #endif
    }

    public static func writeContactSheetJPEG(from movieURL: URL, to url: URL, columns: Int, rows: Int) async throws {
        let columns = max(1, columns)
        let rows = max(1, rows)
        let count = columns * rows

        let asset = AVAsset(url: movieURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        let duration = max(0.0, (try await asset.load(.duration)).seconds)
        let timesSeconds: [Double]
        if duration <= 0.0001 || count == 1 {
            timesSeconds = [0.0]
        } else {
            let step = duration / Double(count)
            timesSeconds = (0..<count).map { i in
                min(duration - 0.001, Double(i) * step + step * 0.5)
            }
        }

        try await writeContactSheetJPEG(
            from: movieURL,
            to: url,
            timesSeconds: timesSeconds,
            columns: columns,
            rows: rows,
            maxCellDimension: nil
        )
    }

    private static func encodeJPEG(cgImage: CGImage, to url: URL, quality: Double) throws {
        #if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
        let data = NSMutableData()
        let typeIdentifier = UTType.jpeg.identifier as CFString
        guard let dest = CGImageDestinationCreateWithData(data, typeIdentifier, 1, nil) else {
            throw NSError(domain: "MetaVisExport", code: 24, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImageDestination"]) 
        }

        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "MetaVisExport", code: 25, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize JPEG encoding"]) 
        }

        try (data as Data).write(to: url, options: [.atomic])
        #else
        throw NSError(domain: "MetaVisExport", code: 26, userInfo: [NSLocalizedDescriptionKey: "ImageIO/UTType not available"]) 
        #endif
    }
}
