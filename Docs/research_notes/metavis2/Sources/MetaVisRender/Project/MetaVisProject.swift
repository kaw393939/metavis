import Foundation

/// Represents the configuration of a MetaVis project (project.json)
public struct ProjectConfig: Codable, Sendable {
    public let name: String
    public let version: String
    public let created: Date
    public let lastModified: Date
    public let settings: ProjectSettings
    
    public init(name: String, settings: ProjectSettings) {
        self.name = name
        self.version = "1.0.0"
        self.created = Date()
        self.lastModified = Date()
        self.settings = settings
    }
}

public struct ProjectSettings: Codable, Sendable {
    public let resolution: SIMD2<Int>
    public let fps: Double
    public let colorSpace: String // "aces", "rec709"
    public let audioSampleRate: Int
    
    public init(resolution: SIMD2<Int> = SIMD2(3840, 2160), fps: Double = 24.0, colorSpace: String = "aces", audioSampleRate: Int = 48000) {
        self.resolution = resolution
        self.fps = fps
        self.colorSpace = colorSpace
        self.audioSampleRate = audioSampleRate
    }
}

/// Manages a .metavis project package
public class MetaVisProject {
    public let url: URL
    public var config: ProjectConfig
    
    public var assetsURL: URL { url.appendingPathComponent("assets") }
    public var sequencesURL: URL { url.appendingPathComponent("sequences") }
    public var renderURL: URL { url.appendingPathComponent("render") }
    public var screenplayURL: URL { url.appendingPathComponent("screenplay.md") }
    
    public init(url: URL) throws {
        self.url = url
        
        let configURL = url.appendingPathComponent("project.json")
        let data = try Data(contentsOf: configURL)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.config = try decoder.decode(ProjectConfig.self, from: data)
    }
    
    public init(createAt url: URL, name: String, settings: ProjectSettings = ProjectSettings()) throws {
        self.url = url
        self.config = ProjectConfig(name: name, settings: settings)
        try createStructure()
    }
    
    private func createStructure() throws {
        let fm = FileManager.default
        
        // Create root .metavis folder
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        
        // Create subfolders
        try fm.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: assetsURL.appendingPathComponent("models"), withIntermediateDirectories: true)
        try fm.createDirectory(at: assetsURL.appendingPathComponent("textures"), withIntermediateDirectories: true)
        try fm.createDirectory(at: assetsURL.appendingPathComponent("audio"), withIntermediateDirectories: true)
        
        try fm.createDirectory(at: sequencesURL, withIntermediateDirectories: true)
        
        try fm.createDirectory(at: renderURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: renderURL.appendingPathComponent("proxies"), withIntermediateDirectories: true)
        try fm.createDirectory(at: renderURL.appendingPathComponent("final"), withIntermediateDirectories: true)
        
        // Write project.json
        try saveConfig()
        
        // Create empty screenplay if not exists
        if !fm.fileExists(atPath: screenplayURL.path) {
            try "# \(config.name)\n\nINT. SCENE 1 - DAY\n".write(to: screenplayURL, atomically: true, encoding: .utf8)
        }
    }
    
    public func saveConfig() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(config)
        try data.write(to: url.appendingPathComponent("project.json"))
    }
    
    /// Creates a new sequence in the project
    public func createSequence(id: String) throws -> URL {
        let seqURL = sequencesURL.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: seqURL, withIntermediateDirectories: true)
        
        // Create sequence.json
        let seqConfig = ["id": id, "scenes": []] as [String : Any]
        let data = try JSONSerialization.data(withJSONObject: seqConfig, options: .prettyPrinted)
        try data.write(to: seqURL.appendingPathComponent("sequence.json"))
        
        return seqURL
    }
    
    /// Creates a new scene within a sequence
    public func createScene(sequenceId: String, sceneId: String) throws -> URL {
        let seqURL = sequencesURL.appendingPathComponent(sequenceId)
        let sceneURL = seqURL.appendingPathComponent(sceneId)
        
        try FileManager.default.createDirectory(at: sceneURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sceneURL.appendingPathComponent("assets"), withIntermediateDirectories: true)
        
        // Create default manifest
        // In a real app, we'd use a default RenderManifest struct here
        let manifest = """
        {
            "metadata": {
                "duration": 5.0,
                "fps": \(config.settings.fps),
                "resolution": [\(config.settings.resolution.x), \(config.settings.resolution.y)]
            },
            "scene": {
                "background": "#000000"
            },
            "camera": {
                "fov": 60,
                "position": [0, 0, 5],
                "target": [0, 0, 0]
            }
        }
        """
        try manifest.write(to: sceneURL.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        
        return sceneURL
    }
}
