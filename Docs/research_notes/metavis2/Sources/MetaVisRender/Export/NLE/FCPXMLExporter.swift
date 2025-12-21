// FCPXMLExporter.swift
// MetaVisRender
//
// Exports timeline to Final Cut Pro XML (FCPXML) format

import Foundation
import CoreMedia

// MARK: - FCPXML Version

/// Supported FCPXML versions
public enum FCPXMLVersion: String, Sendable {
    case v1_8 = "1.8"
    case v1_9 = "1.9"
    case v1_10 = "1.10"
    case v1_11 = "1.11"
    
    var dtdVersion: String {
        return rawValue
    }
}

// MARK: - FCPXML Resource

/// A media resource referenced in the FCPXML
public struct FCPXMLResource: Sendable {
    public let id: String
    public let name: String
    public let src: URL?
    public let duration: CMTime
    public let hasVideo: Bool
    public let hasAudio: Bool
    public let format: String?
    public let width: Int?
    public let height: Int?
    public let frameRate: Double?
    public let audioChannels: Int?
    public let audioSampleRate: Int?
    
    public init(
        id: String,
        name: String,
        src: URL? = nil,
        duration: CMTime = .zero,
        hasVideo: Bool = true,
        hasAudio: Bool = true,
        format: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        frameRate: Double? = nil,
        audioChannels: Int? = nil,
        audioSampleRate: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.src = src
        self.duration = duration
        self.hasVideo = hasVideo
        self.hasAudio = hasAudio
        self.format = format
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.audioChannels = audioChannels
        self.audioSampleRate = audioSampleRate
    }
}

// MARK: - FCPXML Clip

/// A clip in the FCPXML timeline
public struct FCPXMLClip: Sendable {
    public let name: String
    public let resourceId: String
    public let offset: CMTime        // Position on timeline
    public let duration: CMTime      // Duration on timeline
    public let start: CMTime         // Source in point
    public let enabled: Bool
    public let audioRole: String?
    public let videoRole: String?
    
    // Effects
    public let opacity: Double?
    public let position: (x: Double, y: Double)?
    public let scale: Double?
    public let rotation: Double?
    
    // Audio
    public let volume: Double?
    public let pan: Double?
    
    public init(
        name: String,
        resourceId: String,
        offset: CMTime,
        duration: CMTime,
        start: CMTime = .zero,
        enabled: Bool = true,
        audioRole: String? = nil,
        videoRole: String? = nil,
        opacity: Double? = nil,
        position: (x: Double, y: Double)? = nil,
        scale: Double? = nil,
        rotation: Double? = nil,
        volume: Double? = nil,
        pan: Double? = nil
    ) {
        self.name = name
        self.resourceId = resourceId
        self.offset = offset
        self.duration = duration
        self.start = start
        self.enabled = enabled
        self.audioRole = audioRole
        self.videoRole = videoRole
        self.opacity = opacity
        self.position = position
        self.scale = scale
        self.rotation = rotation
        self.volume = volume
        self.pan = pan
    }
}

// MARK: - FCPXML Exporter

/// Exports timelines to FCPXML format
public struct FCPXMLExporter {
    
    /// FCPXML version to export
    public let version: FCPXMLVersion
    
    /// Project name
    public let projectName: String
    
    /// Frame rate (frames per second)
    public let frameRate: Double
    
    /// Frame duration (e.g., "1001/30000s" for 29.97fps)
    public let frameDuration: String
    
    /// Video resolution
    public let width: Int
    public let height: Int
    
    /// Audio sample rate
    public let audioSampleRate: Int
    
    /// Audio channels
    public let audioChannels: Int
    
    public init(
        version: FCPXMLVersion = .v1_10,
        projectName: String = "Untitled",
        frameRate: Double = 24.0,
        width: Int = 1920,
        height: Int = 1080,
        audioSampleRate: Int = 48000,
        audioChannels: Int = 2
    ) {
        self.version = version
        self.projectName = projectName
        self.frameRate = frameRate
        self.frameDuration = Self.calculateFrameDuration(fps: frameRate)
        self.width = width
        self.height = height
        self.audioSampleRate = audioSampleRate
        self.audioChannels = audioChannels
    }
    
    // MARK: - Export Methods
    
    /// Export resources and clips to FCPXML
    public func export(
        resources: [FCPXMLResource],
        clips: [FCPXMLClip],
        duration: CMTime
    ) -> String {
        let xml = XMLDocument()
        
        // Root fcpxml element
        let root = XMLElement(name: "fcpxml")
        root.addAttribute(XMLNode.attribute(withName: "version", stringValue: version.rawValue) as! XMLNode)
        xml.setRootElement(root)
        
        // Resources
        let resourcesElement = XMLElement(name: "resources")
        
        // Add format
        let formatElement = createFormatElement()
        resourcesElement.addChild(formatElement)
        
        // Add media resources
        for resource in resources {
            let assetElement = createAssetElement(resource)
            resourcesElement.addChild(assetElement)
        }
        
        root.addChild(resourcesElement)
        
        // Library > Event > Project structure
        let library = XMLElement(name: "library")
        let event = XMLElement(name: "event")
        event.addAttribute(XMLNode.attribute(withName: "name", stringValue: projectName) as! XMLNode)
        
        let project = createProjectElement(clips: clips, duration: duration)
        event.addChild(project)
        library.addChild(event)
        root.addChild(library)
        
        // Format with declaration and DTD
        let declaration = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        let dtd = "<!DOCTYPE fcpxml>\n"
        
        let xmlOptions: XMLNode.Options = [.nodePrettyPrint, .nodeCompactEmptyElement]
        return declaration + dtd + (xml.xmlString(options: xmlOptions))
    }
    
    /// Export to file
    public func export(
        resources: [FCPXMLResource],
        clips: [FCPXMLClip],
        duration: CMTime,
        to url: URL
    ) throws {
        let content = export(resources: resources, clips: clips, duration: duration)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    /// Export from RenderManifest
    /// Note: RenderManifest doesn't contain timeline/assets data.
    /// For full timeline export, use export(resources:clips:duration:) directly.
    /// This method exports scene elements as placeholder clips for reference.
    public func export(from manifest: RenderManifest) -> String {
        var resources: [FCPXMLResource] = []
        var clips: [FCPXMLClip] = []
        
        // Build resources and clips from scene elements
        // Since RenderManifest doesn't have timeline tracks, we create 
        // sequential clips from scene elements
        var currentOffset = CMTime.zero
        
        guard let elements = manifest.elements else { return export(resources: [], clips: [], duration: .zero) }
        for (index, element) in elements.enumerated() {
            let resourceId = "r\(index + 1)"
            let (name, source, duration, opacity, scale) = extractElementInfo(element)
            
            // Create resource from element
            let resource = FCPXMLResource(
                id: resourceId,
                name: name,
                src: source.flatMap { URL(string: $0) },
                hasVideo: true,
                hasAudio: true,
                width: width,
                height: height,
                frameRate: frameRate
            )
            resources.append(resource)
            
            // Create clip
            let clipDuration = CMTime(seconds: duration, preferredTimescale: 24000)
            
            let clip = FCPXMLClip(
                name: name,
                resourceId: resourceId,
                offset: currentOffset,
                duration: clipDuration,
                start: .zero,
                opacity: opacity,
                scale: scale
            )
            clips.append(clip)
            
            currentOffset = CMTimeAdd(currentOffset, clipDuration)
        }
        
        return export(resources: resources, clips: clips, duration: currentOffset)
    }
    
    private func extractElementInfo(_ element: ManifestElement) -> (name: String, source: String?, duration: Double, opacity: Double?, scale: Double?) {
        switch element {
        case .text(let textElement):
            let name = textElement.content
            let duration = textElement.duration > 0 ? Double(textElement.duration) : 10.0
            return (name, nil, duration, nil, nil)
        case .model(let modelElement):
            let name = URL(fileURLWithPath: modelElement.path).deletingPathExtension().lastPathComponent
            let source = modelElement.path
            let scale = Double(modelElement.scale.x) // Use x component as uniform scale
            return (name, source, 10.0, nil, scale)
        }
    }
    
    // MARK: - Private Methods
    
    private static func calculateFrameDuration(fps: Double) -> String {
        // Common frame rates with their durations
        switch fps {
        case 23.976, 23.98:
            return "1001/24000s"
        case 24:
            return "100/2400s"
        case 25:
            return "100/2500s"
        case 29.97:
            return "1001/30000s"
        case 30:
            return "100/3000s"
        case 50:
            return "100/5000s"
        case 59.94:
            return "1001/60000s"
        case 60:
            return "100/6000s"
        default:
            // Calculate for arbitrary frame rate
            let num = 1000
            let den = Int(fps * 1000)
            return "\(num)/\(den)s"
        }
    }
    
    private func createFormatElement() -> XMLElement {
        let format = XMLElement(name: "format")
        format.addAttribute(XMLNode.attribute(withName: "id", stringValue: "r0") as! XMLNode)
        format.addAttribute(XMLNode.attribute(withName: "name", stringValue: "FFVideoFormat\(width)x\(height)p\(Int(frameRate))") as! XMLNode)
        format.addAttribute(XMLNode.attribute(withName: "frameDuration", stringValue: frameDuration) as! XMLNode)
        format.addAttribute(XMLNode.attribute(withName: "width", stringValue: "\(width)") as! XMLNode)
        format.addAttribute(XMLNode.attribute(withName: "height", stringValue: "\(height)") as! XMLNode)
        format.addAttribute(XMLNode.attribute(withName: "colorSpace", stringValue: "1-1-1 (Rec. 709)") as! XMLNode)
        return format
    }
    
    private func createAssetElement(_ resource: FCPXMLResource) -> XMLElement {
        let asset = XMLElement(name: "asset")
        asset.addAttribute(XMLNode.attribute(withName: "id", stringValue: resource.id) as! XMLNode)
        asset.addAttribute(XMLNode.attribute(withName: "name", stringValue: resource.name) as! XMLNode)
        
        if let src = resource.src {
            asset.addAttribute(XMLNode.attribute(withName: "src", stringValue: src.absoluteString) as! XMLNode)
        }
        
        if resource.duration != .zero {
            asset.addAttribute(XMLNode.attribute(withName: "duration", stringValue: formatTime(resource.duration)) as! XMLNode)
        }
        
        asset.addAttribute(XMLNode.attribute(withName: "hasVideo", stringValue: resource.hasVideo ? "1" : "0") as! XMLNode)
        asset.addAttribute(XMLNode.attribute(withName: "hasAudio", stringValue: resource.hasAudio ? "1" : "0") as! XMLNode)
        asset.addAttribute(XMLNode.attribute(withName: "format", stringValue: "r0") as! XMLNode)
        
        if resource.hasAudio {
            asset.addAttribute(XMLNode.attribute(withName: "audioSources", stringValue: "1") as! XMLNode)
            asset.addAttribute(XMLNode.attribute(withName: "audioChannels", stringValue: "\(resource.audioChannels ?? audioChannels)") as! XMLNode)
            asset.addAttribute(XMLNode.attribute(withName: "audioRate", stringValue: "\(resource.audioSampleRate ?? audioSampleRate)") as! XMLNode)
        }
        
        return asset
    }
    
    private func createProjectElement(clips: [FCPXMLClip], duration: CMTime) -> XMLElement {
        let project = XMLElement(name: "project")
        project.addAttribute(XMLNode.attribute(withName: "name", stringValue: projectName) as! XMLNode)
        
        // Sequence
        let sequence = XMLElement(name: "sequence")
        sequence.addAttribute(XMLNode.attribute(withName: "format", stringValue: "r0") as! XMLNode)
        sequence.addAttribute(XMLNode.attribute(withName: "duration", stringValue: formatTime(duration)) as! XMLNode)
        
        // Spine (primary storyline)
        let spine = XMLElement(name: "spine")
        
        // Add clips to spine
        for clip in clips.sorted(by: { $0.offset < $1.offset }) {
            let clipElement = createClipElement(clip)
            spine.addChild(clipElement)
        }
        
        sequence.addChild(spine)
        project.addChild(sequence)
        
        return project
    }
    
    private func createClipElement(_ clip: FCPXMLClip) -> XMLElement {
        let clipElement = XMLElement(name: "asset-clip")
        clipElement.addAttribute(XMLNode.attribute(withName: "name", stringValue: clip.name) as! XMLNode)
        clipElement.addAttribute(XMLNode.attribute(withName: "ref", stringValue: clip.resourceId) as! XMLNode)
        clipElement.addAttribute(XMLNode.attribute(withName: "offset", stringValue: formatTime(clip.offset)) as! XMLNode)
        clipElement.addAttribute(XMLNode.attribute(withName: "duration", stringValue: formatTime(clip.duration)) as! XMLNode)
        
        if clip.start != .zero {
            clipElement.addAttribute(XMLNode.attribute(withName: "start", stringValue: formatTime(clip.start)) as! XMLNode)
        }
        
        if !clip.enabled {
            clipElement.addAttribute(XMLNode.attribute(withName: "enabled", stringValue: "0") as! XMLNode)
        }
        
        if let audioRole = clip.audioRole {
            clipElement.addAttribute(XMLNode.attribute(withName: "audioRole", stringValue: audioRole) as! XMLNode)
        }
        
        // Add video effects if present
        if clip.opacity != nil || clip.position != nil || clip.scale != nil || clip.rotation != nil {
            let adjustTransform = XMLElement(name: "adjust-transform")
            
            if let position = clip.position {
                adjustTransform.addAttribute(XMLNode.attribute(withName: "position", stringValue: "\(position.x) \(position.y)") as! XMLNode)
            }
            
            if let scale = clip.scale {
                adjustTransform.addAttribute(XMLNode.attribute(withName: "scale", stringValue: "\(scale) \(scale)") as! XMLNode)
            }
            
            if let rotation = clip.rotation {
                adjustTransform.addAttribute(XMLNode.attribute(withName: "rotation", stringValue: "\(rotation)") as! XMLNode)
            }
            
            clipElement.addChild(adjustTransform)
        }
        
        if let opacity = clip.opacity, opacity != 1.0 {
            let adjustBlend = XMLElement(name: "adjust-blend")
            adjustBlend.addAttribute(XMLNode.attribute(withName: "amount", stringValue: "\(opacity)") as! XMLNode)
            clipElement.addChild(adjustBlend)
        }
        
        // Add audio adjustments if present
        if let volume = clip.volume, volume != 1.0 {
            let adjustVolume = XMLElement(name: "adjust-volume")
            // Convert linear to dB
            let dB = 20 * log10(volume)
            adjustVolume.addAttribute(XMLNode.attribute(withName: "amount", stringValue: "\(dB)dB") as! XMLNode)
            clipElement.addChild(adjustVolume)
        }
        
        return clipElement
    }
    
    private func formatTime(_ time: CMTime) -> String {
        // Format as rational number with timescale
        // FCPXML uses format like "3600/600s" for 6 seconds at 600 timescale
        let seconds = time.seconds
        let timescale = 600 // Standard FCPXML timescale
        let value = Int(seconds * Double(timescale))
        return "\(value)/\(timescale)s"
    }
}

// MARK: - FCPXML Parser

/// Basic parser for FCPXML files
public struct FCPXMLParser {
    
    public init() {}
    
    /// Parse FCPXML content
    public func parse(_ content: String) throws -> (resources: [FCPXMLResource], clips: [FCPXMLClip]) {
        guard let data = content.data(using: .utf8) else {
            throw FCPXMLError.invalidContent
        }
        
        let document = try XMLDocument(data: data, options: [])
        
        var resources: [FCPXMLResource] = []
        var clips: [FCPXMLClip] = []
        
        // Parse resources
        let resourceNodes = try document.nodes(forXPath: "//asset")
        for node in resourceNodes {
            guard let element = node as? XMLElement else { continue }
            
            let id = element.attribute(forName: "id")?.stringValue ?? ""
            let name = element.attribute(forName: "name")?.stringValue ?? ""
            let src = element.attribute(forName: "src")?.stringValue.flatMap { URL(string: $0) }
            let hasVideo = element.attribute(forName: "hasVideo")?.stringValue == "1"
            let hasAudio = element.attribute(forName: "hasAudio")?.stringValue == "1"
            
            resources.append(FCPXMLResource(
                id: id,
                name: name,
                src: src,
                hasVideo: hasVideo,
                hasAudio: hasAudio
            ))
        }
        
        // Parse clips
        let clipNodes = try document.nodes(forXPath: "//asset-clip")
        for node in clipNodes {
            guard let element = node as? XMLElement else { continue }
            
            let name = element.attribute(forName: "name")?.stringValue ?? ""
            let ref = element.attribute(forName: "ref")?.stringValue ?? ""
            let offset = parseTime(element.attribute(forName: "offset")?.stringValue)
            let duration = parseTime(element.attribute(forName: "duration")?.stringValue)
            let start = parseTime(element.attribute(forName: "start")?.stringValue)
            let enabled = element.attribute(forName: "enabled")?.stringValue != "0"
            
            clips.append(FCPXMLClip(
                name: name,
                resourceId: ref,
                offset: offset,
                duration: duration,
                start: start,
                enabled: enabled
            ))
        }
        
        return (resources, clips)
    }
    
    /// Parse FCPXML file
    public func parse(fileAt url: URL) throws -> (resources: [FCPXMLResource], clips: [FCPXMLClip]) {
        let content = try String(contentsOf: url, encoding: .utf8)
        return try parse(content)
    }
    
    private func parseTime(_ timeString: String?) -> CMTime {
        guard let timeString = timeString else { return .zero }
        
        // Parse format like "3600/600s"
        let cleaned = timeString.replacingOccurrences(of: "s", with: "")
        let parts = cleaned.components(separatedBy: "/")
        
        guard parts.count == 2,
              let value = Int64(parts[0]),
              let timescale = Int32(parts[1]) else {
            return .zero
        }
        
        return CMTime(value: value, timescale: timescale)
    }
}

// MARK: - FCPXML Error

public enum FCPXMLError: Error, LocalizedError {
    case invalidContent
    case parseError(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidContent:
            return "Invalid FCPXML content"
        case .parseError(let message):
            return "FCPXML parse error: \(message)"
        }
    }
}
