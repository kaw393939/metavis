import Foundation
import CoreVideo
import Metal

// MARK: - FrameBufferPoolConfig

/// Configuration for the frame buffer pool.
public struct FrameBufferPoolConfig: Sendable {
    /// Maximum number of buffers in the pool.
    public let maxBuffers: Int
    
    /// Whether buffers should be Metal-compatible (IOSurface-backed).
    public let metalCompatible: Bool
    
    /// Pixel format for buffers.
    public let pixelFormat: OSType
    
    /// Whether to use a CVPixelBufferPool for efficient allocation.
    public let usePooledAllocation: Bool
    
    /// Memory pressure threshold for releasing unused buffers (0.0-1.0).
    public let memoryPressureThreshold: Float
    
    public init(
        maxBuffers: Int = 8,
        metalCompatible: Bool = true,
        pixelFormat: OSType = kCVPixelFormatType_32BGRA,
        usePooledAllocation: Bool = true,
        memoryPressureThreshold: Float = 0.7
    ) {
        self.maxBuffers = maxBuffers
        self.metalCompatible = metalCompatible
        self.pixelFormat = pixelFormat
        self.usePooledAllocation = usePooledAllocation
        self.memoryPressureThreshold = memoryPressureThreshold
    }
    
    /// Default configuration for 1080p video.
    public static let hd1080p = FrameBufferPoolConfig(maxBuffers: 6)
    
    /// Configuration for 4K video (larger buffers, fewer in pool).
    public static let uhd4K = FrameBufferPoolConfig(maxBuffers: 4)
    
    /// Configuration for preview/scrubbing (smaller pool, faster allocation).
    public static let preview = FrameBufferPoolConfig(maxBuffers: 3)
}

// MARK: - FrameBufferPoolError

/// Errors that can occur during frame buffer pool operations.
public enum FrameBufferPoolError: Error, Sendable {
    case poolExhausted
    case allocationFailed(CVReturn)
    case invalidDimensions
    case poolCreationFailed(CVReturn)
}

extension FrameBufferPoolError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .poolExhausted:
            return "Frame buffer pool exhausted - all buffers in use"
        case .allocationFailed(let status):
            return "Failed to allocate pixel buffer: \(status)"
        case .invalidDimensions:
            return "Invalid buffer dimensions specified"
        case .poolCreationFailed(let status):
            return "Failed to create pixel buffer pool: \(status)"
        }
    }
}

// MARK: - FrameBufferPool

/// Actor managing a pool of CVPixelBuffers for video decoding.
///
/// `FrameBufferPool` provides efficient memory management for video frame buffers:
/// - Reuses buffers to minimize allocation overhead
/// - Ensures Metal compatibility with IOSurface backing
/// - Handles memory pressure by releasing unused buffers
///
/// ## Example Usage
/// ```swift
/// let pool = FrameBufferPool(width: 1920, height: 1080)
/// 
/// // Acquire a buffer for decoding
/// if let buffer = await pool.acquire() {
///     // Use buffer for video decoding...
///     await pool.release(buffer)
/// }
/// ```
public actor FrameBufferPool {
    
    // MARK: - Properties
    
    /// Width of buffers in the pool.
    public let width: Int
    
    /// Height of buffers in the pool.
    public let height: Int
    
    /// Configuration for the pool.
    public let config: FrameBufferPoolConfig
    
    /// CVPixelBufferPool for efficient allocation.
    private var cvPool: CVPixelBufferPool?
    
    /// Available buffers ready for use.
    private var availableBuffers: [CVPixelBuffer] = []
    
    /// Buffers currently in use.
    private var inUseCount: Int = 0
    
    /// Total buffers ever allocated.
    private var totalAllocated: Int = 0
    
    /// Memory pressure observer.
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    
    // MARK: - Initialization
    
    /// Creates a frame buffer pool with specified dimensions.
    ///
    /// - Parameters:
    ///   - width: Width of buffers in pixels.
    ///   - height: Height of buffers in pixels.
    ///   - maxBuffers: Maximum number of buffers (deprecated, use config).
    ///   - config: Pool configuration.
    public init(
        width: Int,
        height: Int,
        maxBuffers: Int? = nil,
        config: FrameBufferPoolConfig = FrameBufferPoolConfig()
    ) {
        self.width = width
        self.height = height
        
        // Allow maxBuffers parameter to override config for backwards compatibility
        if let maxBuffers = maxBuffers {
            self.config = FrameBufferPoolConfig(
                maxBuffers: maxBuffers,
                metalCompatible: config.metalCompatible,
                pixelFormat: config.pixelFormat,
                usePooledAllocation: config.usePooledAllocation,
                memoryPressureThreshold: config.memoryPressureThreshold
            )
        } else {
            self.config = config
        }
        
        // Create CVPixelBufferPool if enabled
        if self.config.usePooledAllocation {
            let poolAttributes: [String: Any] = [
                kCVPixelBufferPoolMinimumBufferCountKey as String: 2
            ]
            
            let bufferAttributes: [String: Any] = [
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferPixelFormatTypeKey as String: self.config.pixelFormat,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
                kCVPixelBufferMetalCompatibilityKey as String: self.config.metalCompatible
            ]
            
            var pool: CVPixelBufferPool?
            let status = CVPixelBufferPoolCreate(
                kCFAllocatorDefault,
                poolAttributes as CFDictionary,
                bufferAttributes as CFDictionary,
                &pool
            )
            
            if status == kCVReturnSuccess {
                self.cvPool = pool
            }
        }
        
        // Set up memory pressure monitoring
        setupMemoryPressureMonitoring()
    }
    
    deinit {
        memoryPressureSource?.cancel()
    }
    
    // MARK: - Public Methods
    
    /// Acquires a buffer from the pool.
    ///
    /// - Returns: A pixel buffer, or nil if the pool is exhausted.
    public func acquire() -> CVPixelBuffer? {
        // Check if we can provide a buffer
        guard inUseCount < config.maxBuffers else {
            return nil
        }
        
        // Try to reuse an available buffer
        if let buffer = availableBuffers.popLast() {
            inUseCount += 1
            return buffer
        }
        
        // Allocate a new buffer
        guard let buffer = allocateBuffer() else {
            return nil
        }
        
        inUseCount += 1
        totalAllocated += 1
        return buffer
    }
    
    /// Releases a buffer back to the pool.
    ///
    /// - Parameter buffer: The buffer to release.
    public func release(_ buffer: CVPixelBuffer) {
        guard inUseCount > 0 else { return }
        
        inUseCount -= 1
        
        // Add to available pool if under limit
        if availableBuffers.count < config.maxBuffers {
            availableBuffers.append(buffer)
        }
        // Otherwise let it be deallocated
    }
    
    /// Handles memory warning by releasing unused buffers.
    public func handleMemoryWarning() {
        // Release all available (unused) buffers
        availableBuffers.removeAll()
    }
    
    /// Releases all unused buffers from the pool.
    public func drain() {
        availableBuffers.removeAll()
    }
    
    /// Resets the pool, releasing all buffers.
    /// Note: Buffers in use will be released when returned.
    public func reset() {
        availableBuffers.removeAll()
        inUseCount = 0
        totalAllocated = 0
    }
    
    // MARK: - Statistics
    
    /// Number of buffers currently available.
    public var availableCount: Int {
        availableBuffers.count
    }
    
    /// Number of buffers currently in use.
    public var inUseBufferCount: Int {
        inUseCount
    }
    
    /// Total buffers allocated (available + in use).
    public var totalBufferCount: Int {
        availableBuffers.count + inUseCount
    }
    
    /// Estimated memory usage in bytes.
    public var estimatedMemoryUsage: Int {
        let bytesPerPixel = config.pixelFormat == kCVPixelFormatType_32BGRA ? 4 : 2
        let bytesPerBuffer = width * height * bytesPerPixel
        return totalBufferCount * bytesPerBuffer
    }
    
    // MARK: - Private Methods
    
    nonisolated private func createCVPool() -> CVPixelBufferPool? {
        let poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 2
        ]
        
        let bufferAttributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: config.pixelFormat,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            kCVPixelBufferMetalCompatibilityKey as String: config.metalCompatible
        ]
        
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as CFDictionary,
            bufferAttributes as CFDictionary,
            &pool
        )
        
        guard status == kCVReturnSuccess else {
            return nil
        }
        
        return pool
    }
    
    private func allocateBuffer() -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        
        // Try pool allocation first
        if let pool = cvPool {
            let status = CVPixelBufferPoolCreatePixelBuffer(
                kCFAllocatorDefault,
                pool,
                &pixelBuffer
            )
            
            if status == kCVReturnSuccess {
                return pixelBuffer
            }
        }
        
        // Fall back to direct allocation
        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: config.pixelFormat,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            kCVPixelBufferMetalCompatibilityKey as String: config.metalCompatible
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            config.pixelFormat,
            attributes as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess else {
            return nil
        }
        
        return pixelBuffer
    }
    
    private nonisolated func setupMemoryPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .global(qos: .utility)
        )
        
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            Task {
                await self.handleMemoryWarning()
            }
        }
        
        source.resume()
        
        Task {
            await setMemoryPressureSource(source)
        }
    }
    
    private func setMemoryPressureSource(_ source: DispatchSourceMemoryPressure) {
        self.memoryPressureSource = source
    }
}

// MARK: - CustomStringConvertible

extension FrameBufferPool {
    /// Debug description of the pool state.
    public var debugDescription: String {
        get async {
            """
            FrameBufferPool:
              Dimensions: \(width)x\(height)
              Available: \(availableCount)/\(config.maxBuffers)
              In Use: \(inUseCount)
              Total Allocated: \(totalAllocated)
              Memory: \(ByteCountFormatter.string(fromByteCount: Int64(estimatedMemoryUsage), countStyle: .memory))
            """
        }
    }
}
