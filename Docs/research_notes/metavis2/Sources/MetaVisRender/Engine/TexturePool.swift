import Metal
import Foundation

// MARK: - TexturePoolConfig

/// Configuration for the texture pool.
public struct TexturePoolConfig: Sendable {
    /// Maximum number of textures to keep per key (prevents memory bloat)
    public let maxTexturesPerKey: Int
    
    /// Maximum total memory budget in bytes (0 = unlimited)
    public let maxMemoryBudget: Int
    
    /// Whether to use MTLHeap for allocations (better memory locality)
    public let useHeapAllocation: Bool
    
    /// Default pool size per texture type
    public let defaultPoolSize: Int
    
    public init(
        maxTexturesPerKey: Int = 8,
        maxMemoryBudget: Int = 512 * 1024 * 1024, // 512 MB default
        useHeapAllocation: Bool = true,
        defaultPoolSize: Int = 4
    ) {
        self.maxTexturesPerKey = maxTexturesPerKey
        self.maxMemoryBudget = maxMemoryBudget
        self.useHeapAllocation = useHeapAllocation
        self.defaultPoolSize = defaultPoolSize
    }
    
    /// Default configuration optimized for video editing
    public static let `default` = TexturePoolConfig()
    
    /// High-performance configuration for multi-stream playback
    public static let multiStream = TexturePoolConfig(
        maxTexturesPerKey: 12,
        maxMemoryBudget: 1024 * 1024 * 1024, // 1 GB
        useHeapAllocation: true,
        defaultPoolSize: 6
    )
    
    /// Memory-constrained configuration
    public static let lowMemory = TexturePoolConfig(
        maxTexturesPerKey: 4,
        maxMemoryBudget: 256 * 1024 * 1024, // 256 MB
        useHeapAllocation: true,
        defaultPoolSize: 2
    )
}

// MARK: - TexturePool

/// Manages a pool of reusable Metal textures to minimize allocation overhead.
/// 
/// Optimizations for Apple Silicon:
/// - MTLHeap-based allocation for better memory locality and reduced fragmentation
/// - LRU eviction to stay within memory budget
/// - Memoryless texture support for transient render targets
/// - Thread-safe with fine-grained locking
public class TexturePool {
    private let device: MTLDevice
    private var pool: [String: [MTLTexture]] = [:]
    private let lock = NSLock()
    private let config: TexturePoolConfig
    
    /// MTLHeap for efficient texture allocation (Apple Silicon optimization)
    private var textureHeap: MTLHeap?
    private var heapSize: Int = 0
    
    /// Track memory usage for budget enforcement
    private var currentMemoryUsage: Int = 0
    
    /// LRU tracking for eviction
    private var accessOrder: [String] = []
    
    // MARK: - Initialization
    
    public init(device: MTLDevice, config: TexturePoolConfig = .default) {
        self.device = device
        self.config = config
        
        // Create MTLHeap if enabled and supported
        if config.useHeapAllocation {
            createHeap(size: min(config.maxMemoryBudget, 256 * 1024 * 1024)) // Start with 256MB
        }
    }
    
    /// Convenience init with default config
    public convenience init(device: MTLDevice) {
        self.init(device: device, config: .default)
    }
    
    // MARK: - Heap Management
    
    private func createHeap(size: Int) {
        let heapDescriptor = MTLHeapDescriptor()
        heapDescriptor.size = size
        heapDescriptor.storageMode = .private  // GPU-only for intermediates
        heapDescriptor.cpuCacheMode = .defaultCache
        heapDescriptor.hazardTrackingMode = .tracked  // Automatic hazard tracking
        
        // Apple Silicon optimization: Use sparse heaps if available
        if device.supportsFamily(.apple4) {
            heapDescriptor.type = .automatic  // Let Metal choose optimal placement
        }
        
        textureHeap = device.makeHeap(descriptor: heapDescriptor)
        textureHeap?.label = "TexturePool Heap"
        heapSize = size
    }
    
    /// Grows the heap if needed
    private func growHeapIfNeeded(for size: Int) {
        guard config.useHeapAllocation else { return }
        
        if let heap = textureHeap, heap.maxAvailableSize(alignment: 256) < size {
            // Create larger heap
            let newSize = min(heapSize * 2, config.maxMemoryBudget)
            if newSize > heapSize {
                createHeap(size: newSize)
            }
        }
    }
    
    // MARK: - Texture Acquisition
    
    /// Retrieves a texture matching the descriptor from the pool, or creates a new one.
    /// - Parameter descriptor: The configuration for the requested texture.
    /// - Returns: A reusable MTLTexture.
    public func acquire(descriptor: MTLTextureDescriptor) -> MTLTexture? {
        let key = cacheKey(for: descriptor)
        
        lock.lock()
        defer { lock.unlock() }
        
        // Update LRU
        updateLRU(key: key)
        
        // Try to get from pool
        if var textures = pool[key], !textures.isEmpty {
            let texture = textures.removeLast()
            pool[key] = textures
            return texture
        }
        
        // Evict if over budget
        evictIfNeeded(for: estimateTextureSize(descriptor))
        
        // Create new texture
        return createTexture(descriptor: descriptor, key: key)
    }
    
    /// Acquires a memoryless texture for transient use within a single render pass.
    /// These textures exist only in tile memory and have zero bandwidth cost.
    ///
    /// - Parameters:
    ///   - pixelFormat: Pixel format for the texture
    ///   - width: Texture width
    ///   - height: Texture height
    /// - Returns: A memoryless texture for on-tile operations
    public func acquireMemoryless(
        pixelFormat: MTLPixelFormat,
        width: Int,
        height: Int
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .memoryless  // Apple Silicon: stays in tile memory
        descriptor.usage = [.renderTarget]
        
        // Memoryless textures are not pooled - they're ephemeral by design
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = "Memoryless-\(pixelFormat.rawValue)"
        return texture
    }
    
    /// Acquires a texture optimized for intermediate render targets.
    /// Uses .private storage mode for GPU-only access.
    public func acquireIntermediate(
        pixelFormat: MTLPixelFormat,
        width: Int,
        height: Int,
        usage: MTLTextureUsage = [.shaderRead, .shaderWrite, .renderTarget]
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .private  // GPU-only, optimal for intermediates
        descriptor.usage = usage
        
        return acquire(descriptor: descriptor)
    }
    
    /// Acquires a texture that can be read by the CPU.
    /// Use sparingly - prefer .private for GPU-only operations.
    public func acquireShared(
        pixelFormat: MTLPixelFormat,
        width: Int,
        height: Int,
        usage: MTLTextureUsage = [.shaderRead, .shaderWrite]
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared  // CPU + GPU access
        descriptor.usage = usage
        
        return acquire(descriptor: descriptor)
    }
    
    // MARK: - Texture Creation
    
    private func createTexture(descriptor: MTLTextureDescriptor, key: String) -> MTLTexture? {
        var texture: MTLTexture?
        
        // Try heap allocation first if enabled and storage mode is compatible
        if config.useHeapAllocation,
           descriptor.storageMode == .private,
           let heap = textureHeap {
            
            let sizeAndAlign = device.heapTextureSizeAndAlign(descriptor: descriptor)
            
            if heap.maxAvailableSize(alignment: sizeAndAlign.align) >= sizeAndAlign.size {
                texture = heap.makeTexture(descriptor: descriptor)
            } else {
                // Try to grow heap
                growHeapIfNeeded(for: sizeAndAlign.size)
                if let newHeap = textureHeap {
                    texture = newHeap.makeTexture(descriptor: descriptor)
                }
            }
        }
        
        // Fall back to device allocation
        if texture == nil {
            texture = device.makeTexture(descriptor: descriptor)
        }
        
        // Track memory and label
        if let tex = texture {
            currentMemoryUsage += estimateTextureSize(descriptor)
            tex.label = "Pooled-\(key)"
        }
        
        return texture
    }
    
    // MARK: - Texture Return
    
    /// Returns a texture to the pool for reuse.
    /// - Parameter texture: The texture to return.
    public func `return`(_ texture: MTLTexture) {
        // Don't pool memoryless textures
        guard texture.storageMode != .memoryless else { return }
        
        let descriptor = descriptorFromTexture(texture)
        let key = cacheKey(for: descriptor)
        
        lock.lock()
        defer { lock.unlock() }
        
        var textures = pool[key] ?? []
        
        // Enforce per-key limit
        if textures.count >= config.maxTexturesPerKey {
            // Don't add, let it be deallocated
            currentMemoryUsage -= estimateTextureSize(descriptor)
            return
        }
        
        textures.append(texture)
        pool[key] = textures
    }
    
    // MARK: - Memory Management
    
    private func evictIfNeeded(for requiredSize: Int) {
        guard config.maxMemoryBudget > 0 else { return }
        
        while currentMemoryUsage + requiredSize > config.maxMemoryBudget && !accessOrder.isEmpty {
            let oldestKey = accessOrder.removeFirst()
            if var textures = pool[oldestKey], !textures.isEmpty {
                let evicted = textures.removeLast()
                currentMemoryUsage -= estimateTextureSize(descriptorFromTexture(evicted))
                pool[oldestKey] = textures.isEmpty ? nil : textures
            }
        }
    }
    
    private func updateLRU(key: String) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }
    
    private func estimateTextureSize(_ descriptor: MTLTextureDescriptor) -> Int {
        let bytesPerPixel: Int
        switch descriptor.pixelFormat {
        case .rgba16Float: bytesPerPixel = 8
        case .rgba32Float: bytesPerPixel = 16
        case .bgra8Unorm, .rgba8Unorm: bytesPerPixel = 4
        case .r16Float: bytesPerPixel = 2
        case .r32Float: bytesPerPixel = 4
        default: bytesPerPixel = 4
        }
        return descriptor.width * descriptor.height * bytesPerPixel * max(1, descriptor.mipmapLevelCount)
    }
    
    /// Clears all textures from the pool.
    public func purge() {
        lock.lock()
        defer { lock.unlock() }
        pool.removeAll()
        accessOrder.removeAll()
        currentMemoryUsage = 0
    }
    
    /// Returns current memory usage in bytes.
    public var memoryUsage: Int {
        lock.lock()
        defer { lock.unlock() }
        return currentMemoryUsage
    }
    
    /// Returns pool statistics for debugging.
    public var statistics: (pooledCount: Int, memoryMB: Double, heapSizeMB: Double) {
        lock.lock()
        defer { lock.unlock() }
        let count = pool.values.reduce(0) { $0 + $1.count }
        return (count, Double(currentMemoryUsage) / (1024 * 1024), Double(heapSize) / (1024 * 1024))
    }
    
    // MARK: - Helpers
    
    private func cacheKey(for descriptor: MTLTextureDescriptor) -> String {
        // Unique key based on properties that affect compatibility
        return "\(descriptor.pixelFormat.rawValue)-\(descriptor.width)x\(descriptor.height)-\(descriptor.storageMode.rawValue)-\(descriptor.usage.rawValue)-\(descriptor.mipmapLevelCount)"
    }
    
    private func descriptorFromTexture(_ texture: MTLTexture) -> MTLTextureDescriptor {
        let desc = MTLTextureDescriptor()
        desc.pixelFormat = texture.pixelFormat
        desc.width = texture.width
        desc.height = texture.height
        desc.storageMode = texture.storageMode
        desc.usage = texture.usage
        desc.mipmapLevelCount = texture.mipmapLevelCount
        return desc
    }
}
