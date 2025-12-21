import AVFoundation
import Foundation
import Logging
@preconcurrency import Metal
import MetalPerformanceShaders

/// Main Metal rendering coordinator
public actor MetalRenderer {
    public nonisolated let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    public nonisolated var queue: MTLCommandQueue { commandQueue }
    private let logger: Logger

    private let blendNormalPipeline: MTLComputePipelineState?
    private let blendScreenPipeline: MTLComputePipelineState?
    private let linearToSRGBPipeline: MTLComputePipelineState?

    public init() throws {
        var logger = Logger(label: "com.metalvis.renderer")
        logger.logLevel = .info
        self.logger = logger

        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RendererError.noMetalDevice
        }
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            throw RendererError.cannotCreateCommandQueue
        }
        commandQueue = queue

        // Load default library
        var library = device.makeDefaultLibrary()

        if library == nil {
            // Try to find default.metallib in the module bundle (for tests)
            if let url = Bundle.module.url(forResource: "default", withExtension: "metallib") {
                do {
                    library = try device.makeLibrary(URL: url)
                } catch {
                    logger.warning("Failed to load library from bundle: \(error)")
                }
            }
        }

        // Fallback: Compile from source (Dev/Test mode)
        if library == nil {
            do {
                library = try MetalRenderer.loadShadersFromSource(bundle: Bundle.module, device: device)
                logger.info("Compiled shaders from source")
            } catch {
                logger.warning("Failed to compile shaders from source: \(error)")
            }
        }

        guard let library = library else {
            logger.warning("Could not load default Metal library. Shaders may be missing.")
            blendNormalPipeline = nil
            blendScreenPipeline = nil
            linearToSRGBPipeline = nil
            return
        }

        var normalPipeline: MTLComputePipelineState?
        var screenPipeline: MTLComputePipelineState?
        var srgbPipeline: MTLComputePipelineState?

        do {
            if let function = library.makeFunction(name: "blend_normal") {
                normalPipeline = try device.makeComputePipelineState(function: function)
            }
            if let function = library.makeFunction(name: "blend_screen") {
                screenPipeline = try device.makeComputePipelineState(function: function)
            }
            if let function = library.makeFunction(name: "linear_to_srgb") {
                srgbPipeline = try device.makeComputePipelineState(function: function)
            }
        } catch {
            logger.warning("Failed to create blend pipeline: \(error)")
        }

        blendNormalPipeline = normalPipeline
        blendScreenPipeline = screenPipeline
        linearToSRGBPipeline = srgbPipeline

        logger.info("Metal renderer initialized", metadata: [
            "device": "\(device.name)"
        ])
    }

    /// Render a single frame offscreen
    public nonisolated func renderFrame(
        width: Int,
        height: Int,
        clearColor: MTLClearColor,
        drawables: [any Drawable]
    ) throws -> MTLTexture {
        // Create offscreen texture
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.renderTarget, .shaderRead]

        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            throw RendererError.cannotCreateTexture
        }

        // Create render pass
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = clearColor
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else {
            throw RendererError.cannotCreateCommandBuffer
        }

        // Draw all drawables
        for drawable in drawables {
            try drawable.draw(encoder: renderEncoder, device: device)
        }

        renderEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return texture
    }

    /// Render a graph visualization frame
    public nonisolated func renderGraphFrame(
        width: Int,
        height: Int,
        nodes: [NodeDrawable],
        edges: [EdgeDrawable],
        chartElements: [ChartDrawable]? = nil,
        labels: [SDFTextRenderer.LabelRequest],
        graphRenderer: GraphRenderer,
        chartRenderer: ChartRenderer? = nil,
        textRenderer: SDFTextRenderer?
    ) throws -> MTLTexture {
        // Create offscreen texture
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.renderTarget, .shaderRead]

        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            throw RendererError.cannotCreateTexture
        }

        // Create render pass with dark background
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1.0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else {
            throw RendererError.cannotCreateCommandBuffer
        }

        let screenSize = SIMD2<Float>(Float(width), Float(height))

        // Draw edges first (behind nodes)
        graphRenderer.renderEdges(edges, encoder: renderEncoder, screenSize: screenSize)

        // Draw chart elements (behind nodes if mixed, but usually exclusive)
        if let chartElements = chartElements, let chartRenderer = chartRenderer {
            chartRenderer.render(elements: chartElements, encoder: renderEncoder, screenSize: screenSize)
        }

        // Draw nodes on top
        graphRenderer.renderNodes(nodes, encoder: renderEncoder, screenSize: screenSize)

        // Draw text labels on top of everything using SDF renderer
        if let textRenderer = textRenderer {
            try textRenderer.render(labels: labels, encoder: renderEncoder, screenSize: screenSize)
        }

        renderEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return texture
    }

    /// Export texture to image data
    public nonisolated func textureToImageData(_ texture: MTLTexture) throws -> Data {
        let width = texture.width
        let height = texture.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bufferSize = bytesPerRow * height

        var pixelData = [UInt8](repeating: 0, count: bufferSize)
        let region = MTLRegionMake2D(0, 0, width, height)

        texture.getBytes(&pixelData, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)

        return Data(pixelData)
    }

    /// Resize a texture using MPS
    public nonisolated func resizeTexture(_ source: MTLTexture, width: Int, height: Int, fit: Bool = false) throws -> MTLTexture {
        if source.width == width && source.height == height {
            return source
        }

        // If fit is requested, we need to preserve aspect ratio
        if fit {
            let sourceAspect = Double(source.width) / Double(source.height)
            let targetAspect = Double(width) / Double(height)

            // If aspects are close enough, just stretch
            if abs(sourceAspect - targetAspect) < 0.01 {
                return try resizeTexture(source, width: width, height: height, fit: false)
            }

            // Calculate fitted dimensions
            var newWidth = width
            var newHeight = height

            if sourceAspect > targetAspect {
                // Source is wider, fit to width
                newHeight = Int(Double(width) / sourceAspect)
            } else {
                // Source is taller, fit to height
                newWidth = Int(Double(height) * sourceAspect)
            }

            // 1. Scale to fitted size
            let scaledTexture = try resizeTexture(source, width: newWidth, height: newHeight, fit: false)

            // 2. Create final black texture
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: source.pixelFormat,
                width: width,
                height: height,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]

            guard let destination = device.makeTexture(descriptor: descriptor) else {
                throw RendererError.cannotCreateTexture
            }

            // 3. Blit to center
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                throw RendererError.cannotCreateCommandBuffer
            }

            // Clear destination to black using a render pass
            let renderPass = MTLRenderPassDescriptor()
            renderPass.colorAttachments[0].texture = destination
            renderPass.colorAttachments[0].loadAction = .clear
            renderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            renderPass.colorAttachments[0].storeAction = .store

            if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) {
                renderEncoder.endEncoding()
            }

            // Now create blit encoder
            guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
                throw RendererError.cannotCreateCommandBuffer
            }

            // Calculate offsets
            let x = (width - newWidth) / 2
            let y = (height - newHeight) / 2

            blitEncoder.copy(
                from: scaledTexture,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: newWidth, height: newHeight, depth: 1),
                to: destination,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: x, y: y, z: 0)
            )

            blitEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()

            return destination
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: source.pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]

        guard let destination = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.cannotCreateTexture
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw RendererError.cannotCreateCommandBuffer
        }

        let scale = MPSImageBilinearScale(device: device)
        scale.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: destination)

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return destination
    }

    /// Render text overlay on an existing texture
    public nonisolated func renderOverlay(
        texture: MTLTexture,
        labels: [SDFTextRenderer.LabelRequest],
        textRenderer: SDFTextRenderer
    ) throws {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .load // Load existing content
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else {
            throw RendererError.cannotCreateCommandBuffer
        }

        let screenSize = SIMD2<Float>(Float(texture.width), Float(texture.height))

        try textRenderer.render(labels: labels, encoder: renderEncoder, screenSize: screenSize)

        renderEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    /// Center a smaller texture into a larger background texture
    public nonisolated func centerTexture(_ source: MTLTexture, in width: Int, height: Int) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: source.pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]

        guard let destination = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.cannotCreateTexture
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw RendererError.cannotCreateCommandBuffer
        }

        // Clear to black
        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = destination
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        renderPass.colorAttachments[0].storeAction = .store

        if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) {
            renderEncoder.endEncoding()
        }

        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            throw RendererError.cannotCreateCommandBuffer
        }

        let x = (width - source.width) / 2
        let y = (height - source.height) / 2

        blitEncoder.copy(
            from: source,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: source.width, height: source.height, depth: 1),
            to: destination,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: x, y: y, z: 0)
        )

        blitEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return destination
    }

    /// Create a texture filled with a solid color
    public nonisolated func createSolidColorTexture(
        width: Int,
        height: Int,
        color: MTLClearColor,
        pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .renderTarget]

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.cannotCreateTexture
        }

        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = texture
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].clearColor = color
        renderPass.colorAttachments[0].storeAction = .store

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass)
        else {
            throw RendererError.cannotCreateCommandBuffer
        }

        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return texture
    }

    /// Blend two textures
    public nonisolated func blendTexture(
        source: MTLTexture,
        destination: MTLTexture,
        blendMode: String
    ) throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw RendererError.cannotCreateCommandBuffer
        }

        var pipeline: MTLComputePipelineState?

        if blendMode == "screen" {
            pipeline = blendScreenPipeline
        } else {
            pipeline = blendNormalPipeline
        }

        if let pipeline = pipeline,
           let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(source, index: 0)
            encoder.setTexture(destination, index: 1)

            let w = pipeline.threadExecutionWidth
            let h = pipeline.maxTotalThreadsPerThreadgroup / w
            let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
            let threadsPerGrid = MTLSize(width: destination.width, height: destination.height, depth: 1)

            encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
            encoder.endEncoding()
        }

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    /// Convert Linear Float16 texture to sRGB 8-bit texture for export
    public nonisolated func convertToSRGB(_ source: MTLTexture) throws -> MTLTexture {
        // Create output texture (sRGB encoded values, but stored in unorm)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, 
            width: source.width,
            height: source.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite] // Compute write
        
        guard let destination = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.cannotCreateTexture
        }
        
        guard let pipeline = linearToSRGBPipeline else {
             throw RendererError.cannotLoadShader
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw RendererError.cannotCreateCommandBuffer
        }
        
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(destination, index: 1)
        
        let w = pipeline.threadExecutionWidth
        let h = pipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
        let threadsPerGrid = MTLSize(width: destination.width, height: destination.height, depth: 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return destination
    }

    private static func loadShadersFromSource(bundle: Bundle, device: MTLDevice) throws -> MTLLibrary {
        let urls = bundle.urls(forResourcesWithExtension: "metal", subdirectory: nil) ?? []
        
        // Order matters for dependencies
        let order = [
            "ColorSpace.metal",
            "Color.metal",
            "Noise.metal",
            "ACES.metal",
            "Blending.metal",
            "FilmGrain.metal",
            "Vignette.metal",
            "ColorGrading.metal",
            "Bloom.metal",
            "InputProcessing.metal",
            "PostProcessing.metal",
            "SDFText.metal",
            "ImageTransform.metal",
            "GraphShaders.metal",
            "ChartShaders.metal"
        ]
        
        var processed = Set<String>()
        var fullSource = ""
        
        func processFile(_ name: String, url: URL) throws {
            var source = try String(contentsOf: url, encoding: .utf8)
            
            // Handle Includes
            source = source.replacingOccurrences(of: "#include \"ColorSpace.metal\"", with: "// #include \"ColorSpace.metal\"")
            source = source.replacingOccurrences(of: "#include \"ACES.metal\"", with: "// #include \"ACES.metal\"")
            source = source.replacingOccurrences(of: "#include \"Core/ACES.metal\"", with: "// #include \"Core/ACES.metal\"")
            source = source.replacingOccurrences(of: "#include \"../Core/Noise.metal\"", with: "// #include \"../Core/Noise.metal\"")
            source = source.replacingOccurrences(of: "#include \"../Core/Color.metal\"", with: "// #include \"../Core/Color.metal\"")
            source = source.replacingOccurrences(of: "#include \"Core/Noise.metal\"", with: "// #include \"Core/Noise.metal\"")
            source = source.replacingOccurrences(of: "#include \"Core/Color.metal\"", with: "// #include \"Core/Color.metal\"")
            source = source.replacingOccurrences(of: "#include \"Color.metal\"", with: "// #include \"Color.metal\"")
            source = source.replacingOccurrences(of: "#include \"Effects/FilmGrain.metal\"", with: "// #include \"Effects/FilmGrain.metal\"")
            source = source.replacingOccurrences(of: "#include \"Effects/Vignette.metal\"", with: "// #include \"Effects/Vignette.metal\"")
            source = source.replacingOccurrences(of: "#include \"Effects/ColorGrading.metal\"", with: "// #include \"Effects/ColorGrading.metal\"")
            source = source.replacingOccurrences(of: "#include \"Effects/Bloom.metal\"", with: "// #include \"Effects/Bloom.metal\"")
            
            // Handle Conflicts
            if name == "GraphShaders.metal" {
                source = source.replacingOccurrences(of: "VertexOut", with: "GraphVertexOut")
            }
            if name == "ChartShaders.metal" {
                source = source.replacingOccurrences(of: "VertexOut", with: "ChartVertexOut")
            }
            
            fullSource += "\n// File: \(name)\n"
            fullSource += source
            processed.insert(name)
        }
        
        // 1. Process ordered files
        for name in order {
            if let url = urls.first(where: { $0.lastPathComponent == name }) {
                try processFile(name, url: url)
            }
        }
        
        // 2. Process any remaining files
        for url in urls {
            let name = url.lastPathComponent
            if !processed.contains(name) {
                try processFile(name, url: url)
            }
        }
        
        return try device.makeLibrary(source: fullSource, options: nil)
    }
}

/// Protocol for drawable objects
public protocol Drawable: Sendable {
    func draw(encoder: MTLRenderCommandEncoder, device: MTLDevice) throws
}

public enum RendererError: Error {
    case noMetalDevice
    case cannotCreateCommandQueue
    case cannotCreateTexture
    case cannotCreateCommandBuffer
    case cannotCreateRenderPipeline
    case cannotLoadShader
}
