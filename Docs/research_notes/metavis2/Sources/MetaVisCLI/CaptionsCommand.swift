// CaptionsCommand.swift
// MetaVisCLI
//
// CLI commands for generating and converting caption files

import ArgumentParser
import Foundation
import MetaVisRender

struct Captions: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "captions",
        abstract: "Generate and convert caption files",
        subcommands: [
            CaptionsGenerate.self,
            CaptionsConvert.self
        ],
        defaultSubcommand: CaptionsGenerate.self
    )
}

// MARK: - Generate Subcommand

struct CaptionsGenerate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate",
        abstract: "Generate captions from a transcript"
    )
    
    @Argument(help: "Path to transcript JSON file")
    var transcript: String
    
    @Option(name: .shortAndLong, help: "Output file path")
    var output: String
    
    @Option(name: .shortAndLong, help: "Output format: srt, vtt, json, txt")
    var format: String = "srt"
    
    @Option(name: .long, help: "Caption style: youtube, broadcast, karaoke")
    var style: String = "youtube"
    
    @Option(name: .long, help: "Maximum characters per line")
    var maxChars: Int = 42
    
    @Option(name: .long, help: "Maximum lines per caption")
    var maxLines: Int = 2
    
    @Flag(name: .long, help: "Include speaker labels")
    var speakers: Bool = false
    
    @Option(name: .long, help: "Comma-separated speaker names to replace IDs")
    var speakerNames: String?
    
    mutating func run() async throws {
        let transcriptURL = URL(fileURLWithPath: transcript)
        
        guard FileManager.default.fileExists(atPath: transcript) else {
            throw ValidationError("Transcript file not found: \(transcript)")
        }
        
        print("Generating captions from: \(transcriptURL.lastPathComponent)")
        
        // Load transcript
        let data = try Data(contentsOf: transcriptURL)
        let loadedTranscript = try JSONDecoder().decode(Transcript.self, from: data)
        
        // Parse format
        let captionFormat = parseCaptionFormat(format)
        let captionStyle = parseCaptionStyle(style, maxChars: maxChars, maxLines: maxLines, speakers: speakers)
        
        // Parse speaker names if provided
        var speakerNameMap: [String: String] = [:]
        if let names = speakerNames {
            let nameList = names.split(separator: ",").map(String.init)
            for (index, name) in nameList.enumerated() {
                speakerNameMap["SPEAKER_\(String(format: "%02d", index))"] = name.trimmingCharacters(in: .whitespaces)
            }
        }
        
        // Configure generator
        let generator = CaptionGenerator(style: captionStyle, speakerNames: speakerNameMap)
        
        // Generate captions
        let outputContent = generator.generate(from: loadedTranscript, format: captionFormat)
        
        // Write output
        let outputURL = URL(fileURLWithPath: output)
        try outputContent.write(to: outputURL, atomically: true, encoding: .utf8)
        
        print("✅ Captions saved to: \(output)")
        print("   Format: \(format.uppercased())")
        print("   Cues: \(countCues(in: outputContent, format: captionFormat))")
    }
    
    private func parseCaptionFormat(_ format: String) -> CaptionFormat {
        switch format.lowercased() {
        case "srt":
            return .srt
        case "vtt", "webvtt":
            return .vtt
        case "json":
            return .json
        case "txt", "text":
            return .txt
        default:
            return .srt
        }
    }
    
    private func parseCaptionStyle(_ style: String, maxChars: Int, maxLines: Int, speakers: Bool) -> CaptionStyle {
        switch style.lowercased() {
        case "youtube":
            return CaptionStyle(
                maxLineLength: maxChars,
                maxLines: maxLines,
                includeSpeakerLabels: speakers
            )
        case "broadcast":
            return CaptionStyle(
                maxLineLength: 32,
                maxLines: maxLines,
                includeSpeakerLabels: false
            )
        case "karaoke":
            return CaptionStyle(
                maxLineLength: 60,
                maxLines: 1,
                includeSpeakerLabels: false,
                wordBreaking: .word
            )
        default:
            return CaptionStyle(
                maxLineLength: maxChars,
                maxLines: maxLines,
                includeSpeakerLabels: speakers
            )
        }
    }
    
    private func countCues(in content: String, format: CaptionFormat) -> Int {
        switch format {
        case .srt, .vtt:
            // Count lines that contain "-->" (timing markers)
            return content.components(separatedBy: "\n")
                .filter { $0.contains("-->") }
                .count
        case .json:
            // Count "start" occurrences
            return content.components(separatedBy: "\"start\"").count - 1
        case .txt:
            return 1 // Plain text is one block
        }
    }
}

// MARK: - Convert Subcommand

struct CaptionsConvert: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "convert",
        abstract: "Convert between caption formats"
    )
    
    @Argument(help: "Input caption file")
    var input: String
    
    @Option(name: .shortAndLong, help: "Output file path")
    var output: String
    
    @Option(name: .shortAndLong, help: "Output format: srt, vtt, json, txt")
    var format: String = "vtt"
    
    mutating func run() async throws {
        let inputURL = URL(fileURLWithPath: input)
        
        guard FileManager.default.fileExists(atPath: input) else {
            throw ValidationError("Input file not found: \(input)")
        }
        
        print("Converting: \(inputURL.lastPathComponent) → \(format.uppercased())")
        
        // Read input
        let inputContent = try String(contentsOf: inputURL, encoding: .utf8)
        
        // Detect input format
        let inputFormat = detectFormat(inputContent, filename: input)
        
        // Parse to intermediate representation
        let cues = try parseCaptions(inputContent, format: inputFormat)
        
        // Convert to output format
        let outputFormat = parseOutputFormat(format)
        let outputContent = formatCaptions(cues, format: outputFormat)
        
        // Write output
        let outputURL = URL(fileURLWithPath: output)
        try outputContent.write(to: outputURL, atomically: true, encoding: .utf8)
        
        print("✅ Converted to: \(output)")
        print("   Cues: \(cues.count)")
    }
    
    private func detectFormat(_ content: String, filename: String) -> String {
        if filename.hasSuffix(".srt") {
            return "srt"
        } else if filename.hasSuffix(".vtt") || content.hasPrefix("WEBVTT") {
            return "vtt"
        } else if filename.hasSuffix(".json") || content.hasPrefix("{") {
            return "json"
        }
        return "srt"
    }
    
    private func parseOutputFormat(_ format: String) -> CaptionFormat {
        switch format.lowercased() {
        case "srt":
            return .srt
        case "vtt", "webvtt":
            return .vtt
        case "json":
            return .json
        case "txt", "text":
            return .txt
        default:
            return .vtt
        }
    }
    
    private func parseCaptions(_ content: String, format: String) throws -> [CaptionCue] {
        var cues: [CaptionCue] = []
        
        switch format {
        case "srt":
            cues = try parseSRT(content)
        case "vtt":
            cues = try parseVTT(content)
        case "json":
            cues = try parseJSON(content)
        default:
            throw ValidationError("Unknown input format: \(format)")
        }
        
        return cues
    }
    
    private func parseSRT(_ content: String) throws -> [CaptionCue] {
        var cues: [CaptionCue] = []
        let blocks = content.components(separatedBy: "\n\n")
        
        for block in blocks {
            let lines = block.components(separatedBy: "\n")
            guard lines.count >= 3 else { continue }
            
            // Parse timing line
            let timingLine = lines[1]
            guard let (start, end) = parseTimingLine(timingLine, isSRT: true) else { continue }
            
            // Get text (remaining lines)
            let text = lines.dropFirst(2).joined(separator: "\n")
            
            cues.append(CaptionCue(
                index: cues.count + 1,
                startTime: start,
                endTime: end,
                text: text
            ))
        }
        
        return cues
    }
    
    private func parseVTT(_ content: String) throws -> [CaptionCue] {
        var cues: [CaptionCue] = []
        let blocks = content.components(separatedBy: "\n\n")
        
        for block in blocks {
            // Skip WEBVTT header
            if block.hasPrefix("WEBVTT") { continue }
            
            let lines = block.components(separatedBy: "\n")
            
            // Find timing line
            var timingIndex = 0
            for (index, line) in lines.enumerated() {
                if line.contains("-->") {
                    timingIndex = index
                    break
                }
            }
            
            guard timingIndex < lines.count else { continue }
            
            let timingLine = lines[timingIndex]
            guard let (start, end) = parseTimingLine(timingLine, isSRT: false) else { continue }
            
            // Get text (remaining lines after timing)
            let text = lines.dropFirst(timingIndex + 1).joined(separator: "\n")
            guard !text.isEmpty else { continue }
            
            cues.append(CaptionCue(
                index: cues.count + 1,
                startTime: start,
                endTime: end,
                text: text
            ))
        }
        
        return cues
    }
    
    private func parseJSON(_ content: String) throws -> [CaptionCue] {
        struct JSONCue: Decodable {
            let start: Double
            let end: Double
            let text: String
        }
        
        struct JSONCaptions: Decodable {
            let cues: [JSONCue]?
            let segments: [JSONCue]?
        }
        
        let data = content.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(JSONCaptions.self, from: data)
        
        let jsonCues = decoded.cues ?? decoded.segments ?? []
        
        return jsonCues.enumerated().map { index, cue in
            CaptionCue(
                index: index + 1,
                startTime: cue.start,
                endTime: cue.end,
                text: cue.text
            )
        }
    }
    
    private func parseTimingLine(_ line: String, isSRT: Bool) -> (Double, Double)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }
        
        let startStr = parts[0].trimmingCharacters(in: .whitespaces)
        let endStr = parts[1].trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ").first ?? ""
        
        guard let start = parseTimestamp(startStr, isSRT: isSRT),
              let end = parseTimestamp(endStr, isSRT: isSRT) else {
            return nil
        }
        
        return (start, end)
    }
    
    private func parseTimestamp(_ timestamp: String, isSRT: Bool) -> Double? {
        // SRT: 00:00:01,234
        // VTT: 00:00:01.234 or 00:01.234
        
        let separator = isSRT ? "," : "."
        let parts = timestamp.replacingOccurrences(of: separator, with: ":").split(separator: ":")
        
        guard parts.count >= 3 else { return nil }
        
        var hours: Double = 0
        var minutes: Double = 0
        var seconds: Double = 0
        var millis: Double = 0
        
        if parts.count == 4 {
            hours = Double(parts[0]) ?? 0
            minutes = Double(parts[1]) ?? 0
            seconds = Double(parts[2]) ?? 0
            millis = Double(parts[3]) ?? 0
        } else if parts.count == 3 {
            if parts[0].count <= 2 && (Double(parts[0]) ?? 0) < 60 {
                // mm:ss.mmm format
                minutes = Double(parts[0]) ?? 0
                seconds = Double(parts[1]) ?? 0
                millis = Double(parts[2]) ?? 0
            } else {
                hours = Double(parts[0]) ?? 0
                minutes = Double(parts[1]) ?? 0
                seconds = Double(parts[2]) ?? 0
            }
        }
        
        return hours * 3600 + minutes * 60 + seconds + millis / 1000
    }
    
    private func formatCaptions(_ cues: [CaptionCue], format: CaptionFormat) -> String {
        switch format {
        case .srt:
            return formatAsSRT(cues)
        case .vtt:
            return formatAsVTT(cues)
        case .json:
            return formatAsJSON(cues)
        case .txt:
            return formatAsTXT(cues)
        }
    }
    
    private func formatAsSRT(_ cues: [CaptionCue]) -> String {
        var output = ""
        
        for cue in cues {
            output += "\(cue.index)\n"
            output += "\(formatSRTTime(cue.startTime)) --> \(formatSRTTime(cue.endTime))\n"
            output += "\(cue.text)\n\n"
        }
        
        return output
    }
    
    private func formatAsVTT(_ cues: [CaptionCue]) -> String {
        var output = "WEBVTT\n\n"
        
        for cue in cues {
            output += "\(formatVTTTime(cue.startTime)) --> \(formatVTTTime(cue.endTime))\n"
            output += "\(cue.text)\n\n"
        }
        
        return output
    }
    
    private func formatAsJSON(_ cues: [CaptionCue]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        struct JSONOutput: Encodable {
            let cues: [JSONCue]
        }
        
        struct JSONCue: Encodable {
            let index: Int
            let start: Double
            let end: Double
            let text: String
        }
        
        let jsonCues = cues.map { JSONCue(index: $0.index, start: $0.startTime, end: $0.endTime, text: $0.text) }
        let data = try? encoder.encode(JSONOutput(cues: jsonCues))
        return String(data: data ?? Data(), encoding: .utf8) ?? "{}"
    }
    
    private func formatAsTXT(_ cues: [CaptionCue]) -> String {
        return cues.map { $0.text }.joined(separator: "\n\n")
    }
    
    private func formatSRTTime(_ seconds: Double) -> String {
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
        let millis = Int((seconds - floor(seconds)) * 1000)
        
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, millis)
    }
    
    private func formatVTTTime(_ seconds: Double) -> String {
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
        let millis = Int((seconds - floor(seconds)) * 1000)
        
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, secs, millis)
    }
}

// MARK: - Helper Types

struct CaptionCue {
    let index: Int
    let startTime: Double
    let endTime: Double
    let text: String
}
