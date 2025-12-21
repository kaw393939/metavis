import Foundation
import AVFoundation
import MetaVisCore

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
        try await writeWebVTT(to: url, cues: [])
    }

    /// Best-effort writer that prefers copying an existing sidecar from disk.
    /// If no candidate exists, falls back to rendering from cues (empty by default).
    public static func writeWebVTT(to url: URL, sidecarCandidates: [URL], cues: [CaptionCue] = []) async throws {
        if let candidate = firstExistingCandidate(in: sidecarCandidates, allowedExtensions: ["vtt"]) {
            try copyFile(from: candidate, to: url)
            return
        }
        if let candidate = firstExistingCandidate(in: sidecarCandidates, allowedExtensions: ["srt"]) {
            let parsed = try parseSRT(from: candidate)
            try await writeWebVTT(to: url, cues: parsed)
            return
        }
        try await writeWebVTT(to: url, cues: cues)
    }

    public static func writeSRT(to url: URL) async throws {
        try await writeSRT(to: url, cues: [])
    }

    /// Best-effort writer that prefers copying an existing sidecar from disk.
    /// If no candidate exists, falls back to rendering from cues (empty by default).
    public static func writeSRT(to url: URL, sidecarCandidates: [URL], cues: [CaptionCue] = []) async throws {
        if let candidate = firstExistingCandidate(in: sidecarCandidates, allowedExtensions: ["srt"]) {
            try copyFile(from: candidate, to: url)
            return
        }
        if let candidate = firstExistingCandidate(in: sidecarCandidates, allowedExtensions: ["vtt"]) {
            let parsed = try parseWebVTT(from: candidate)
            try await writeSRT(to: url, cues: parsed)
            return
        }
        try await writeSRT(to: url, cues: cues)
    }

    public static func writeWebVTT(to url: URL, cues: [CaptionCue]) async throws {
        let contents = renderWebVTT(cues: cues)
        try contents.data(using: .utf8)?.write(to: url, options: [.atomic])
    }

    public static func writeSRT(to url: URL, cues: [CaptionCue]) async throws {
        // Valid empty SRT: just no cues.
        let contents = renderSRT(cues: cues)
        try contents.data(using: .utf8)?.write(to: url, options: [.atomic])
    }

    /// Loads caption cues from the first existing candidate in `sidecarCandidates`.
    /// Returns an empty list if none exist.
    public static func loadCues(from sidecarCandidates: [URL]) throws -> [CaptionCue] {
        if let candidate = firstExistingCandidate(in: sidecarCandidates, allowedExtensions: ["vtt"]) {
            return try parseWebVTT(from: candidate)
        }
        if let candidate = firstExistingCandidate(in: sidecarCandidates, allowedExtensions: ["srt"]) {
            return try parseSRT(from: candidate)
        }
        return []
    }

    private static func renderWebVTT(cues: [CaptionCue]) -> String {
        var output = "WEBVTT\n\n"
        let normalized = normalize(cues: cues)
        for cue in normalized {
            output += "\(formatVTTTime(cue.startSeconds)) --> \(formatVTTTime(cue.endSeconds))\n"
            if let speaker = cue.speaker, !speaker.isEmpty {
                output += "<v \(speaker)>"
            }
            output += cue.text + "\n\n"
        }
        return output
    }

    private static func firstExistingCandidate(in candidates: [URL], allowedExtensions: Set<String>) -> URL? {
        for url in candidates {
            let ext = url.pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { continue }
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private static func copyFile(from source: URL, to destination: URL) throws {
        let data = try Data(contentsOf: source)
        try data.write(to: destination, options: [.atomic])
    }

    private static func parseWebVTT(from url: URL) throws -> [CaptionCue] {
        let raw = try String(contentsOf: url, encoding: .utf8)
        return parseWebVTT(contents: raw)
    }

    private static func parseSRT(from url: URL) throws -> [CaptionCue] {
        let raw = try String(contentsOf: url, encoding: .utf8)
        return parseSRT(contents: raw)
    }

    private static func parseWebVTT(contents: String) -> [CaptionCue] {
        let lines = contents
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var cues: [CaptionCue] = []
        cues.reserveCapacity(64)

        var i = 0
        // Skip optional WEBVTT header block.
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            i += 1
            if line.isEmpty { break }
        }

        while i < lines.count {
            // Skip blank lines.
            while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
            }
            if i >= lines.count { break }

            // Optional cue identifier line (does not contain -->).
            if !lines[i].contains("-->") {
                i += 1
                if i >= lines.count { break }
            }

            guard i < lines.count, let timing = parseTimingLine(lines[i], isVTT: true) else {
                // Malformed block: skip until next blank line.
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).isEmpty { i += 1 }
                continue
            }
            i += 1

            var textLines: [String] = []
            while i < lines.count {
                let line = lines[i]
                i += 1
                if line.trimmingCharacters(in: .whitespaces).isEmpty { break }
                textLines.append(line)
            }

            let (speaker, text) = parseSpeakerFromVTT(textLines.joined(separator: "\n"))
            cues.append(.init(startSeconds: timing.start, endSeconds: timing.end, text: text, speaker: speaker))
        }

        return cues
    }

    private static func parseSRT(contents: String) -> [CaptionCue] {
        let lines = contents
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var cues: [CaptionCue] = []
        cues.reserveCapacity(64)

        var i = 0
        while i < lines.count {
            // Skip blank lines.
            while i < lines.count, lines[i].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                i += 1
            }
            if i >= lines.count { break }

            // Optional numeric index line.
            if Int(lines[i].trimmingCharacters(in: .whitespacesAndNewlines)) != nil {
                i += 1
            }
            if i >= lines.count { break }

            guard let timing = parseTimingLine(lines[i], isVTT: false) else {
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).isEmpty { i += 1 }
                continue
            }
            i += 1

            var textLines: [String] = []
            while i < lines.count {
                let line = lines[i]
                i += 1
                if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { break }
                textLines.append(line)
            }

            let (speaker, text) = parseSpeakerFromSRT(textLines.joined(separator: "\n"))
            cues.append(.init(startSeconds: timing.start, endSeconds: timing.end, text: text, speaker: speaker))
        }

        return cues
    }

    private static func parseTimingLine(_ line: String, isVTT: Bool) -> (start: Double, end: Double)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count >= 2 else { return nil }

        let startRaw = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let endRaw = parts[1]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .first ?? ""

        guard let start = isVTT ? parseVTTTime(startRaw) : parseSRTTime(startRaw) else { return nil }
        guard let end = isVTT ? parseVTTTime(endRaw) : parseSRTTime(endRaw) else { return nil }
        return (start: start, end: end)
    }

    private static func parseVTTTime(_ s: String) -> Double? {
        // Expected: HH:MM:SS.mmm
        let comps = s.split(separator: ":")
        guard comps.count == 3 else { return nil }
        guard let hours = Double(comps[0]), let minutes = Double(comps[1]) else { return nil }
        let secParts = comps[2].split(separator: ".")
        guard secParts.count == 2 else { return nil }
        guard let secs = Double(secParts[0]), let millis = Double(secParts[1]) else { return nil }
        return hours * 3600 + minutes * 60 + secs + millis / 1000.0
    }

    private static func parseSRTTime(_ s: String) -> Double? {
        // Expected: HH:MM:SS,mmm
        let comps = s.split(separator: ":")
        guard comps.count == 3 else { return nil }
        guard let hours = Double(comps[0]), let minutes = Double(comps[1]) else { return nil }
        let secParts = comps[2].split(separator: ",")
        guard secParts.count == 2 else { return nil }
        guard let secs = Double(secParts[0]), let millis = Double(secParts[1]) else { return nil }
        return hours * 3600 + minutes * 60 + secs + millis / 1000.0
    }

    private static func parseSpeakerFromVTT(_ text: String) -> (speaker: String?, text: String) {
        // Minimal support for <v Speaker> prefix.
        guard text.hasPrefix("<v ") else { return (nil, text) }
        guard let close = text.firstIndex(of: ">") else { return (nil, text) }
        let tag = String(text[text.startIndex..<close]) // "<v Speaker"
        let speaker = tag.replacingOccurrences(of: "<v", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let remainder = String(text[text.index(after: close)...])
        return (speaker.isEmpty ? nil : speaker, remainder)
    }

    private static func parseSpeakerFromSRT(_ text: String) -> (speaker: String?, text: String) {
        // Minimal support for "[Speaker] " prefix.
        guard text.hasPrefix("[") else { return (nil, text) }
        guard let close = text.firstIndex(of: "]") else { return (nil, text) }
        let speaker = String(text[text.index(after: text.startIndex)..<close])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let after = String(text[text.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        return (speaker.isEmpty ? nil : speaker, after)
    }

    private static func renderSRT(cues: [CaptionCue]) -> String {
        let normalized = normalize(cues: cues)
        guard !normalized.isEmpty else { return "" }

        var output = ""
        for (idx, cue) in normalized.enumerated() {
            output += "\(idx + 1)\n"
            output += "\(formatSRTTime(cue.startSeconds)) --> \(formatSRTTime(cue.endSeconds))\n"
            if let speaker = cue.speaker, !speaker.isEmpty {
                output += "[\(speaker)] "
            }
            output += cue.text + "\n\n"
        }
        return output
    }

    private static func normalize(cues: [CaptionCue]) -> [CaptionCue] {
        let filtered = cues.filter { cue in
            cue.startSeconds.isFinite && cue.endSeconds.isFinite && cue.startSeconds >= 0 && cue.endSeconds > cue.startSeconds
        }

        let sorted = filtered.sorted { a, b in
            if a.startSeconds != b.startSeconds { return a.startSeconds < b.startSeconds }
            return a.endSeconds < b.endSeconds
        }

        var out: [CaptionCue] = []
        out.reserveCapacity(sorted.count)
        var prevEnd: Double = 0
        for cue in sorted {
            let start = max(cue.startSeconds, prevEnd)
            let end = max(cue.endSeconds, start)
            if end > start {
                let text = cue.text
                    .replacingOccurrences(of: "\r\n", with: "\n")
                    .replacingOccurrences(of: "\r", with: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    out.append(CaptionCue(startSeconds: start, endSeconds: end, text: text, speaker: cue.speaker))
                    prevEnd = end
                }
            }
        }
        return out
    }

    private static func formatSRTTime(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let hours = Int(clamped) / 3600
        let minutes = (Int(clamped) % 3600) / 60
        let secs = Int(clamped) % 60
        let millis = Int((clamped.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, millis)
    }

    private static func formatVTTTime(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let hours = Int(clamped) / 3600
        let minutes = (Int(clamped) % 3600) / 60
        let secs = Int(clamped) % 60
        let millis = Int((clamped.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, secs, millis)
    }
}

public enum TranscriptSidecarWriter {

    /// Writes a stable word-level transcript JSON.
    ///
    /// If `cues` is empty, attempts to load caption cues from `sidecarCandidates`.
    public static func writeTranscriptWordsJSON(
        to url: URL,
        sidecarCandidates: [URL],
        cues: [CaptionCue] = []
    ) async throws {
        let resolvedCues: [CaptionCue] = cues.isEmpty ? (try CaptionSidecarWriter.loadCues(from: sidecarCandidates)) : cues
        let artifact = TranscriptArtifact(words: words(from: resolvedCues))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(artifact)
        try data.write(to: url, options: [.atomic])
    }

    private static func words(from cues: [CaptionCue]) -> [TranscriptArtifact.Word] {
        // Deterministic split: whitespace-only, preserve order.
        // Time mapping (v1): assume cue times are already in timeline time; source == timeline.
        var out: [TranscriptArtifact.Word] = []
        out.reserveCapacity(max(16, cues.count * 3))

        for cue in cues {
            let startS = max(0.0, cue.startSeconds)
            let endS = max(startS, cue.endSeconds)
            let raw = cue.text
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty { continue }

            let tokens = raw
                .split(whereSeparator: { $0.isWhitespace })
                .map { String($0) }
            if tokens.isEmpty { continue }

            let cueStartTicks = secondsToTicks(startS)
            let cueEndTicks = max(cueStartTicks, secondsToTicks(endS))
            let total = max(1, cueEndTicks - cueStartTicks)
            let n = Int64(tokens.count)

            for (i, word) in tokens.enumerated() {
                let a = Int64(i)
                let b = Int64(i + 1)

                // Integer partitioning avoids floating drift and stays deterministic.
                let wStart = cueStartTicks + (total * a) / n
                let wEnd = cueStartTicks + (total * b) / n

                out.append(.init(
                    text: word,
                    speaker: cue.speaker,
                    sourceStartTicks: wStart,
                    sourceEndTicks: max(wStart, wEnd),
                    timelineStartTicks: wStart,
                    timelineEndTicks: max(wStart, wEnd)
                ))
            }
        }

        return out
    }

    private static func secondsToTicks(_ seconds: Double) -> Int64 {
        // Canonical tick scale: 60000.
        // We round to nearest tick deterministically.
        let ticks = seconds * 60000.0
        if !ticks.isFinite { return 0 }
        return Int64(ticks.rounded())
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
