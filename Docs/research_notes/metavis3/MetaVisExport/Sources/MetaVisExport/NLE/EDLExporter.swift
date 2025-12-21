// EDLExporter.swift
// MetaVisRender
//
// Exports timeline to Edit Decision List (EDL) format for NLE interchange

import Foundation
import CoreMedia

// MARK: - EDL Format

/// EDL format variants
public enum EDLFormat: String, Sendable, CaseIterable {
    case cmx3600 = "CMX 3600"
    case cmx340 = "CMX 340"
    case gvg = "GVG"
    case sony = "Sony"
    
    public var fileExtension: String { "edl" }
}

// MARK: - EDL Event

/// Represents a single edit event in an EDL
public struct EDLEvent: Sendable {
    /// Event number (3-digit, 001-999)
    public let eventNumber: Int
    
    /// Source reel/tape name (8 characters max)
    public let reelName: String
    
    /// Track type (V for video, A/A2 for audio, AA for both)
    public let track: EDLTrack
    
    /// Edit type (C=Cut, D=Dissolve, W=Wipe, K=Key)
    public let editType: EDLEditType
    
    /// Wipe number (for wipe transitions)
    public let wipeNumber: Int?
    
    /// Source in point
    public let sourceIn: CMTime
    
    /// Source out point
    public let sourceOut: CMTime
    
    /// Record in point (timeline position)
    public let recordIn: CMTime
    
    /// Record out point
    public let recordOut: CMTime
    
    /// Clip name (for comments)
    public let clipName: String?
    
    /// Source file path (for FROM CLIP NAME comment)
    public let sourceFile: String?
    
    /// Motion effect speed percentage
    public let motionSpeed: Double?
    
    public init(
        eventNumber: Int,
        reelName: String,
        track: EDLTrack = .both,
        editType: EDLEditType = .cut,
        wipeNumber: Int? = nil,
        sourceIn: CMTime,
        sourceOut: CMTime,
        recordIn: CMTime,
        recordOut: CMTime,
        clipName: String? = nil,
        sourceFile: String? = nil,
        motionSpeed: Double? = nil
    ) {
        self.eventNumber = eventNumber
        self.reelName = String(reelName.prefix(8)).uppercased()
        self.track = track
        self.editType = editType
        self.wipeNumber = wipeNumber
        self.sourceIn = sourceIn
        self.sourceOut = sourceOut
        self.recordIn = recordIn
        self.recordOut = recordOut
        self.clipName = clipName
        self.sourceFile = sourceFile
        self.motionSpeed = motionSpeed
    }
}

// MARK: - EDL Track

/// Track designator in EDL
public enum EDLTrack: String, Sendable {
    case video = "V"
    case audio1 = "A"
    case audio2 = "A2"
    case audio3 = "A3"
    case audio4 = "A4"
    case both = "AA"      // Audio and video
    case audioAll = "AA/V" // All audio + video
    
    public var description: String {
        switch self {
        case .video: return "V     "
        case .audio1: return "A     "
        case .audio2: return "A2    "
        case .audio3: return "A3    "
        case .audio4: return "A4    "
        case .both: return "AA    "
        case .audioAll: return "AA/V  "
        }
    }
}

// MARK: - EDL Edit Type

/// Edit/transition type in EDL
public enum EDLEditType: Sendable {
    case cut
    case dissolve(frames: Int)
    case wipe(number: Int, frames: Int)
    case key
    
    public var code: String {
        switch self {
        case .cut:
            return "C"
        case .dissolve:
            return "D"
        case .wipe(let number, _):
            return "W\(String(format: "%03d", number))"
        case .key:
            return "K"
        }
    }
    
    public var duration: Int {
        switch self {
        case .cut: return 0
        case .dissolve(let frames): return frames
        case .wipe(_, let frames): return frames
        case .key: return 0
        }
    }
}

// MARK: - EDL Exporter

import Foundation
import MetaVisCore

/// Exports timeline to CMX 3600 EDL format
public struct EDLExporter {
    
    /// Frame rate for timecode calculation
    public let frameRate: Double
    
    /// EDL format variant
    public let format: EDLFormat
    
    /// Title for the EDL
    public let title: String
    
    /// Drop frame timecode
    public let dropFrame: Bool
    
    public init(
        frameRate: Double = 24.0,
        format: EDLFormat = .cmx3600,
        title: String = "Untitled",
        dropFrame: Bool = false
    ) {
        self.frameRate = frameRate
        self.format = format
        self.title = title
        self.dropFrame = dropFrame
    }
    
    // MARK: - Export Methods
    
    /// Export events to EDL string
    public func export(events: [EDLEvent]) -> String {
        var lines: [String] = []
        
        // Header
        lines.append("TITLE: \(title)")
        lines.append("FCM: \(dropFrame ? "DROP FRAME" : "NON-DROP FRAME")")
        lines.append("")
        
        // Events
        for event in events {
            lines.append(contentsOf: formatEvent(event))
            lines.append("")
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Export events to file
    public func export(events: [EDLEvent], to url: URL) throws {
        let content = export(events: events)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    /*
    /// Export from RenderManifest
    /// Note: RenderManifest doesn't contain timeline data. 
    /// For timeline export, use export(events:) with EDLEvent array directly.
    /// This method exports scene elements as placeholder events for reference.
    public func export(from manifest: RenderManifest) -> String {
        var events: [EDLEvent] = []
        var eventNumber = 1
        
        // Export elements from scene as placeholder clips
        // Since RenderManifest doesn't have timeline tracks, we create events
        // from scene elements with assumed sequential positioning
        var currentTime = CMTime.zero
        
        guard let elements = manifest.elements else { return export(events: []) }
        for element in elements {
            let (elementId, name, duration) = extractElementInfo(element)
            let clipDuration = CMTime(seconds: duration, preferredTimescale: 24000)
            
            let event = EDLEvent(
                eventNumber: eventNumber,
                reelName: sanitizeReelName(elementId),
                track: .video,
                editType: .cut,
                sourceIn: .zero,
                sourceOut: clipDuration,
                recordIn: currentTime,
                recordOut: CMTimeAdd(currentTime, clipDuration),
                clipName: name,
                sourceFile: nil
            )
            events.append(event)
            eventNumber += 1
            currentTime = CMTimeAdd(currentTime, clipDuration)
        }
        
        return export(events: events)
    }
    
    private func extractElementInfo(_ element: ManifestElement) -> (id: String, name: String, duration: Double) {
        switch element {
        case .text(let textElement):
            let id = String(textElement.content.prefix(20).replacingOccurrences(of: " ", with: "_"))
            let name = textElement.content
            let duration = textElement.duration > 0 ? Double(textElement.duration) : 10.0
            return (id, name, duration)
        case .model(let modelElement):
            let name = URL(fileURLWithPath: modelElement.path).deletingPathExtension().lastPathComponent
            let source = modelElement.path
            return (String(name.prefix(20)), name, 10.0)
        case .solid(let solidElement):
            let name = solidElement.name ?? "Solid"
            let duration = solidElement.duration > 0 ? solidElement.duration : 10.0
            return ("SOLID", name, duration)
        }
    }
    */
    
    // MARK: - Private Methods
    
    private func formatEvent(_ event: EDLEvent) -> [String] {
        var lines: [String] = []
        
        // Main event line
        // Format: 001  REEL     V     C        00:00:00:00 00:00:10:00 01:00:00:00 01:00:10:00
        let eventNum = String(format: "%03d", event.eventNumber)
        let reel = event.reelName.padding(toLength: 8, withPad: " ", startingAt: 0)
        let track = event.track.description
        let edit = event.editType.code.padding(toLength: 8, withPad: " ", startingAt: 0)
        
        let sourceIn = formatTimecode(event.sourceIn)
        let sourceOut = formatTimecode(event.sourceOut)
        let recordIn = formatTimecode(event.recordIn)
        let recordOut = formatTimecode(event.recordOut)
        
        lines.append("\(eventNum)  \(reel) \(track)\(edit) \(sourceIn) \(sourceOut) \(recordIn) \(recordOut)")
        
        // Motion effect (M2 command)
        if let speed = event.motionSpeed, speed != 100.0 {
            let speedStr = String(format: "%.1f", speed)
            lines.append("M2   \(reel) \(speedStr)     \(sourceIn)")
        }
        
        // Clip name comment
        if let clipName = event.clipName {
            lines.append("* FROM CLIP NAME: \(clipName)")
        }
        
        // Source file comment
        if let sourceFile = event.sourceFile {
            lines.append("* SOURCE FILE: \(sourceFile)")
        }
        
        return lines
    }
    
    private func formatTimecode(_ time: CMTime) -> String {
        let totalSeconds = time.seconds
        let totalFrames = Int(totalSeconds * frameRate)
        
        let frames = totalFrames % Int(frameRate)
        let seconds = (totalFrames / Int(frameRate)) % 60
        let minutes = (totalFrames / Int(frameRate) / 60) % 60
        let hours = totalFrames / Int(frameRate) / 60 / 60
        
        let separator = dropFrame ? ";" : ":"
        
        return String(format: "%02d:%02d:%02d%@%02d", hours, minutes, seconds, separator, frames)
    }
    
    private func sanitizeReelName(_ name: String) -> String {
        // Remove invalid characters and limit to 8 chars
        let sanitized = name
            .replacingOccurrences(of: "[^A-Za-z0-9]", with: "", options: .regularExpression)
            .uppercased()
        
        if sanitized.isEmpty {
            return "BL"  // Black/blank
        }
        
        return String(sanitized.prefix(8))
    }
}

// MARK: - EDL Parser

/// Parses EDL files into events
public struct EDLParser {
    
    public let frameRate: Double
    
    public init(frameRate: Double = 24.0) {
        self.frameRate = frameRate
    }
    
    /// Parse EDL content
    public func parse(_ content: String) -> [EDLEvent] {
        var events: [EDLEvent] = []
        let lines = content.components(separatedBy: .newlines)
        
        var currentEventNumber: Int?
        var currentReel: String?
        var currentTrack: EDLTrack?
        var currentEditType: EDLEditType?
        var sourceIn: CMTime?
        var sourceOut: CMTime?
        var recordIn: CMTime?
        var recordOut: CMTime?
        var clipName: String?
        var sourceFile: String?
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and headers
            if trimmed.isEmpty || trimmed.hasPrefix("TITLE:") || trimmed.hasPrefix("FCM:") {
                continue
            }
            
            // Parse event line
            if let eventLine = parseEventLine(trimmed) {
                // Save previous event if exists
                if let num = currentEventNumber,
                   let reel = currentReel,
                   let track = currentTrack,
                   let edit = currentEditType,
                   let sIn = sourceIn,
                   let sOut = sourceOut,
                   let rIn = recordIn,
                   let rOut = recordOut {
                    events.append(EDLEvent(
                        eventNumber: num,
                        reelName: reel,
                        track: track,
                        editType: edit,
                        sourceIn: sIn,
                        sourceOut: sOut,
                        recordIn: rIn,
                        recordOut: rOut,
                        clipName: clipName,
                        sourceFile: sourceFile
                    ))
                    clipName = nil
                    sourceFile = nil
                }
                
                currentEventNumber = eventLine.eventNumber
                currentReel = eventLine.reel
                currentTrack = eventLine.track
                currentEditType = eventLine.editType
                sourceIn = eventLine.sourceIn
                sourceOut = eventLine.sourceOut
                recordIn = eventLine.recordIn
                recordOut = eventLine.recordOut
            }
            
            // Parse comments
            if trimmed.hasPrefix("* FROM CLIP NAME:") {
                clipName = String(trimmed.dropFirst("* FROM CLIP NAME:".count)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("* SOURCE FILE:") {
                sourceFile = String(trimmed.dropFirst("* SOURCE FILE:".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        
        // Save last event
        if let num = currentEventNumber,
           let reel = currentReel,
           let track = currentTrack,
           let edit = currentEditType,
           let sIn = sourceIn,
           let sOut = sourceOut,
           let rIn = recordIn,
           let rOut = recordOut {
            events.append(EDLEvent(
                eventNumber: num,
                reelName: reel,
                track: track,
                editType: edit,
                sourceIn: sIn,
                sourceOut: sOut,
                recordIn: rIn,
                recordOut: rOut,
                clipName: clipName,
                sourceFile: sourceFile
            ))
        }
        
        return events
    }
    
    /// Parse EDL file
    public func parse(fileAt url: URL) throws -> [EDLEvent] {
        let content = try String(contentsOf: url, encoding: .utf8)
        return parse(content)
    }
    
    private func parseEventLine(_ line: String) -> (
        eventNumber: Int,
        reel: String,
        track: EDLTrack,
        editType: EDLEditType,
        sourceIn: CMTime,
        sourceOut: CMTime,
        recordIn: CMTime,
        recordOut: CMTime
    )? {
        // Basic pattern: 001  REEL     V     C        00:00:00:00 00:00:10:00 01:00:00:00 01:00:10:00
        let pattern = #"^(\d{3})\s+(\w+)\s+(\S+)\s+(\S+)\s+(\d{2}[;:]?\d{2}[;:]?\d{2}[;:]?\d{2})\s+(\d{2}[;:]?\d{2}[;:]?\d{2}[;:]?\d{2})\s+(\d{2}[;:]?\d{2}[;:]?\d{2}[;:]?\d{2})\s+(\d{2}[;:]?\d{2}[;:]?\d{2}[;:]?\d{2})"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }
        
        func extract(_ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: line) else { return nil }
            return String(line[range])
        }
        
        guard let eventNumStr = extract(1), let eventNum = Int(eventNumStr),
              let reel = extract(2),
              let trackStr = extract(3),
              let editStr = extract(4),
              let sourceInStr = extract(5),
              let sourceOutStr = extract(6),
              let recordInStr = extract(7),
              let recordOutStr = extract(8) else {
            return nil
        }
        
        // Parse track
        let track: EDLTrack
        switch trackStr.trimmingCharacters(in: .whitespaces) {
        case "V": track = .video
        case "A": track = .audio1
        case "A2": track = .audio2
        case "AA": track = .both
        default: track = .both
        }
        
        // Parse edit type
        let editType: EDLEditType
        let editCode = editStr.trimmingCharacters(in: .whitespaces)
        if editCode == "C" {
            editType = .cut
        } else if editCode.hasPrefix("D") {
            let frames = Int(editCode.dropFirst()) ?? 0
            editType = .dissolve(frames: frames)
        } else if editCode.hasPrefix("W") {
            let wipeNum = Int(editCode.dropFirst().prefix(3)) ?? 0
            editType = .wipe(number: wipeNum, frames: 0)
        } else {
            editType = .cut
        }
        
        return (
            eventNumber: eventNum,
            reel: reel,
            track: track,
            editType: editType,
            sourceIn: parseTimecode(sourceInStr),
            sourceOut: parseTimecode(sourceOutStr),
            recordIn: parseTimecode(recordInStr),
            recordOut: parseTimecode(recordOutStr)
        )
    }
    
    private func parseTimecode(_ tc: String) -> CMTime {
        let parts = tc.replacingOccurrences(of: ";", with: ":").components(separatedBy: ":")
        guard parts.count == 4,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]),
              let seconds = Int(parts[2]),
              let frames = Int(parts[3]) else {
            return .zero
        }
        
        let totalFrames = hours * 3600 * Int(frameRate) +
                         minutes * 60 * Int(frameRate) +
                         seconds * Int(frameRate) +
                         frames
        
        return CMTime(value: CMTimeValue(totalFrames), timescale: CMTimeScale(frameRate))
    }
}
