import Foundation
import Logging
import MetalVisCore
import Shared
@preconcurrency import Metal
import CoreImage
import CoreGraphics
import UniformTypeIdentifiers

public struct LabRunner: @unchecked Sendable {
    private let logger = Logger(label: "com.metalvis.lab")
    private let device: MTLDevice
    
    public init() throws {
        guard let d = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal device not found")
        }
        self.device = d
    }
    
    public func runManifest(path: String, output: String, validate: Bool = false, frameIndex: Int? = nil, exportPNG: Bool = false) async throws {
        // 1. Load Manifest
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(RenderManifest.self, from: data)
        
        logger.info("Loaded manifest: \(manifest.manifestId ?? "Unknown")")
        
        // 2. Resolve Pipeline
        let (pipeline, scene) = try ManifestResolver.resolve(manifest: manifest, device: device)
        
        // 3. Determine resolution from manifest
        // V5.1 doesn't explicitly state resolution in metadata, but intendedQualityProfile might hint at it.
        // Defaulting to HD (1920x1080) unless "4k" is mentioned in profile.
        let is4K = manifest.metadata.intendedQualityProfile.lowercased().contains("4k")
        var width = is4K ? 3840 : 1920
        var height = is4K ? 2160 : 1080
        
        // Handle Aspect Ratio
        let aspectRatioStr = manifest.metadata.targetAspectRatio
        if aspectRatioStr == "9:16" {
            // Vertical
            let temp = width
            width = height
            height = temp
        } else if aspectRatioStr.contains(":") {
            // Parse "W:H" (e.g. "2.39:1")
            let parts = aspectRatioStr.split(separator: ":")
            if parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]), h > 0 {
                let ratio = w / h
                // Keep width, adjust height (Letterboxing style)
                height = Int(Double(width) / ratio)
                // Ensure even height for encoding
                if height % 2 != 0 { height += 1 }
            }
        }
        
        // 4. Calculate timeline duration
        // V5.1 spec doesn't have framerate in metadata, defaulting to 30.
        let fps = 30
        let duration = Double(manifest.metadata.durationSeconds)
        let totalFrames = Int(duration * Double(fps))
        
        logger.info("Timeline: \(duration)s @ \(fps)fps = \(totalFrames) frames")
        
        // 5. Render frames
        guard let commandQueue = device.makeCommandQueue() else {
            logger.error("Failed to create command queue")
            throw NSError(domain: "LabRunner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create command queue"])
        }
        
        var renderedTextures: [MTLTexture] = []
        
        // Determine frame range
        let range: Range<Int>
        if let specificFrame = frameIndex {
            if specificFrame < 0 || specificFrame >= totalFrames {
                logger.error("Frame index \(specificFrame) out of bounds (0..<\(totalFrames))")
                throw NSError(domain: "LabRunner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Frame index out of bounds"])
            }
            range = specificFrame..<(specificFrame + 1)
            logger.info("Rendering single frame: \(specificFrame)")
        } else {
            range = 0..<totalFrames
            renderedTextures.reserveCapacity(totalFrames)
            logger.info("Starting full sequence rendering...")
        }
        
        // Create a blit encoder for copying textures
        let converter = FormatConverter(device: device)
        
        for i in range {
            let time = Double(i) / Double(fps)
            scene.update(time: Float(time))
            
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                logger.warning("Failed to create command buffer for frame \(i)")
                continue
            }
            
            let context = RenderContext(
                device: device,
                commandBuffer: commandBuffer,
                resolution: SIMD2(width, height),
                time: time,
                scene: scene
            )
            
            if let frameTexture = try? pipeline.render(context: context) {
                // Create a copy of the texture to store
                // FIX: Use a 2-step process for compatibility with Discrete GPUs (macOS)
                // 1. Render/Convert to a PRIVATE texture (always supported as render target)
                // 2. Blit to a MANAGED/SHARED texture for CPU readback
                
                let targetFormat: MTLPixelFormat = .bgra8Unorm
                
                // Step 1: Intermediate Private Texture (Render Target)
                let renderDesc = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: targetFormat,
                    width: frameTexture.width,
                    height: frameTexture.height,
                    mipmapped: false
                )
                renderDesc.usage = [.shaderRead, .renderTarget]
                renderDesc.storageMode = .private
                
                guard let intermediateTexture = device.makeTexture(descriptor: renderDesc) else {
                    logger.warning("Failed to create intermediate texture for frame \(i)")
                    continue
                }
                
                // Perform Format Conversion (RGBA16Float -> BGRA8Unorm) into Private Texture
                // If formats match, we can just blit, but for safety/consistency we'll use the converter or blit
                if frameTexture.pixelFormat == targetFormat {
                    // Direct Blit (Private -> Private)
                    if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
                        blitEncoder.copy(
                            from: frameTexture,
                            sourceSlice: 0,
                            sourceLevel: 0,
                            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                            sourceSize: MTLSize(width: frameTexture.width, height: frameTexture.height, depth: 1),
                            to: intermediateTexture,
                            destinationSlice: 0,
                            destinationLevel: 0,
                            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
                        )
                        blitEncoder.endEncoding()
                    }
                } else {
                    // Render Pass Conversion (Private -> Private)
                    try? converter.convert(source: frameTexture, to: intermediateTexture, commandBuffer: commandBuffer)
                }
                
                // Step 2: CPU Accessible Texture
                let readbackDesc = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: targetFormat,
                    width: frameTexture.width,
                    height: frameTexture.height,
                    mipmapped: false
                )
                readbackDesc.usage = [.shaderRead] // Only need to read
                
                #if os(macOS)
                // On macOS, .managed is preferred for CPU readback on discrete GPUs
                // On Apple Silicon, .managed is aliased to .shared, so this works for both
                readbackDesc.storageMode = .managed
                #else
                readbackDesc.storageMode = .shared
                #endif
                
                guard let readbackTexture = device.makeTexture(descriptor: readbackDesc) else {
                    logger.warning("Failed to create readback texture for frame \(i)")
                    continue
                }
                
                // Blit Private -> Managed/Shared
                if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
                    blitEncoder.copy(
                        from: intermediateTexture,
                        sourceSlice: 0,
                        sourceLevel: 0,
                        sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                        sourceSize: MTLSize(width: intermediateTexture.width, height: intermediateTexture.height, depth: 1),
                        to: readbackTexture,
                        destinationSlice: 0,
                        destinationLevel: 0,
                        destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
                    )
                    
                    #if os(macOS)
                    if readbackDesc.storageMode == .managed {
                        blitEncoder.synchronize(resource: readbackTexture)
                    }
                    #endif
                    
                    blitEncoder.endEncoding()
                }
                
                commandBuffer.commit()
                await commandBuffer.completed()
                renderedTextures.append(readbackTexture)
                
                if i % 24 == 0 {
                    logger.info("Rendered frame \(i)/\(totalFrames)")
                }
            }
        }
        
        // Handle Output
        if exportPNG || frameIndex != nil {
            // Export PNGs
            logger.info("Exporting PNGs...")
            let ciContext = CIContext(mtlDevice: device)
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
            
            for (index, texture) in renderedTextures.enumerated() {
                let actualFrameIndex = frameIndex ?? index
                guard let ciImage = CIImage(mtlTexture: texture, options: [.colorSpace: colorSpace]) else { continue }
                
                // Flip Y because Metal is top-left? No, Metal is top-left, CIImage usually bottom-left.
                // Actually, usually need to flip for PNG export if texture is standard Metal.
                let flipped = ciImage.transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -CGFloat(height)))
                
                if let cgImage = ciContext.createCGImage(flipped, from: flipped.extent) {
                    let filename = frameIndex != nil ? output : output.replacingOccurrences(of: ".mov", with: "_\(String(format: "%04d", actualFrameIndex)).png")
                    let url = URL(fileURLWithPath: filename)
                    
                    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { continue }
                    CGImageDestinationAddImage(destination, cgImage, nil)
                    CGImageDestinationFinalize(destination)
                    logger.info("Saved frame \(actualFrameIndex) to \(filename)")
                }
            }
        }
        
        // Only encode video if we rendered the full sequence and didn't just ask for a single frame
        if frameIndex == nil && !exportPNG {
            logger.info("Rendered \(renderedTextures.count) frames, starting encode...")
            
            // 6. Create stream from completed frames
            // Note: Using nonisolated(unsafe) to bypass Sendable checking
            // This is safe because all frames are fully rendered before encoding
            nonisolated(unsafe) let textures = renderedTextures
            let frameStream = AsyncStream<MTLTexture> { continuation in
                for texture in textures {
                    continuation.yield(texture)
                }
                continuation.finish()
            }
            
            // 7. Encode to video
            let encoder = VideoEncoder()
            let outputURL = URL(fileURLWithPath: output)
            
            try await encoder.encode(
                frames: frameStream,
                outputURL: outputURL,
                width: width,
                height: height,
                frameRate: fps,
                codec: "h264",
                quality: "high",
                colorSpace: "rec709"
            )
            
            logger.info("✅ Video saved: \(output)")
        }
        
        if validate && frameIndex == nil && !exportPNG {
            logger.info("🧪 Starting validation...")
            
            let outputURL = URL(fileURLWithPath: output)
            
            // 1. Video File Validation
            logger.info("Running Video File Validation...")
            // Map manifest codec string to AVVideoCodecType if possible, or default to what we encoded
            // The encoder above uses "h264", so we validate against that for now.
            // Ideally, the encoder should use manifest.meta.codec
            let videoSpec = VideoSpec(
                resolution: CGSize(width: width, height: height),
                frameRate: Float(fps),
                codec: .h264, 
                duration: duration,
                tolerance: 0.5 // Allow some slack for encoding
            )
            
            do {
                let isValid = try await VideoValidator.validate(fileURL: outputURL, against: videoSpec)
                if isValid {
                    logger.info("✅ Video File Validation PASSED")
                }
            } catch {
                logger.error("❌ Video File Validation FAILED: \(error)")
            }
            
            let service = try EffectValidationService(device: device)
            
            // Register validators
            await service.registerValidators([
                BloomValidator(device: device),
                VignetteValidator(device: device),
                HalationValidator(device: device),
                ChromaticAberrationValidator(device: device),
                FilmGrainValidator(device: device),
                AnamorphicValidator(device: device),
                TextLayoutValidator(device: device),
                ACESValidator(device: device),
                PBRValidator(device: device)
            ])
            
            let manifestURL = URL(fileURLWithPath: path)
            
            let report = try await service.validate(videoURL: outputURL, manifestURL: manifestURL)
            
            // Save report
            let reportPath = output.replacingOccurrences(of: ".mov", with: "_validation.json")
                                   .replacingOccurrences(of: ".mp4", with: "_validation.json")
            let reportURL = URL(fileURLWithPath: reportPath)
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let reportData = try encoder.encode(report)
            try reportData.write(to: reportURL)
            
            logger.info("📝 Validation report saved: \(reportPath)")
            
            if report.summary.failed > 0 {
                logger.warning("⚠️ Validation FAILED: \(report.summary.failed) effects failed")
            } else {
                logger.info("✅ Validation PASSED")
            }
        }
    }
    
    // Removed old runManifest and helpers that are replaced
    
    public func run(group: String?, profile: String?, renderer: String?, outputDir: String) async throws {
        logger.info("LabRunner is currently disabled for architectural migration.")
    }
    
    // Helper for format conversion
    private class FormatConverter {
        private let device: MTLDevice
        private var pipelineState: MTLRenderPipelineState?
        private let logger = Logger(label: "com.metalvis.lab.converter")
        
        init(device: MTLDevice) {
            self.device = device
        }
        
        func convert(source: MTLTexture, to destination: MTLTexture, commandBuffer: MTLCommandBuffer) throws {
            if pipelineState == nil {
                do {
                    // Robustness Fix: Embed shader source directly to avoid file loading issues in CLI
                    let shaderSource = """
                    #include <metal_stdlib>
                    using namespace metal;
                    
                    struct QuadVertexOut {
                        float4 position [[position]];
                        float2 uv;
                    };
                    
                    vertex QuadVertexOut vertex_converter(uint vertexID [[vertex_id]]) {
                        QuadVertexOut out;
                        // Fullscreen triangle
                        float2 position = float2(float((vertexID << 1) & 2), float(vertexID & 2));
                        out.position = float4(position * float2(2.0, 2.0) + float2(-1.0, -1.0), 0.0, 1.0);
                        // Flip Y check: Use 1.0 - position.y for correct orientation
                        out.uv = float2(position.x, 1.0 - position.y); 
                        return out;
                    }
                    
                    fragment float4 fragment_converter(QuadVertexOut in [[stage_in]], texture2d<float> texture [[texture(0)]]) {
                        constexpr sampler s(filter::linear, address::clamp_to_edge);
                        return texture.sample(s, in.uv);
                    }
                    """
                    
                    let library = try device.makeLibrary(source: shaderSource, options: nil)
                    let vertexFn = library.makeFunction(name: "vertex_converter")
                    let fragmentFn = library.makeFunction(name: "fragment_converter")
                    
                    guard let v = vertexFn, let f = fragmentFn else {
                        logger.error("Failed to create functions from embedded source")
                        return
                    }
                    
                    let descriptor = MTLRenderPipelineDescriptor()
                    descriptor.label = "Format Conversion"
                    descriptor.vertexFunction = v
                    descriptor.fragmentFunction = f
                    descriptor.colorAttachments[0].pixelFormat = destination.pixelFormat
                    
                    pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
                    logger.info("FormatConverter pipeline compiled successfully")
                } catch {
                    logger.error("Failed to create pipeline state: \(error)")
                    throw error
                }
            }
            
            guard let pipeline = pipelineState else {
                logger.error("Pipeline state is nil")
                return
            }
            
            let passDesc = MTLRenderPassDescriptor()
            passDesc.colorAttachments[0].texture = destination
            passDesc.colorAttachments[0].loadAction = .clear
            passDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            passDesc.colorAttachments[0].storeAction = .store
            
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc) else {
                logger.error("Failed to create render command encoder")
                return
            }
            encoder.label = "Format Conversion"
            
            encoder.setViewport(MTLViewport(
                originX: 0, originY: 0,
                width: Double(destination.width), height: Double(destination.height),
                znear: 0, zfar: 1
            ))
            
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(source, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }
    }
}
