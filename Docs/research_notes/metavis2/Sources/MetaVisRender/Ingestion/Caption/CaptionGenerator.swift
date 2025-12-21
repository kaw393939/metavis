// Sources/MetaVisRender/Ingestion/Caption/CaptionGenerator.swift
// Sprint 03: Generate SRT, VTT, and JSON caption files

import Foundation

// MARK: - Caption Format

public enum CaptionFormat: String, Codable, Sendable, CaseIterable {
    case srt = "srt"
    case vtt = "vtt"
    case json = "json"
    case txt = "txt"
    
    public var fileExtension: String { rawValue }
    
    public var mimeType: String {
        switch self {
        case .srt: return "application/x-subrip"
        case .vtt: return "text/vtt"
        case .json: return "application/json"
        case .txt: return "text/plain"
        }
    }
}

// MARK: - Caption Style

public struct CaptionStyle: Codable, Sendable {
    public let maxLineLength: Int
    public let maxLines: Int
    public let includeTimestamps: Bool
    public let includeSpeakerLabels: Bool
    public let speakerLabelFormat: SpeakerLabelFormat
    public let wordBreaking: WordBreaking
    
    public enum SpeakerLabelFormat: String, Codable, Sendable {
        case brackets = "[Speaker]"      // [SPEAKER_00]
        case colon = "Speaker:"          // SPEAKER_00:
        case parentheses = "(Speaker)"   // (SPEAKER_00)
        case vttVoice = "voice"          // <v SPEAKER_00>
        case none = "none"
    }
    
    public enum WordBreaking: String, Codable, Sendable {
        case word       // Break at word boundaries
        case sentence   // Break at sentence boundaries
        case time       // Break at time intervals
    }
    
    public init(
        maxLineLength: Int = 42,
        maxLines: Int = 2,
        includeTimestamps: Bool = true,
        includeSpeakerLabels: Bool = true,
        speakerLabelFormat: SpeakerLabelFormat = .brackets,
        wordBreaking: WordBreaking = .word
    ) {
        self.maxLineLength = maxLineLength
        self.maxLines = maxLines
        self.includeTimestamps = includeTimestamps
        self.includeSpeakerLabels = includeSpeakerLabels
        self.speakerLabelFormat = speakerLabelFormat
        self.wordBreaking = wordBreaking
    }
    
    public static let `default` = CaptionStyle()
    
    public static let youtube = CaptionStyle(
        maxLineLength: 42,
        maxLines: 2,
        speakerLabelFormat: .brackets
    )
    
    public static let broadcast = CaptionStyle(
        maxLineLength: 32,
        maxLines: 2,
        speakerLabelFormat: .none
    )
    
    public static let karaoke = CaptionStyle(
        maxLineLength: 60,
        maxLines: 1,
        speakerLabelFormat: .none,
        wordBreaking: .word
    )
}

// MARK: - Caption Entry

public struct CaptionEntry: Codable, Sendable {
    public let index: Int
    public let start: Double
    public let end: Double
    public let text: String
    public let speakerId: String?
    
    public init(
        index: Int,
        start: Double,
        end: Double,
        text: String,
        speakerId: String? = nil
    ) {
        self.index = index
        self.start = start
        self.end = end
        self.text = text
        self.speakerId = speakerId
    }
    
    public var duration: Double { end - start }
}

// MARK: - Caption Generator

public struct CaptionGenerator {
    
    private let style: CaptionStyle
    private let speakerNames: [String: String]
    
    public init(style: CaptionStyle = .default, speakerNames: [String: String] = [:]) {
        self.style = style
        self.speakerNames = speakerNames
    }
    
    // MARK: - Generate from Transcript
    
    /// Generate captions from a transcript
    public func generate(from transcript: Transcript, format: CaptionFormat) -> String {
        let entries = buildEntries(from: transcript)
        
        switch format {
        case .srt:
            return generateSRT(entries: entries)
        case .vtt:
            return generateVTT(entries: entries)
        case .json:
            return generateJSON(entries: entries, transcript: transcript)
        case .txt:
            return generatePlainText(entries: entries)
        }
    }
    
    /// Generate captions and write to file
    public func generate(
        from transcript: Transcript,
        format: CaptionFormat,
        to outputURL: URL
    ) throws {
        let content = generate(from: transcript, format: format)
        try content.write(to: outputURL, atomically: true, encoding: .utf8)
    }
    
    /// Generate multiple formats at once
    public func generateAll(
        from transcript: Transcript,
        formats: [CaptionFormat],
        outputDirectory: URL,
        baseName: String
    ) throws -> [URL] {
        var outputURLs: [URL] = []
        
        for format in formats {
            let url = outputDirectory.appendingPathComponent("\(baseName).\(format.fileExtension)")
            try generate(from: transcript, format: format, to: url)
            outputURLs.append(url)
        }
        
        return outputURLs
    }
    
    // MARK: - Build Entries
    
    private func buildEntries(from transcript: Transcript) -> [CaptionEntry] {
        var entries: [CaptionEntry] = []
        var index = 1
        
        for segment in transcript.segments {
            // Split segment if too long
            let lines = splitIntoLines(segment.text)
            
            if lines.count <= style.maxLines {
                // Single entry
                entries.append(CaptionEntry(
                    index: index,
                    start: segment.start,
                    end: segment.end,
                    text: lines.joined(separator: "\n"),
                    speakerId: segment.speakerId
                ))
                index += 1
            } else {
                // Multiple entries needed
                let entriesNeeded = (lines.count + style.maxLines - 1) / style.maxLines
                let duration = segment.duration / Double(entriesNeeded)
                
                for i in 0..<entriesNeeded {
                    let startLine = i * style.maxLines
                    let endLine = min(startLine + style.maxLines, lines.count)
                    let entryLines = Array(lines[startLine..<endLine])
                    
                    entries.append(CaptionEntry(
                        index: index,
                        start: segment.start + Double(i) * duration,
                        end: segment.start + Double(i + 1) * duration,
                        text: entryLines.joined(separator: "\n"),
                        speakerId: segment.speakerId
                    ))
                    index += 1
                }
            }
        }
        
        return entries
    }
    
    private func splitIntoLines(_ text: String) -> [String] {
        var lines: [String] = []
        var currentLine = ""
        
        let words = text.split(separator: " ").map(String.init)
        
        for word in words {
            if currentLine.isEmpty {
                currentLine = word
            } else if currentLine.count + 1 + word.count <= style.maxLineLength {
                currentLine += " " + word
            } else {
                lines.append(currentLine)
                currentLine = word
            }
        }
        
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        
        return lines
    }
    
    // MARK: - SRT Format
    
    private func generateSRT(entries: [CaptionEntry]) -> String {
        var output = ""
        
        for entry in entries {
            output += "\(entry.index)\n"
            output += "\(formatSRTTime(entry.start)) --> \(formatSRTTime(entry.end))\n"
            
            if style.includeSpeakerLabels, let speakerId = entry.speakerId {
                let name = speakerNames[speakerId] ?? speakerId
                output += formatSpeakerLabel(name, format: style.speakerLabelFormat)
            }
            
            output += entry.text + "\n\n"
        }
        
        return output
    }
    
    private func formatSRTTime(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, millis)
    }
    
    // MARK: - VTT Format
    
    private func generateVTT(entries: [CaptionEntry]) -> String {
        var output = "WEBVTT\n\n"
        
        for entry in entries {
            output += "\(formatVTTTime(entry.start)) --> \(formatVTTTime(entry.end))\n"
            
            if style.includeSpeakerLabels && style.speakerLabelFormat == .vttVoice,
               let speakerId = entry.speakerId {
                let name = speakerNames[speakerId] ?? speakerId
                output += "<v \(name)>"
            } else if style.includeSpeakerLabels, let speakerId = entry.speakerId {
                let name = speakerNames[speakerId] ?? speakerId
                output += formatSpeakerLabel(name, format: style.speakerLabelFormat)
            }
            
            output += entry.text + "\n\n"
        }
        
        return output
    }
    
    private func formatVTTTime(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d.%03d", hours, minutes, secs, millis)
        } else {
            return String(format: "%02d:%02d.%03d", minutes, secs, millis)
        }
    }
    
    // MARK: - JSON Format
    
    private func generateJSON(entries: [CaptionEntry], transcript: Transcript) -> String {
        let output: [String: Any] = [
            "version": "1.0",
            "language": transcript.language,
            "duration": transcript.duration,
            "engine": transcript.engine.rawValue,
            "entries": entries.map { entry -> [String: Any] in
                var dict: [String: Any] = [
                    "index": entry.index,
                    "start": entry.start,
                    "end": entry.end,
                    "text": entry.text
                ]
                if let speaker = entry.speakerId {
                    dict["speaker"] = speakerNames[speaker] ?? speaker
                }
                return dict
            }
        ]
        
        guard let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        
        return json
    }
    
    // MARK: - Plain Text Format
    
    private func generatePlainText(entries: [CaptionEntry]) -> String {
        var output = ""
        var currentSpeaker: String? = nil
        
        for entry in entries {
            if style.includeSpeakerLabels, let speaker = entry.speakerId, speaker != currentSpeaker {
                let name = speakerNames[speaker] ?? speaker
                output += "\n[\(name)]\n"
                currentSpeaker = speaker
            }
            
            output += entry.text + " "
        }
        
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Helper
    
    private func formatSpeakerLabel(_ name: String, format: CaptionStyle.SpeakerLabelFormat) -> String {
        switch format {
        case .brackets:
            return "[\(name)] "
        case .colon:
            return "\(name): "
        case .parentheses:
            return "(\(name)) "
        case .vttVoice:
            return ""  // Handled separately in VTT
        case .none:
            return ""
        }
    }
}

// MARK: - Word-Level Captions (Karaoke)

extension CaptionGenerator {
    
    /// Generate word-by-word JSON for karaoke-style rendering
    public func generateWordTiming(from transcript: Transcript) -> String {
        let words = transcript.words.map { word -> [String: Any] in
            var dict: [String: Any] = [
                "word": word.word,
                "start": word.start,
                "end": word.end,
                "confidence": word.confidence
            ]
            if let speaker = word.speakerId {
                dict["speaker"] = speakerNames[speaker] ?? speaker
            }
            return dict
        }
        
        let output: [String: Any] = [
            "version": "1.0",
            "type": "word_timing",
            "language": transcript.language,
            "duration": transcript.duration,
            "words": words
        ]
        
        guard let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        
        return json
    }
}
