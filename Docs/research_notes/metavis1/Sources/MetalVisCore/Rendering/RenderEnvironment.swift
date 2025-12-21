import Foundation
import Logging
import CoreText
import Metal
import Shared

/// Defines the runtime environment for the rendering engine.
/// This encapsulates all external dependencies, configuration, and system resources,
/// allowing for Dependency Injection and easier testing.
public struct RenderEnvironment: Sendable {
    public let logger: Logger
    public let config: RenderConfig
    public let fontProvider: FontProvider
    public let assetLoader: AssetLoader
    public let audioConfig: AudioConfiguration
    
    public init(
        logger: Logger,
        config: RenderConfig = .default,
        fontProvider: FontProvider = DefaultFontProvider(),
        assetLoader: AssetLoader = DefaultAssetLoader(),
        audioConfig: AudioConfiguration = .default
    ) {
        self.logger = logger
        self.config = config
        self.fontProvider = fontProvider
        self.assetLoader = assetLoader
        self.audioConfig = audioConfig
    }
    
    public static let production: RenderEnvironment = {
        var logger = Logger(label: "com.metalvis.production")
        logger.logLevel = .info
        return RenderEnvironment(logger: logger)
    }()
}

/// Configuration for Audio Subsystem
public struct AudioConfiguration: Sendable {
    public let sampleRate: Double
    public let channels: UInt32
    
    public static let `default` = AudioConfiguration(sampleRate: 44100, channels: 2)
    
    public init(sampleRate: Double, channels: UInt32) {
        self.sampleRate = sampleRate
        self.channels = channels
    }
}

/// Protocol for providing fonts, abstracting CoreText dependency
public protocol FontProvider: Sendable {
    func getFont(name: String, size: CGFloat) throws -> CTFont
    func getAtlasSize() -> CGSize
}

public struct DefaultFontProvider: FontProvider {
    public init() {}
    
    public func getFont(name: String, size: CGFloat) throws -> CTFont {
        // In a real system, this would handle fallbacks and custom font loading
        return CTFontCreateWithName(name as CFString, size, nil)
    }
    
    public func getAtlasSize() -> CGSize {
        return CGSize(width: 2048, height: 2048)
    }
}

/// Protocol for loading assets, abstracting FileSystem
public protocol AssetLoader: Sendable {
    func resolvePath(_ path: String) -> URL?
}

public struct DefaultAssetLoader: AssetLoader {
    public init() {}
    
    public func resolvePath(_ path: String) -> URL? {
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
