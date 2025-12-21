// FrameSource.swift
// MetaVisRender
//
// Created for Sprint 14: Validation
// Abstraction for frame sources (video files, PDF pages, image sequences)

import Foundation
import Metal
import CoreMedia

// MARK: - FrameSource Protocol

/// Protocol for sources that can provide frames to the timeline system.
///
/// Implementations can be video files, PDF pages, image sequences, etc.
public protocol FrameSource: Actor {
    /// The source identifier
    var sourceID: String { get }
    
    /// Duration of the source in seconds
    var duration: Double { get async }
    
    /// Frame rate (for video) or default frame rate (for static images)
    var frameRate: Double { get async }
    
    /// Native resolution of the source
    var resolution: SIMD2<Int> { get async }
    
    /// Returns a frame at the specified time
    func frame(at time: CMTime) async throws -> MTLTexture?
    
    /// Seeks to a specific time (optimization for video sources)
    func seek(to time: CMTime) async throws
    
    /// Closes/releases resources
    func close() async
}

// MARK: - VideoFileSource

/// Frame source backed by a video file using VideoDecoder.
public actor VideoFileSource: FrameSource {
    public let sourceID: String
    private let decoder: VideoDecoder
    private let url: URL
    
    public init(sourceID: String, url: URL, device: MTLDevice, config: VideoDecoderConfig = .export) async throws {
        self.sourceID = sourceID
        self.url = url
        self.decoder = try await VideoDecoder(url: url, device: device, config: config)
    }
    
    public var duration: Double {
        get async {
            return await decoder.duration.seconds
        }
    }
    
    public var frameRate: Double {
        get async {
            await decoder.frameRate
        }
    }
    
    public var resolution: SIMD2<Int> {
        get async {
            await decoder.resolution
        }
    }
    
    public func frame(at time: CMTime) async throws -> MTLTexture? {
        // Seek if needed
        let currentTime = await decoder.currentTimeSeconds
        let targetTime = time.seconds
        let seekTolerance = 1.0 / 60.0
        
        if abs(currentTime - targetTime) > seekTolerance {
            try await decoder.seek(to: time)
        }
        
        // Decode frame
        guard let decodedFrame = try await decoder.nextFrame() else {
            return nil
        }
        
        return await decoder.textureWithCache(from: decodedFrame)
    }
    
    public func seek(to time: CMTime) async throws {
        try await decoder.seek(to: time)
    }
    
    public func close() async {
        await decoder.close()
    }
}

// MARK: - PDFPageSource

/// Frame source backed by a PDF page.
///
/// PDF pages are static images, so all time requests return the same texture.
public actor PDFPageSource: FrameSource {
    public let sourceID: String
    private let pdfURL: URL
    private let pageNumber: Int
    private let pageRenderer: PageRenderer
    private let targetResolution: SIMD2<Int>
    
    // Cached texture
    private var cachedTexture: MTLTexture?
    
    public init(
        sourceID: String,
        pdfURL: URL,
        pageNumber: Int,
        resolution: SIMD2<Int>,
        pageRenderer: PageRenderer
    ) {
        self.sourceID = sourceID
        self.pdfURL = pdfURL
        self.pageNumber = pageNumber
        self.pageRenderer = pageRenderer
        self.targetResolution = resolution
    }
    
    public var duration: Double {
        get async {
            // PDF pages are "infinite" duration - they're static
            // Return a reasonable default
            return 10.0
        }
    }
    
    public var frameRate: Double {
        get async {
            // PDF pages don't have an inherent frame rate
            return 30.0
        }
    }
    
    public var resolution: SIMD2<Int> {
        get async {
            return targetResolution
        }
    }
    
    public func frame(at time: CMTime) async throws -> MTLTexture? {
        // Return cached texture if available
        if let cached = cachedTexture {
            return cached
        }
        
        // Render the page
        let texture = try await pageRenderer.renderToTexture(
            page: pageNumber,
            from: pdfURL,
            resolution: CGSize(
                width: CGFloat(targetResolution.x),
                height: CGFloat(targetResolution.y)
            )
        )
        
        // Cache for future requests
        cachedTexture = texture
        return texture
    }
    
    public func seek(to time: CMTime) async throws {
        // No-op for static images
    }
    
    public func close() async {
        cachedTexture = nil
    }
}

// MARK: - ImageSequenceSource

/// Frame source backed by a sequence of images.
///
/// Each frame time maps to a specific image in the sequence.
public actor ImageSequenceSource: FrameSource {
    public let sourceID: String
    private let imageURLs: [URL]
    private let fps: Double
    private let pageRenderer: PageRenderer
    private let targetResolution: SIMD2<Int>
    
    // Cache of rendered textures
    private var textureCache: [Int: MTLTexture] = [:]
    
    public init(
        sourceID: String,
        imageURLs: [URL],
        fps: Double,
        resolution: SIMD2<Int>,
        pageRenderer: PageRenderer
    ) {
        self.sourceID = sourceID
        self.imageURLs = imageURLs
        self.fps = fps
        self.pageRenderer = pageRenderer
        self.targetResolution = resolution
    }
    
    public var duration: Double {
        get async {
            return Double(imageURLs.count) / fps
        }
    }
    
    public var frameRate: Double {
        get async {
            return fps
        }
    }
    
    public var resolution: SIMD2<Int> {
        get async {
            return targetResolution
        }
    }
    
    public func frame(at time: CMTime) async throws -> MTLTexture? {
        // Calculate which image this time corresponds to
        let frameIndex = Int(time.seconds * fps)
        
        guard frameIndex >= 0 && frameIndex < imageURLs.count else {
            return nil
        }
        
        // Return cached texture if available
        if let cached = textureCache[frameIndex] {
            return cached
        }
        
        // Render the image
        // TODO: Implement image loading/rendering
        // For now, return nil
        return nil
    }
    
    public func seek(to time: CMTime) async throws {
        // No-op for image sequences
    }
    
    public func close() async {
        textureCache.removeAll()
    }
}
