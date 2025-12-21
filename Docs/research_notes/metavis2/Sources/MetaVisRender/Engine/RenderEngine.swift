import Foundation
@preconcurrency import Metal
import MetalKit
import CoreText

// MARK: - RenderEngineConfig

/// Configuration for high-performance rendering
public struct RenderEngineConfig: Sendable {
    /// Maximum number of command buffers in flight
    public let maxInflightBuffers: Int
    
    /// Enable async command buffer submission
    public let enableAsyncSubmission: Bool
    
    /// Memory configuration for texture pool
    public let texturePoolConfig: TexturePoolConfig
    
    /// Enable parallel render pass encoding
    public let enableParallelEncoding: Bool
    
    public init(
        maxInflightBuffers: Int = 3,
        enableAsyncSubmission: Bool = true,
        texturePoolConfig: TexturePoolConfig = .default,
        enableParallelEncoding: Bool = true
    ) {
        self.maxInflightBuffers = maxInflightBuffers
        self.enableAsyncSubmission = enableAsyncSubmission
        self.texturePoolConfig = texturePoolConfig
        self.enableParallelEncoding = enableParallelEncoding
    }
    
    /// Standard configuration
    public static let standard = RenderEngineConfig()
    
    /// High-performance for video editing
    public static let highPerformance = RenderEngineConfig(
        maxInflightBuffers: 4,
        enableAsyncSubmission: true,
        texturePoolConfig: .multiStream,
        enableParallelEncoding: true
    )
}

public class RenderEngine {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    public let shaderLibrary: MTLLibrary // Expose library for pipeline creation
    public let texturePool: TexturePool
    
    /// Configuration for high-performance rendering
    private let config: RenderEngineConfig
    
    /// Inflight buffer semaphore for GPU pipelining
    private let inflightSemaphore: DispatchSemaphore
    
    // Resolver injection for testing
    public var resolver: (RenderManifest, MTLDevice) throws -> (RenderPipeline, Scene) = ManifestResolver.resolve
    
    public init(device: MTLDevice, config: RenderEngineConfig = .standard) {
        self.device = device
        self.config = config
        self.commandQueue = device.makeCommandQueue()!
        self.texturePool = TexturePool(device: device, config: config.texturePoolConfig)
        self.inflightSemaphore = DispatchSemaphore(value: config.maxInflightBuffers)
        do {
            self.shaderLibrary = try ShaderLibrary.loadDefaultLibrary(device: device)
        } catch {
            fatalError("Failed to load shader library: \(error)")
        }
    }
    
    /// Legacy initializer for backward compatibility
    public convenience init(device: MTLDevice) {
        self.init(device: device, config: .standard)
    }
    
    @MainActor
    public func execute(job: RenderJob, inputProvider: InputProvider? = nil) async throws {
        // 0. Validate manifest before any GPU work (fail fast)
        try job.manifest.validate()
        
        // 1. Resolve Pipeline and Scene from Manifest
        let (pipeline, scene) = try resolver(job.manifest, device)
        
        // Pre-warm glyphs if using StandardPipeline
        if let stdPipeline = pipeline as? StandardPipeline {
            await prewarm(manifest: job.manifest, glyphManager: stdPipeline.glyphManager, fontRegistry: stdPipeline.fontRegistry)
        }
        
        let step = 1.0 / job.fps
        // Use stride to generate time points
        // We use stride(from:to:by:) which excludes the upper bound, matching 0.0..<1.0 logic
        let timePoints = stride(from: job.timeRange.lowerBound, to: job.timeRange.upperBound, by: step)
        
        // Parse background color
        let clearColor = parseColor(job.manifest.scene.background)
        
        for time in timePoints {
            // Wait for available command buffer slot
            if config.enableAsyncSubmission {
                inflightSemaphore.wait()
            }
            
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                if config.enableAsyncSubmission {
                    inflightSemaphore.signal()
                }
                throw RenderError.commandBufferCreationFailed
            }
            
            // Update Scene
            scene.update(time: time)
            
            // Create RenderPassDescriptor based on output
            let descriptor: MTLRenderPassDescriptor
            var outputTexture: MTLTexture?
            
            switch job.output {
            case .texture(let texture):
                outputTexture = texture
                descriptor = MTLRenderPassDescriptor()
                descriptor.colorAttachments[0].texture = texture
                descriptor.colorAttachments[0].loadAction = .clear
                descriptor.colorAttachments[0].clearColor = clearColor
                descriptor.colorAttachments[0].storeAction = .store
                
            case .offscreen:
                // OPTIMIZATION: Use texturePool for intermediate textures
                let texDesc = makeOffscreenDescriptor(resolution: job.resolution)
                
                guard let texture = texturePool.acquire(descriptor: texDesc) else {
                    if config.enableAsyncSubmission {
                        inflightSemaphore.signal()
                    }
                    continue
                }
                outputTexture = texture
                
                descriptor = MTLRenderPassDescriptor()
                descriptor.colorAttachments[0].texture = texture
                descriptor.colorAttachments[0].loadAction = .clear
                descriptor.colorAttachments[0].clearColor = clearColor
                // OPTIMIZATION: Use .dontCare for intermediate if not reading back
                // But since offscreen callback needs data, we must .store
                descriptor.colorAttachments[0].storeAction = .store
                
            case .view(let view):
                guard let viewDescriptor = view.currentRenderPassDescriptor else {
                    if config.enableAsyncSubmission {
                        inflightSemaphore.signal()
                    }
                    continue
                }
                descriptor = viewDescriptor
                // Note: View descriptor usually has its own clear color managed by the view
            }
            
            let qualityMode: MVQualityMode
            switch job.manifest.metadata.quality {
            case "cinema": qualityMode = .cinema
            case "lab": qualityMode = .lab
            default: qualityMode = .realtime
            }
            
            let context = RenderContext(
                device: device,
                commandBuffer: commandBuffer,
                renderPassDescriptor: descriptor,
                resolution: job.resolution,
                time: time,
                scene: scene,
                quality: MVQualitySettings(mode: qualityMode),
                texturePool: texturePool,
                inputProvider: inputProvider
            )
            
            try pipeline.render(context: context)
            
            // Handle Output and Commit
            switch job.output {
            case .offscreen(let callback):
                await withCheckedContinuation { continuation in
                    commandBuffer.addCompletedHandler { [inflightSemaphore = self.inflightSemaphore, config = self.config] _ in
                        if config.enableAsyncSubmission {
                            inflightSemaphore.signal()
                        }
                        continuation.resume()
                    }
                    commandBuffer.commit()
                }
                if let texture = outputTexture {
                    await callback(texture, time)
                    // Return texture to pool after callback
                    texturePool.return(texture)
                }
                
            case .texture:
                await withCheckedContinuation { continuation in
                    commandBuffer.addCompletedHandler { [inflightSemaphore = self.inflightSemaphore, config = self.config] _ in
                        if config.enableAsyncSubmission {
                            inflightSemaphore.signal()
                        }
                        continuation.resume()
                    }
                    commandBuffer.commit()
                }
                
            case .view(let view):
                if let drawable = view.currentDrawable {
                    commandBuffer.present(drawable)
                }
                if config.enableAsyncSubmission {
                    commandBuffer.addCompletedHandler { [inflightSemaphore = self.inflightSemaphore] _ in
                        inflightSemaphore.signal()
                    }
                }
                commandBuffer.commit()
            }
        }
    }
    
    private func prewarm(manifest: RenderManifest, glyphManager: GlyphManager, fontRegistry: FontRegistry) async {
        // Collect all characters
        var characters = Set<Character>()
        if let elements = manifest.elements {
            for element in elements {
                if case .text(let textElement) = element {
                    for char in textElement.content {
                        characters.insert(char)
                    }
                }
            }
        }
        
        // Ensure font is registered (StandardPipeline registers Helvetica as ID 1)
        // In a real system, we'd map font names to IDs.
        let fontID: FontID = 1 
        
        guard let font = fontRegistry.getFont(fontID) else { return }
        
        for char in characters {
            var uni = Array(String(char).utf16)
            var glyphIndex: CGGlyph = 0
            CTFontGetGlyphsForCharacters(font, &uni, &glyphIndex, 1)
            let id = GlyphID(fontID: fontID, index: glyphIndex)
            
            // Poll until generated
            let start = Date()
            while glyphManager.getGlyph(id: id) == nil {
                if Date().timeIntervalSince(start) > 2.0 {
                    print("Timeout waiting for glyph: \(char)")
                    break
                }
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
        }
    }
    
    private func parseColor(_ hex: String) -> MTLClearColor {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        let scanner = Scanner(string: hexSanitized)
        if scanner.scanHexInt64(&rgb) {
            let r = Double((rgb & 0xFF0000) >> 16) / 255.0
            let g = Double((rgb & 0x00FF00) >> 8) / 255.0
            let b = Double(rgb & 0x0000FF) / 255.0
            print("Parsed background color: \(hex) -> R:\(r) G:\(g) B:\(b)")
            return MTLClearColor(red: r, green: g, blue: b, alpha: 1.0)
        } else {
            print("Failed to parse background color: \(hex), defaulting to black")
            return MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        }
    }
    
    /// Returns pool statistics for monitoring
    public var texturePoolStats: (pooledCount: Int, memoryMB: Double, heapSizeMB: Double) {
        texturePool.statistics
    }

    // MARK: - Internal Helpers for Testing
    
    internal func makeOffscreenDescriptor(resolution: SIMD2<Int>) -> MTLTextureDescriptor {
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,  // 16-bit float for HDR precision
            width: resolution.x,
            height: resolution.y,
            mipmapped: false
        )
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .private
        return texDesc
    }
}

public enum RenderError: Error, CustomStringConvertible {
    case commandBufferCreationFailed
    case shaderSourceNotFound(String)
    case shaderNotFound(String)
    case shaderCompilationFailed(String)
    case bufferAllocationFailed(String)
    case encoderCreationFailed
    case invalidParameter(String)
    
    public var description: String {
        switch self {
        case .commandBufferCreationFailed:
            return "Failed to create command buffer"
        case .shaderSourceNotFound(let name):
            return "Shader source not found: \(name)"
        case .shaderNotFound(let name):
            return "Shader not found: \(name)"
        case .shaderCompilationFailed(let msg):
            return "Shader compilation failed: \(msg)"
        case .bufferAllocationFailed(let name):
            return "Failed to allocate buffer: \(name)"
        case .encoderCreationFailed:
            return "Failed to create encoder"
        case .invalidParameter(let msg):
            return "Invalid parameter: \(msg)"
        }
    }
}
