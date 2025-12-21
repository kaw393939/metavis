// MultiSourceDecoder.swift
// MetaVisRender
//
// Created for Sprint 11: Timeline Editing
// Manages a pool of VideoDecoders for multi-source timeline playback

import Foundation
import CoreMedia
import Metal

// MARK: - MultiSourceDecoderError

/// Errors that can occur in the multi-source decoder.
public enum MultiSourceDecoderError: Error, Sendable {
    case sourceNotFound(String)
    case decoderCreationFailed(String, Error)
    case seekFailed(String)
    case decodeFailed(String, Error)
    case invalidSource(String)
    case poolExhausted
    case memoryPressure
}

extension MultiSourceDecoderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .sourceNotFound(let source):
            return "Source not found: \(source)"
        case .decoderCreationFailed(let source, let error):
            return "Failed to create decoder for \(source): \(error.localizedDescription)"
        case .seekFailed(let source):
            return "Failed to seek in source: \(source)"
        case .decodeFailed(let source, let error):
            return "Failed to decode from \(source): \(error.localizedDescription)"
        case .invalidSource(let source):
            return "Invalid source: \(source)"
        case .poolExhausted:
            return "Decoder pool exhausted"
        case .memoryPressure:
            return "Memory pressure - evicting decoders"
        }
    }
}

// MARK: - MultiSourceDecoderConfig

/// Configuration for multi-source decoding optimized for high-performance editing
public struct MultiSourceDecoderConfig: Sendable {
    /// Maximum concurrent decoders
    public let maxDecoders: Int
    
    /// Seek tolerance (avoid seeks for small time differences)
    public let seekTolerance: Double
    
    /// Preload lookahead time (seconds)
    public let preloadLookahead: Double
    
    /// Whether preloading is enabled
    public let enablePreloading: Bool
    
    /// Enable parallel decoding for overlapping clips
    public let enableParallelDecoding: Bool
    
    /// Memory budget in MB (0 = auto-calculate based on system)
    public let memoryBudgetMB: Int
    
    public init(
        maxDecoders: Int = 4,
        seekTolerance: Double = 1.0/60.0,
        preloadLookahead: Double = 2.0,
        enablePreloading: Bool = true,
        enableParallelDecoding: Bool = true,
        memoryBudgetMB: Int = 0
    ) {
        self.maxDecoders = maxDecoders
        self.seekTolerance = seekTolerance
        self.preloadLookahead = preloadLookahead
        self.enablePreloading = enablePreloading
        self.enableParallelDecoding = enableParallelDecoding
        self.memoryBudgetMB = memoryBudgetMB
    }
    
    /// Default config for standard editing
    public static let standard = MultiSourceDecoderConfig()
    
    /// High-performance config for multi-cam / Director's Chair
    public static let multiCam = MultiSourceDecoderConfig(
        maxDecoders: 8,
        seekTolerance: 1.0/120.0,
        preloadLookahead: 3.0,
        enablePreloading: true,
        enableParallelDecoding: true,
        memoryBudgetMB: 2048
    )
    
    /// Memory-constrained config
    public static let lowMemory = MultiSourceDecoderConfig(
        maxDecoders: 2,
        seekTolerance: 1.0/30.0,
        preloadLookahead: 1.0,
        enablePreloading: false,
        enableParallelDecoding: false,
        memoryBudgetMB: 512
    )
}

// MARK: - DecoderState

/// State of a decoder in the pool.
private struct DecoderState {
    let decoder: VideoDecoder
    var lastAccessTime: Date
    var lastSeekTime: CMTime
    var isActive: Bool
    var estimatedMemoryMB: Int
    var accessCount: Int
    
    init(decoder: VideoDecoder, estimatedMemoryMB: Int = 50) {
        self.decoder = decoder
        self.lastAccessTime = Date()
        self.lastSeekTime = .zero
        self.isActive = true
        self.estimatedMemoryMB = estimatedMemoryMB
        self.accessCount = 0
    }
}

// MARK: - MultiSourceDecoder

/// Manages multiple VideoDecoder instances for multi-source timeline playback.
///
/// Optimized for Director's Chair / Multi-Cam workflows:
/// - Lazy decoder creation (load on first use)
/// - LRU eviction with memory budget awareness
/// - Seek optimization (avoid seeks for sequential access)
/// - Parallel decoding for overlapping clips
/// - Predictive preloading (prepare next source before needed)
/// - Memory pressure handling
///
/// ## Example
/// ```swift
/// let decoder = MultiSourceDecoder(
///     device: mtlDevice,
///     sources: ["cam_a": "/path/to/cam_a.mov", "cam_b": "/path/to/cam_b.mov"],
///     config: .multiCam
/// )
///
/// // Get frame from a source
/// let frame = try await decoder.frame(source: "cam_a", at: CMTime.seconds(10))
/// ```
public actor MultiSourceDecoder {
    
    // MARK: - Properties
    
    /// Metal device for texture creation
    public let device: MTLDevice
    
    /// Source paths (sourceID → file path)
    private var sources: [String: URL]
    
    /// Active decoder instances
    private var decoders: [String: DecoderState] = [:]
    
    /// Multi-source configuration
    private let multiConfig: MultiSourceDecoderConfig
    
    /// Decoder configuration
    private let config: VideoDecoderConfig
    
    /// Current estimated memory usage in MB
    private var currentMemoryMB: Int = 0
    
    /// Memory budget in MB
    private let memoryBudgetMB: Int
    
    /// Parallel decoding task group
    private var parallelDecodingEnabled: Bool
    
    // MARK: - Computed Properties (Legacy Compatibility)
    
    private var maxDecoders: Int { multiConfig.maxDecoders }
    private var seekTolerance: Double { multiConfig.seekTolerance }
    private var preloadLookahead: Double { multiConfig.preloadLookahead }
    private var enablePreloading: Bool { multiConfig.enablePreloading }
    
    // MARK: - Initialization
    
    /// Creates a new multi-source decoder with full configuration.
    public init(
        device: MTLDevice,
        sources: [String: String] = [:],
        config: MultiSourceDecoderConfig = .standard,
        decoderConfig: VideoDecoderConfig = .realtime,
        targetResolution: SIMD2<Int>? = nil
    ) {
        self.device = device
        self.sources = sources.mapValues { URL(fileURLWithPath: $0) }
        self.multiConfig = config
        self.parallelDecodingEnabled = config.enableParallelDecoding
        
        // Calculate memory budget
        if config.memoryBudgetMB > 0 {
            self.memoryBudgetMB = config.memoryBudgetMB
        } else {
            // Auto-calculate based on system memory (use ~10% of physical RAM)
            let physicalMemoryGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
            self.memoryBudgetMB = Int(physicalMemoryGB) * 100  // 100MB per GB of RAM
        }
        
        // Apply target resolution to config if specified
        if let resolution = targetResolution {
            self.config = VideoDecoderConfig(
                useTextureCache: decoderConfig.useTextureCache,
                outputPixelFormat: decoderConfig.outputPixelFormat,
                enableHardwareAcceleration: decoderConfig.enableHardwareAcceleration,
                prefetchCount: decoderConfig.prefetchCount,
                decodeAudio: decoderConfig.decodeAudio,
                targetResolution: resolution,
                enableDecodeAhead: decoderConfig.enableDecodeAhead,
                decodeAheadCount: decoderConfig.decodeAheadCount
            )
        } else {
            self.config = decoderConfig
        }
    }
    
    /// Legacy init for backward compatibility
    public init(
        device: MTLDevice,
        sources: [String: String] = [:],
        maxDecoders: Int = 3,
        config: VideoDecoderConfig = .realtime,
        seekTolerance: Double = 1.0/60.0,
        preloadLookahead: Double = 2.0,
        enablePreloading: Bool = true,
        targetResolution: SIMD2<Int>? = nil
    ) {
        self.device = device
        self.sources = sources.mapValues { URL(fileURLWithPath: $0) }
        self.multiConfig = MultiSourceDecoderConfig(
            maxDecoders: maxDecoders,
            seekTolerance: seekTolerance,
            preloadLookahead: preloadLookahead,
            enablePreloading: enablePreloading
        )
        self.parallelDecodingEnabled = true
        self.memoryBudgetMB = 1024  // Default 1GB
        
        // Apply target resolution to config if specified
        if let resolution = targetResolution {
            self.config = VideoDecoderConfig(
                useTextureCache: config.useTextureCache,
                outputPixelFormat: config.outputPixelFormat,
                enableHardwareAcceleration: config.enableHardwareAcceleration,
                prefetchCount: config.prefetchCount,
                decodeAudio: config.decodeAudio,
                targetResolution: resolution,
                enableDecodeAhead: config.enableDecodeAhead,
                decodeAheadCount: config.decodeAheadCount
            )
        } else {
            self.config = config
        }
    }
    
    /// Creates a multi-source decoder from a timeline.
    /// Automatically configures target resolution from timeline for efficient decode-time scaling.
    public init(
        device: MTLDevice,
        timeline: TimelineModel,
        maxDecoders: Int? = nil,
        config: VideoDecoderConfig = .realtime
    ) {
        self.device = device
        self.sources = timeline.sources.mapValues { URL(fileURLWithPath: $0.path) }
        
        let decoderCount = maxDecoders ?? timeline.quality.decoderPoolSize
        self.multiConfig = MultiSourceDecoderConfig(
            maxDecoders: decoderCount,
            enableParallelDecoding: true
        )
        self.parallelDecodingEnabled = true
        self.memoryBudgetMB = 1024
        
        // Configure decode-time scaling to timeline resolution
        self.config = VideoDecoderConfig(
            useTextureCache: config.useTextureCache,
            outputPixelFormat: config.outputPixelFormat,
            enableHardwareAcceleration: config.enableHardwareAcceleration,
            prefetchCount: config.prefetchCount,
            decodeAudio: config.decodeAudio,
            targetResolution: timeline.resolution,  // Scale at decode time!
            enableDecodeAhead: true,
            decodeAheadCount: 2
        )
    }
    
    // MARK: - Source Management
    
    /// Registers a new source.
    public func registerSource(id: String, path: String) {
        sources[id] = URL(fileURLWithPath: path)
    }
    
    /// Registers a new source with URL.
    public func registerSource(id: String, url: URL) {
        sources[id] = url
    }
    
    /// Removes a source (and closes its decoder if active).
    public func removeSource(id: String) async {
        sources.removeValue(forKey: id)
        if let state = decoders.removeValue(forKey: id) {
            currentMemoryMB -= state.estimatedMemoryMB
            await state.decoder.close()
        }
    }
    
    /// Returns whether a source is registered.
    public func hasSource(_ id: String) -> Bool {
        sources[id] != nil
    }
    
    /// Returns all registered source IDs.
    public var sourceIDs: [String] {
        Array(sources.keys)
    }
    
    // MARK: - Frame Decoding
    
    /// Decodes a frame from the specified source at the given time.
    ///
    /// - Parameters:
    ///   - source: Source identifier
    ///   - time: Time in the source file
    /// - Returns: Decoded frame, or nil if at end of source
    public func frame(source: String, at time: CMTime) async throws -> DecodedFrame? {
        let decoder = try await ensureDecoder(for: source)
        
        // Check if seek is needed
        let currentTime = await decoder.currentTimeSeconds
        let targetTime = time.seconds
        let sourceFrameRate = await decoder.frameRate
        let frameDuration = 1.0 / sourceFrameRate
        
        // Need to seek if:
        // 1. Going backwards (targetTime < currentTime - small tolerance)
        // 2. Jumping forward too far (more than a few frames ahead)
        let isBackward = targetTime < (currentTime - seekTolerance)
        let isLargeJump = targetTime > (currentTime + frameDuration * 3)
        
        if isBackward || isLargeJump {
            try await decoder.seek(to: time)
        }
        
        // Update access time and count
        decoders[source]?.lastAccessTime = Date()
        decoders[source]?.lastSeekTime = time
        decoders[source]?.accessCount += 1
        
        // Decode frame
        return try await decoder.nextFrame()
    }
    
    /// Decodes a frame and converts to texture.
    public func texture(source: String, at time: CMTime) async throws -> MTLTexture? {
        guard let frame = try await frame(source: source, at: time) else {
            return nil
        }
        
        let decoder = try await ensureDecoder(for: source)
        return await decoder.textureWithCache(from: frame)
    }
    
    /// Decodes a frame and converts to texture using async (non-blocking) GPU copy.
    /// Preferred for high-performance pipelines.
    public func textureAsync(source: String, at time: CMTime) async throws -> MTLTexture? {
        guard let frame = try await frame(source: source, at: time) else {
            return nil
        }
        
        let decoder = try await ensureDecoder(for: source)
        return await decoder.textureWithCacheAsync(from: frame)
    }
    
    /// Decodes frames from multiple sources in parallel.
    /// Optimized for multi-cam / Director's Chair workflows.
    public func framesParallel(
        _ requests: [(source: String, time: CMTime)]
    ) async throws -> [String: DecodedFrame] {
        guard parallelDecodingEnabled else {
            // Fall back to sequential
            return try await frames(requests)
        }
        
        return try await withThrowingTaskGroup(of: (String, DecodedFrame?).self) { group in
            for request in requests {
                group.addTask {
                    let frame = try await self.frame(source: request.source, at: request.time)
                    return (request.source, frame)
                }
            }
            
            var results: [String: DecodedFrame] = [:]
            for try await (source, frame) in group {
                if let frame = frame {
                    results[source] = frame
                }
            }
            return results
        }
    }
    
    /// Decodes textures from multiple sources in parallel.
    /// Optimized for multi-cam / Director's Chair workflows.
    public func texturesParallel(
        _ requests: [(source: String, time: CMTime)]
    ) async throws -> [String: MTLTexture] {
        guard parallelDecodingEnabled else {
            // Fall back to sequential
            var results: [String: MTLTexture] = [:]
            for request in requests {
                if let texture = try await texture(source: request.source, at: request.time) {
                    results[request.source] = texture
                }
            }
            return results
        }
        
        return try await withThrowingTaskGroup(of: (String, MTLTexture?).self) { group in
            for request in requests {
                group.addTask {
                    let texture = try await self.textureAsync(source: request.source, at: request.time)
                    return (request.source, texture)
                }
            }
            
            var results: [String: MTLTexture] = [:]
            for try await (source, texture) in group {
                if let texture = texture {
                    results[source] = texture
                }
            }
            return results
        }
    }
    
    /// Decodes frames from multiple sources at their respective times (sequential).
    public func frames(
        _ requests: [(source: String, time: CMTime)]
    ) async throws -> [String: DecodedFrame] {
        var results: [String: DecodedFrame] = [:]
        
        // Decode each source
        for request in requests {
            if let frame = try await frame(source: request.source, at: request.time) {
                results[request.source] = frame
            }
        }
        
        return results
    }
    
    // MARK: - Preloading
    
    /// Preloads a source for upcoming use.
    public func preload(source: String, at time: CMTime) async throws {
        let decoder = try await ensureDecoder(for: source)
        
        // Seek to prepare for upcoming access
        try await decoder.seek(to: time)
        
        // Update state
        decoders[source]?.lastAccessTime = Date()
        decoders[source]?.lastSeekTime = time
    }
    
    /// Preloads multiple sources in parallel.
    public func preloadSourcesParallel(_ sources: [String]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for source in sources {
                group.addTask {
                    _ = try await self.ensureDecoder(for: source)
                }
            }
            try await group.waitForAll()
        }
    }
    
    /// Preloads multiple sources.
    public func preloadSources(_ sources: [String]) async throws {
        for source in sources {
            _ = try await ensureDecoder(for: source)
        }
    }
    
    // MARK: - Decoder Management
    
    /// Ensures a decoder exists for the given source, creating if necessary.
    private func ensureDecoder(for source: String) async throws -> VideoDecoder {
        // Return existing decoder
        if let state = decoders[source] {
            return state.decoder
        }
        
        // Get source URL
        guard let url = sources[source] else {
            throw MultiSourceDecoderError.sourceNotFound(source)
        }
        
        // Check memory budget and evict if needed
        await evictIfOverBudget()
        
        // Evict if at capacity
        if decoders.count >= maxDecoders {
            await evictLRU()
        }
        
        // Create new decoder
        do {
            let decoder = try await VideoDecoder(url: url, device: device, config: config)
            
            // Estimate memory based on resolution
            let resolution = await decoder.resolution
            let estimatedMB = (resolution.x * resolution.y * 4 * 3) / (1024 * 1024)  // 3 frames of BGRA
            
            decoders[source] = DecoderState(decoder: decoder, estimatedMemoryMB: max(50, estimatedMB))
            currentMemoryMB += max(50, estimatedMB)
            
            return decoder
        } catch {
            throw MultiSourceDecoderError.decoderCreationFailed(source, error)
        }
    }
    
    /// Evicts decoders if over memory budget
    private func evictIfOverBudget() async {
        while currentMemoryMB > memoryBudgetMB && decoders.count > 1 {
            await evictLRU()
        }
    }
    
    /// Evicts the least recently used decoder.
    private func evictLRU() async {
        // Find the oldest, least accessed decoder
        guard let oldest = decoders
            .filter({ $0.value.accessCount > 0 }) // Prefer evicting used decoders over freshly preloaded
            .min(by: { 
                if $0.value.lastAccessTime == $1.value.lastAccessTime {
                    return $0.value.accessCount < $1.value.accessCount
                }
                return $0.value.lastAccessTime < $1.value.lastAccessTime 
            }) ?? decoders.min(by: { $0.value.lastAccessTime < $1.value.lastAccessTime })
        else {
            return
        }
        
        currentMemoryMB -= oldest.value.estimatedMemoryMB
        await oldest.value.decoder.close()
        decoders.removeValue(forKey: oldest.key)
    }
    
    /// Closes all decoders.
    public func closeAll() async {
        for (_, state) in decoders {
            await state.decoder.close()
        }
        decoders.removeAll()
        currentMemoryMB = 0
    }
    
    /// Closes a specific source's decoder.
    public func close(source: String) async {
        if let state = decoders.removeValue(forKey: source) {
            currentMemoryMB -= state.estimatedMemoryMB
            await state.decoder.close()
        }
    }
    
    // MARK: - Status & Diagnostics
    
    /// Returns the number of active decoders.
    public var activeDecoderCount: Int {
        decoders.count
    }
    
    /// Returns which sources have active decoders.
    public var activeSourceIDs: [String] {
        Array(decoders.keys)
    }
    
    /// Returns decoder info for a source.
    public func decoderInfo(for source: String) async -> VideoMetadata? {
        guard let state = decoders[source] else { return nil }
        return await state.decoder.metadata
    }
    
    /// Returns whether a decoder is active for a source.
    public func isActive(_ source: String) -> Bool {
        decoders[source] != nil
    }
    
    /// Returns current memory usage statistics.
    public var memoryStats: (usedMB: Int, budgetMB: Int, decoderCount: Int) {
        (currentMemoryMB, memoryBudgetMB, decoders.count)
    }
}

// MARK: - Convenience Extensions

extension MultiSourceDecoder {
    /// Decodes a frame from the specified source at the given time in seconds.
    public func frame(source: String, atSeconds seconds: Double) async throws -> DecodedFrame? {
        let time = CMTime(seconds: seconds, preferredTimescale: 90000)
        return try await frame(source: source, at: time)
    }
    
    /// Decodes a texture from the specified source at the given time in seconds.
    public func texture(source: String, atSeconds seconds: Double) async throws -> MTLTexture? {
        let time = CMTime(seconds: seconds, preferredTimescale: 90000)
        return try await texture(source: source, at: time)
    }
}

// MARK: - Timeline Integration

extension MultiSourceDecoder {
    /// Decodes a frame for a resolved frame context.
    public func frame(for resolved: ResolvedFrame) async throws -> (primary: DecodedFrame?, secondary: DecodedFrame?) {
        let primary = try await frame(source: resolved.primarySource, at: resolved.primarySourceTime)
        
        var secondary: DecodedFrame? = nil
        if let secondarySource = resolved.secondarySource,
           let secondaryTime = resolved.secondarySourceTime {
            secondary = try await frame(source: secondarySource, at: secondaryTime)
        }
        
        return (primary, secondary)
    }
    
    /// Decodes textures for a resolved frame context using parallel decoding when possible.
    public func textures(for resolved: ResolvedFrame) async throws -> (primary: MTLTexture?, secondary: MTLTexture?) {
        // Use parallel decoding if we have a secondary source
        if let secondarySource = resolved.secondarySource,
           let secondaryTime = resolved.secondarySourceTime {
            let results = try await texturesParallel([
                (source: resolved.primarySource, time: resolved.primarySourceTime),
                (source: secondarySource, time: secondaryTime)
            ])
            return (results[resolved.primarySource], results[secondarySource])
        }
        
        // Single source - no parallelism needed
        let primary = try await texture(source: resolved.primarySource, at: resolved.primarySourceTime)
        return (primary, nil)
    }
}
