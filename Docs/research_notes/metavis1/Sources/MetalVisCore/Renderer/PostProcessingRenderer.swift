import Foundation
@preconcurrency import Metal
import simd

/// HDR Post-Processing Pipeline with ACES tonemapping and bloom
public class PostProcessingRenderer {
    public let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    // Compute pipelines
    private let bloomDownsamplePipeline: MTLComputePipelineState
    private let bloomUpsamplePipeline: MTLComputePipelineState
    // private let bloomCompositePipeline: MTLComputePipelineState // Removed for optimization
    private let compositeOverlayPipeline: MTLComputePipelineState
    private let finalCompositePipeline: MTLComputePipelineState

    // Effect Passes
    private let halationPass: HalationPass
    private let anamorphicPass: AnamorphicPass
    private let lensDistortionPass: LensDistortionPass
    private let chromaticAberrationPass: ChromaticAberrationPass

    // Dummy resources
    private let dummyLUT: MTLTexture
    private let dummyBloom: MTLTexture

    // Zero buffer for clearing
    private var zeroBuffer: MTLBuffer?
    private var zeroBufferSize: Int = 0

    public init(device: MTLDevice) throws {
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            throw PostProcessingError.cannotCreateCommandQueue
        }
        commandQueue = queue

        // Create dummy 3D texture for when no LUT is provided
        // Upgrade: 2x2x2 Identity LUT in .rgba16Float to avoid sampling issues and format mismatch
        let lutDesc = MTLTextureDescriptor()
        lutDesc.textureType = .type3D
        lutDesc.width = 2
        lutDesc.height = 2
        lutDesc.depth = 2
        lutDesc.pixelFormat = .rgba16Float
        lutDesc.usage = .shaderRead
        guard let dummy = device.makeTexture(descriptor: lutDesc) else {
            throw PostProcessingError.cannotCreateTexture
        }

        // Fill with identity values
        // (0,0,0) (1,0,0) (0,1,0) (1,1,0) ...
        // r varies with x, g with y, b with z
        var data = [Float16](repeating: 0, count: 2 * 2 * 2 * 4)
        for z in 0 ..< 2 {
            for y in 0 ..< 2 {
                for x in 0 ..< 2 {
                    let index = (z * 4 + y * 2 + x) * 4
                    data[index] = Float16(x)
                    data[index + 1] = Float16(y)
                    data[index + 2] = Float16(z)
                    data[index + 3] = Float16(1.0)
                }
            }
        }

        dummy.replace(
            region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0), size: MTLSize(width: 2, height: 2, depth: 2)),
            mipmapLevel: 0,
            slice: 0,
            withBytes: data,
            bytesPerRow: 2 * 4 * 2, // 2 pixels * 4 channels * 2 bytes
            bytesPerImage: 2 * 2 * 4 * 2 // 2 rows * 2 pixels * 4 channels * 2 bytes
        )

        dummyLUT = dummy

        // Create dummy Bloom texture (1x1 black)
        let bloomDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 1, height: 1, mipmapped: false)
        bloomDesc.usage = .shaderRead
        guard let dummyB = device.makeTexture(descriptor: bloomDesc) else {
            throw PostProcessingError.cannotCreateTexture
        }
        var black = [Float16](repeating: 0, count: 4)
        dummyB.replace(region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0), size: MTLSize(width: 1, height: 1, depth: 1)), mipmapLevel: 0, withBytes: &black, bytesPerRow: 8)
        dummyBloom = dummyB

        // Load shaders - compile from source for SPM compatibility
        // We need to load dependencies in order
        let library: MTLLibrary

        let bundle = Bundle.module
        var shaderSource = ""
        
        // Helper to load shader source
        func loadShader(_ name: String, subdirectory: String? = nil) {
            // Try to find resource with subdirectory hint if possible, or just name
            // SPM .process() usually preserves directory structure if it's a folder.
            // But path(forResource:ofType:) is flat.
            // We might need to use inDirectory parameter.
            
            var path: String?
            if let sub = subdirectory {
                path = bundle.path(forResource: name, ofType: "metal", inDirectory: "Shaders/\(sub)")
                if path == nil {
                    // Try without Shaders prefix
                    path = bundle.path(forResource: name, ofType: "metal", inDirectory: sub)
                }
            }
            
            if path == nil {
                // Fallback to flat search
                path = bundle.path(forResource: name, ofType: "metal")
            }
            
            if let p = path, let source = try? String(contentsOfFile: p) {
                let lines = source.components(separatedBy: .newlines)
                let filtered = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#include \"") }
                shaderSource += filtered.joined(separator: "\n") + "\n"
            } else {
                print("WARNING: Could not load shader source for \(name)")
            }
        }

        // 1. Core Dependencies (Order Matters!)
        loadShader("ColorSpace") // Root - Defines ColorSpace namespace
        loadShader("Color", subdirectory: "Core") // Defines Core::Color
        loadShader("Noise", subdirectory: "Core")
        loadShader("ACES", subdirectory: "Core") // Uses ColorSpace and Core::Color
        
        // 2. Effects Dependencies
        loadShader("Bloom", subdirectory: "Effects")
        loadShader("Vignette", subdirectory: "Effects")
        loadShader("FilmGrain", subdirectory: "Effects")
        loadShader("ColorGrading", subdirectory: "Effects")
        
        // 3. Main Shader
        loadShader("PostProcessing")

        print("DEBUG: Shader Source Length: \(shaderSource.count)")
        
        if !shaderSource.isEmpty {
            do {
                library = try device.makeLibrary(source: shaderSource, options: nil)
            } catch {
                fatalError("🔥 METAL COMPILATION ERROR:\n\(error)")
            }
        } else if let defaultLibrary = device.makeDefaultLibrary() {
            library = defaultLibrary
        } else {
            throw PostProcessingError.cannotLoadShaders
        }

        // Create compute pipelines
        do {
            print("DEBUG: Creating bloom_downsample")
            bloomDownsamplePipeline = try Self.makeComputePipeline(device: device, library: library, functionName: "bloom_downsample")
            print("DEBUG: Creating bloom_upsample")
            bloomUpsamplePipeline = try Self.makeComputePipeline(device: device, library: library, functionName: "bloom_upsample")
            // self.bloomCompositePipeline = try Self.makeComputePipeline(device: device, library: library, functionName: "bloom_composite")
            print("DEBUG: Creating composite_overlay")
            compositeOverlayPipeline = try Self.makeComputePipeline(device: device, library: library, functionName: "composite_overlay")
            print("DEBUG: Creating final_composite")
            finalCompositePipeline = try Self.makeComputePipeline(device: device, library: library, functionName: "final_composite")
        } catch {
            fatalError("🔥 PIPELINE CREATION ERROR: \(error)")
        }

        // Initialize Effect Passes
        self.halationPass = HalationPass(device: device)
        self.anamorphicPass = AnamorphicPass(device: device)
        // LensDistortionPass requires a camera, but we can update it later or pass a default
        self.lensDistortionPass = LensDistortionPass(device: device, camera: PhysicalCamera())
        self.chromaticAberrationPass = ChromaticAberrationPass(device: device)
    }

    private static func makeComputePipeline(device: MTLDevice, library: MTLLibrary, functionName: String) throws -> MTLComputePipelineState {
        guard let function = library.makeFunction(name: functionName) else {
            throw PostProcessingError.cannotLoadShaders
        }
        return try device.makeComputePipelineState(function: function)
    }

    /// Apply full HDR post-processing pipeline
    public func processHDR(
        inputTexture: MTLTexture,
        config: PostProcessingConfig,
        commandBuffer externalCommandBuffer: MTLCommandBuffer? = nil,
        outputTexture externalOutputTexture: MTLTexture? = nil
    ) throws -> MTLTexture {
        // Create output texture
        // Use .bgra8Unorm (Linear/Untyped) to prevent Metal from applying implicit Gamma encoding
        // when writing sRGB/Rec.709 values from the LUT.
        let outputTexture: MTLTexture
        
        if let external = externalOutputTexture {
            outputTexture = external
        } else {
            let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: inputTexture.width,
                height: inputTexture.height,
                mipmapped: false
            )
            outputDescriptor.usage = [.shaderRead, .shaderWrite]

            guard let tex = device.makeTexture(descriptor: outputDescriptor) else {
                throw PostProcessingError.cannotCreateTexture
            }
            outputTexture = tex
        }

        let commandBuffer: MTLCommandBuffer
        let shouldCommit: Bool

        if let external = externalCommandBuffer {
            commandBuffer = external
            shouldCommit = false
        } else {
            guard let cmd = commandQueue.makeCommandBuffer() else {
                throw PostProcessingError.cannotCreateCommandBuffer
            }
            commandBuffer = cmd
            shouldCommit = true
        }
        
        // Create a dummy context for passes
        let dummyScene = Scene(camera: PhysicalCamera())
        let context = RenderContext(
            device: device,
            commandBuffer: commandBuffer,
            resolution: SIMD2(inputTexture.width, inputTexture.height),
            time: CFAbsoluteTimeGetCurrent(),
            scene: dummyScene
        )
        
        // Optimization: Ping-Pong Buffers
        // Instead of allocating a new texture for every pass, we allocate two reusable buffers
        // and swap between them. This significantly reduces memory bandwidth and allocation overhead.
        let intermediateDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: inputTexture.width,
            height: inputTexture.height,
            mipmapped: false
        )
        // Add .renderTarget usage to allow fast clearing via RenderPass
        intermediateDesc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        
        // Ensure zero buffer is large enough for full resolution
        let requiredSize = inputTexture.width * inputTexture.height * 8
        if zeroBuffer == nil || zeroBufferSize < requiredSize {
            zeroBufferSize = requiredSize
            zeroBuffer = device.makeBuffer(length: requiredSize, options: .storageModeShared)
            if let ptr = zeroBuffer?.contents() {
                memset(ptr, 0, requiredSize)
            }
        }
        
        // We only need these if we have active passes
        var ping: MTLTexture?
        var pong: MTLTexture?
        
        func clearTexture(_ texture: MTLTexture) {
            guard let buffer = zeroBuffer, let blit = commandBuffer.makeBlitCommandEncoder() else { return }
            
            blit.copy(from: buffer,
                      sourceOffset: 0,
                      sourceBytesPerRow: texture.width * 8,
                      sourceBytesPerImage: texture.height * texture.width * 8,
                      sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
                      to: texture,
                      destinationSlice: 0,
                      destinationLevel: 0,
                      destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.endEncoding()
        }
        
        func getPing() -> MTLTexture? {
            if ping == nil { 
                ping = device.makeTexture(descriptor: intermediateDesc)
                if let tex = ping { clearTexture(tex) }
            }
            return ping
        }
        
        func getPong() -> MTLTexture? {
            if pong == nil { 
                pong = device.makeTexture(descriptor: intermediateDesc)
                if let tex = pong { clearTexture(tex) }
            }
            return pong
        }
        
        var currentSource = inputTexture
        
        // Helper to swap buffers
        func applyPass(_ block: (MTLTexture, MTLTexture) throws -> Void) rethrows {
            // If current source is input, we write to Ping
            // If current source is Ping, we write to Pong
            // If current source is Pong, we write to Ping
            
            let dest: MTLTexture?
            if currentSource === inputTexture {
                dest = getPing()
            } else if currentSource === ping {
                dest = getPong()
            } else {
                dest = getPing()
            }
            
            if let destination = dest {
                try block(currentSource, destination)
                currentSource = destination
            }
        }
        
        // 1. Lens Distortion
        if config.lensDistortionEnabled {
            try? applyPass { src, dst in
                lensDistortionPass.camera.distortionK1 = config.lensDistortionK1
                lensDistortionPass.camera.distortionK2 = config.lensDistortionK2
                try lensDistortionPass.execute(
                    context: context,
                    inputTextures: ["main_buffer": src],
                    outputTextures: ["display_buffer": dst]
                )
            }
        }
        
        // 2. Chromatic Aberration
        if config.chromaticAberrationEnabled {
            try? applyPass { src, dst in
                chromaticAberrationPass.intensity = config.chromaticAberrationIntensity
                try chromaticAberrationPass.execute(
                    context: context,
                    inputTextures: ["main_buffer": src],
                    outputTextures: ["display_buffer": dst]
                )
            }
        }
        
        // 3. Anamorphic Flares
        if config.anamorphicEnabled {
            try? applyPass { src, dst in
                anamorphicPass.intensity = config.anamorphicIntensity
                anamorphicPass.threshold = config.anamorphicThreshold
                anamorphicPass.streakLength = config.anamorphicStreakLength
                try anamorphicPass.execute(
                    context: context,
                    inputTextures: ["main_buffer": src],
                    outputTextures: ["anamorphic_composite": dst]
                )
            }
        }
        
        // 4. Halation
        if config.halationEnabled {
            try? applyPass { src, dst in
                halationPass.intensity = config.halationIntensity
                halationPass.threshold = config.halationThreshold
                halationPass.radius = config.halationRadius
                try halationPass.execute(
                    context: context,
                    inputTextures: ["main_buffer": src],
                    outputTextures: ["halation_composite": dst]
                )
            }
        }

        // 5. Apply bloom if enabled
        var bloomTexture: MTLTexture?
        if config.bloomEnabled {
            bloomTexture = try applyBloom(
                inputTexture: currentSource, // Use current processed texture
                strength: config.bloomStrength,
                threshold: config.bloomThreshold,
                radius: config.bloomRadius,
                commandBuffer: commandBuffer
            )
        }

        // 6. Final composite with vignette, grain, LUT, letterbox, and bloom
        // This now includes Tonemapping and OETF
        // Input is Linear HDR

        try applyFinalComposite(
            inputTexture: currentSource, // Read from processed input
            outputTexture: outputTexture, // Write to final output
            bloomTexture: bloomTexture, // Pass bloom texture (optional)
            config: config,
            commandBuffer: commandBuffer
        )

        if shouldCommit {
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }

        return outputTexture
    }

    private func applyBloom(
        inputTexture: MTLTexture,
        strength _: Float,
        threshold: Float,
        radius: Int,
        commandBuffer: MTLCommandBuffer
    ) throws -> MTLTexture {
        if radius <= 0 {
            return dummyBloom
        }

        // Create mipchain for bloom
        var mipChain: [MTLTexture] = []
        var currentWidth = inputTexture.width / 2
        var currentHeight = inputTexture.height / 2

        // Ensure zero buffer (reuse existing if large enough)
        let w = max(1, currentWidth)
        let h = max(1, currentHeight)
        let requiredSize = w * h * 8
        if zeroBuffer == nil || zeroBufferSize < requiredSize {
            zeroBufferSize = requiredSize
            zeroBuffer = device.makeBuffer(length: requiredSize, options: .storageModeShared)
            if let ptr = zeroBuffer?.contents() {
                memset(ptr, 0, requiredSize)
            }
        }

        // Downsample pass
        for _ in 0 ..< radius {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float,
                width: max(1, currentWidth),
                height: max(1, currentHeight),
                mipmapped: false
            )
            descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget] // Add .renderTarget for clearing

            guard let mipTexture = device.makeTexture(descriptor: descriptor) else {
                throw PostProcessingError.cannotCreateTexture
            }
            
            // Clear mip texture using Blit (Robust)
            if let buffer = zeroBuffer, buffer.length >= currentWidth * currentHeight * 8 {
                 let blit = commandBuffer.makeBlitCommandEncoder()
                 let bytesPerRow = currentWidth * 8
                 let bytesPerImage = currentHeight * bytesPerRow
                 blit?.copy(from: buffer,
                           sourceOffset: 0,
                           sourceBytesPerRow: bytesPerRow,
                           sourceBytesPerImage: bytesPerImage,
                           sourceSize: MTLSize(width: currentWidth, height: currentHeight, depth: 1),
                           to: mipTexture,
                           destinationSlice: 0,
                           destinationLevel: 0,
                           destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
                 blit?.endEncoding()
            }

            mipChain.append(mipTexture)
            currentWidth /= 2
            currentHeight /= 2
        }

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw PostProcessingError.cannotCreateCommandBuffer
        }

        encoder.setComputePipelineState(bloomDownsamplePipeline)

        // First downsample from input (Apply Threshold)
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(mipChain[0], index: 1)
        
        var firstPassThreshold = threshold
        var knee: Float = 0.5
        encoder.setBytes(&firstPassThreshold, length: MemoryLayout<Float>.stride, index: 0)
        encoder.setBytes(&knee, length: MemoryLayout<Float>.stride, index: 1)

        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        var threadGroups = MTLSize(
            width: (mipChain[0].width + 15) / 16,
            height: (mipChain[0].height + 15) / 16,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)

        // Continue downsampling chain (No Threshold)
        var zeroThreshold: Float = 0.0
        encoder.setBytes(&zeroThreshold, length: MemoryLayout<Float>.stride, index: 0)
        
        for i in 1 ..< mipChain.count {
            encoder.setTexture(mipChain[i - 1], index: 0)
            encoder.setTexture(mipChain[i], index: 1)

            threadGroups = MTLSize(
                width: (mipChain[i].width + 15) / 16,
                height: (mipChain[i].height + 15) / 16,
                depth: 1
            )
            encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        }

        encoder.endEncoding()

        // Upsample pass (additive blending)
        guard let upEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw PostProcessingError.cannotCreateCommandBuffer
        }

        upEncoder.setComputePipelineState(bloomUpsamplePipeline)

        var filterRadius: Float = 1.0
        upEncoder.setBytes(&filterRadius, length: MemoryLayout<Float>.stride, index: 0)

        for i in stride(from: mipChain.count - 1, to: 0, by: -1) {
            upEncoder.setTexture(mipChain[i], index: 0)
            upEncoder.setTexture(mipChain[i - 1], index: 1)

            threadGroups = MTLSize(
                width: (mipChain[i - 1].width + 15) / 16,
                height: (mipChain[i - 1].height + 15) / 16,
                depth: 1
            )
            upEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        }

        upEncoder.endEncoding()

        return mipChain[0]
    }

    /*
     private func compositeBloom(
         sceneTexture: MTLTexture,
         bloomTexture: MTLTexture,
         outputTexture: MTLTexture,
         strength: Float,
         commandBuffer: MTLCommandBuffer
     ) throws {
         guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
             throw PostProcessingError.cannotCreateCommandBuffer
         }

         encoder.setComputePipelineState(bloomCompositePipeline)
         encoder.setTexture(sceneTexture, index: 0)
         encoder.setTexture(bloomTexture, index: 1)
         encoder.setTexture(outputTexture, index: 2)

         var bloomStrength = strength
         encoder.setBytes(&bloomStrength, length: MemoryLayout<Float>.stride, index: 0)

         let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
         let threadGroups = MTLSize(
             width: (sceneTexture.width + 15) / 16,
             height: (sceneTexture.height + 15) / 16,
             depth: 1
         )

         encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
         encoder.endEncoding()
     }
     */

    private func applyFinalComposite(
        inputTexture: MTLTexture,
        outputTexture: MTLTexture,
        bloomTexture: MTLTexture?,
        config: PostProcessingConfig,
        commandBuffer: MTLCommandBuffer
    ) throws {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw PostProcessingError.cannotCreateCommandBuffer
        }

        encoder.setComputePipelineState(finalCompositePipeline)
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)

        // Bind LUT if available, otherwise bind dummy 3D texture
        if let lut = config.lutTexture {
            encoder.setTexture(lut, index: 2)
        } else {
            encoder.setTexture(dummyLUT, index: 2)
        }

        // Bind Bloom if available, otherwise bind dummy
        if let bloom = bloomTexture {
            encoder.setTexture(bloom, index: 3)
        } else {
            encoder.setTexture(dummyBloom, index: 3)
        }

        var vignetteIntensity = config.vignetteIntensity
        var vignetteSmoothness = config.vignetteSmoothness
        var filmGrainStrength = config.filmGrainStrength
        var lutIntensity = config.lutIntensity
        var hasLUT: Bool = config.lutTexture != nil
        var time = Float(CFAbsoluteTimeGetCurrent().truncatingRemainder(dividingBy: 100.0))
        var letterboxRatio = config.letterboxRatio

        // Add Tonemap params to buffer
        var exposure = config.exposure
        var tonemapOp = config.tonemapOperator.rawValue
        // print("DEBUG: Tonemap Operator: \(tonemapOp)")
        var saturation = config.saturation
        var contrast = config.contrast
        var odt = config.odt.rawValue
        var debugFlag: UInt32 = config.debugFlag ? 1 : 0
        var validationMode = config.validationMode.rawValue

        // Bloom params
        var bloomStrength = config.bloomStrength
        var hasBloom: Bool = bloomTexture != nil

        encoder.setBytes(&vignetteIntensity, length: MemoryLayout<Float>.stride, index: 0)
        encoder.setBytes(&vignetteSmoothness, length: MemoryLayout<Float>.stride, index: 1)
        encoder.setBytes(&filmGrainStrength, length: MemoryLayout<Float>.stride, index: 2)
        encoder.setBytes(&lutIntensity, length: MemoryLayout<Float>.stride, index: 3)
        encoder.setBytes(&hasLUT, length: MemoryLayout<Bool>.stride, index: 4)
        encoder.setBytes(&time, length: MemoryLayout<Float>.stride, index: 5)
        encoder.setBytes(&letterboxRatio, length: MemoryLayout<Float>.stride, index: 6)

        // New params for Uber Shader
        encoder.setBytes(&exposure, length: MemoryLayout<Float>.stride, index: 7)
        encoder.setBytes(&tonemapOp, length: MemoryLayout<UInt32>.stride, index: 8)
        encoder.setBytes(&saturation, length: MemoryLayout<Float>.stride, index: 9)
        encoder.setBytes(&contrast, length: MemoryLayout<Float>.stride, index: 10)
        encoder.setBytes(&odt, length: MemoryLayout<UInt32>.stride, index: 11)
        encoder.setBytes(&debugFlag, length: MemoryLayout<UInt32>.stride, index: 12)
        encoder.setBytes(&validationMode, length: MemoryLayout<UInt32>.stride, index: 13)

        // Bloom params
        encoder.setBytes(&bloomStrength, length: MemoryLayout<Float>.stride, index: 14)
        encoder.setBytes(&hasBloom, length: MemoryLayout<Bool>.stride, index: 15)

        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (inputTexture.width + 15) / 16,
            height: (inputTexture.height + 15) / 16,
            depth: 1
        )

        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
    }

    public func compositeOverlay(
        baseTexture: MTLTexture,
        overlayTexture: MTLTexture,
        outputTexture: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) throws {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw PostProcessingError.cannotCreateCommandBuffer
        }

        encoder.setComputePipelineState(compositeOverlayPipeline)
        encoder.setTexture(baseTexture, index: 0)
        encoder.setTexture(overlayTexture, index: 1)
        encoder.setTexture(outputTexture, index: 2)

        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (outputTexture.width + 15) / 16,
            height: (outputTexture.height + 15) / 16,
            depth: 1
        )

        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
    }
}

// MARK: - Configuration

public struct PostProcessingConfig: Sendable {
    public var exposure: Float
    public var tonemapOperator: TonemapOperator
    public var saturation: Float
    public var contrast: Float
    public var bloomEnabled: Bool
    public var bloomStrength: Float
    public var bloomThreshold: Float
    public var bloomRadius: Int
    public var vignetteIntensity: Float
    public var vignetteSmoothness: Float
    public var filmGrainStrength: Float

    // New Effects
    public var halationEnabled: Bool
    public var halationIntensity: Float
    public var halationThreshold: Float
    public var halationRadius: Float

    public var anamorphicEnabled: Bool
    public var anamorphicIntensity: Float
    public var anamorphicThreshold: Float
    public var anamorphicStreakLength: Float

    public var lensDistortionEnabled: Bool
    public var lensDistortionK1: Float
    public var lensDistortionK2: Float

    public var chromaticAberrationEnabled: Bool
    public var chromaticAberrationIntensity: Float

    public var lutTexture: MTLTexture?
    public var lutIntensity: Float
    public var letterboxRatio: Float
    public var odt: OutputDeviceTransform
    public var debugFlag: Bool
    public var validationMode: ValidationMode

    public enum QualityPreset: Sendable {
        case mobile
        case balanced
        case reference
    }

    public init(preset: QualityPreset) {
        switch preset {
        case .mobile:
            self.init(
                exposure: 1.0,
                tonemapOperator: .aces,
                saturation: 1.0,
                contrast: 1.0,
                bloomEnabled: true,
                bloomStrength: 0.02,
                bloomRadius: 3, // Smaller radius
                vignetteIntensity: 0.3,
                filmGrainStrength: 0.0, // Disabled
                halationEnabled: false, // Disabled
                anamorphicEnabled: false, // Disabled
                lensDistortionEnabled: false, // Disabled
                chromaticAberrationEnabled: false, // Disabled
                odt: .sRGB
            )
        case .balanced:
            self.init(
                exposure: 1.0,
                tonemapOperator: .aces,
                saturation: 1.05,
                contrast: 1.02,
                bloomEnabled: true,
                bloomStrength: 0.04,
                bloomRadius: 5,
                vignetteIntensity: 0.5,
                filmGrainStrength: 0.02, // Reduced from 0.05
                halationEnabled: true,
                halationIntensity: 0.5,
                anamorphicEnabled: false, // Still expensive
                lensDistortionEnabled: true,
                chromaticAberrationEnabled: true,
                chromaticAberrationIntensity: 0.1, // Reduced from 0.3
                odt: .sRGB
            )
        case .reference:
            self.init(
                exposure: 1.0,
                tonemapOperator: .aces,
                saturation: 1.1,
                contrast: 1.05,
                bloomEnabled: true,
                bloomStrength: 0.06,
                bloomRadius: 7,
                vignetteIntensity: 0.6,
                filmGrainStrength: 0.04, // Reduced from 0.15
                halationEnabled: true,
                halationIntensity: 0.8,
                anamorphicEnabled: true,
                anamorphicIntensity: 0.6,
                lensDistortionEnabled: true,
                lensDistortionK1: -0.1,
                chromaticAberrationEnabled: true,
                chromaticAberrationIntensity: 0.2, // Reduced from 0.5
                odt: .sRGB
            )
        }
    }

    public init(
        exposure: Float = 1.0,
        tonemapOperator: TonemapOperator = .aces,
        saturation: Float = 1.0,
        contrast: Float = 1.0,
        bloomEnabled: Bool = true,
        bloomStrength: Float = 0.04,
        bloomThreshold: Float = 1.0,
        bloomRadius: Int = 5,
        vignetteIntensity: Float = 0.5,
        vignetteSmoothness: Float = 0.5,
        filmGrainStrength: Float = 0.0,
        
        halationEnabled: Bool = false,
        halationIntensity: Float = 0.8,
        halationThreshold: Float = 0.2,
        halationRadius: Float = 20.0,
        
        anamorphicEnabled: Bool = false,
        anamorphicIntensity: Float = 0.6,
        anamorphicThreshold: Float = 0.85,
        anamorphicStreakLength: Float = 8.0,
        
        lensDistortionEnabled: Bool = false,
        lensDistortionK1: Float = -0.1,
        lensDistortionK2: Float = 0.0,
        
        chromaticAberrationEnabled: Bool = false,
        chromaticAberrationIntensity: Float = 0.5,
        
        lutTexture: MTLTexture? = nil,
        lutIntensity: Float = 1.0,
        letterboxRatio: Float = 0.0,
        odt: OutputDeviceTransform = .sRGB,
        debugFlag: Bool = false,
        validationMode: ValidationMode = .off
    ) {
        self.exposure = exposure
        self.tonemapOperator = tonemapOperator
        self.saturation = saturation
        self.contrast = contrast
        self.bloomEnabled = bloomEnabled
        self.bloomStrength = bloomStrength
        self.bloomThreshold = bloomThreshold
        self.bloomRadius = bloomRadius
        self.vignetteIntensity = vignetteIntensity
        self.vignetteSmoothness = vignetteSmoothness
        self.filmGrainStrength = filmGrainStrength
        
        self.halationEnabled = halationEnabled
        self.halationIntensity = halationIntensity
        self.halationThreshold = halationThreshold
        self.halationRadius = halationRadius
        
        self.anamorphicEnabled = anamorphicEnabled
        self.anamorphicIntensity = anamorphicIntensity
        self.anamorphicThreshold = anamorphicThreshold
        self.anamorphicStreakLength = anamorphicStreakLength
        
        self.lensDistortionEnabled = lensDistortionEnabled
        self.lensDistortionK1 = lensDistortionK1
        self.lensDistortionK2 = lensDistortionK2
        
        self.chromaticAberrationEnabled = chromaticAberrationEnabled
        self.chromaticAberrationIntensity = chromaticAberrationIntensity
        
        self.lutTexture = lutTexture
        self.lutIntensity = lutIntensity
        self.letterboxRatio = letterboxRatio
        self.odt = odt
        self.debugFlag = debugFlag
        self.validationMode = validationMode
    }

    public static let cinematic = PostProcessingConfig(
        exposure: 1.2,
        tonemapOperator: .aces,
        saturation: 1.1,
        contrast: 1.05,
        bloomEnabled: true,
        bloomStrength: 0.08,
        vignetteIntensity: 0.6,
        filmGrainStrength: 0.15,
        letterboxRatio: 2.35,
        odt: .sRGB,
        validationMode: .off
    )

    public static let minimal = PostProcessingConfig(
        exposure: 1.0,
        tonemapOperator: .none,
        saturation: 1.0,
        contrast: 1.0,
        bloomEnabled: false,
        vignetteIntensity: 0.0,
        validationMode: .off
    )
}

public enum TonemapOperator: UInt32, Sendable {
    case aces = 0
    case reinhard = 1
    case uncharted2 = 2
    case none = 3
}

public enum OutputDeviceTransform: UInt32, Sendable {
    case sRGB = 0
    case rec709 = 1
    case p3D65 = 2
    case rec2020_pq = 3
    case rec2020_hlg = 4
    case linear = 5
    case sRGB_NoRRT = 6
}

public enum ValidationMode: UInt32, Sendable {
    case off = 0
    case aces = 1
}

struct TonemapUniforms {
    var exposure: Float
    var tonemapOperator: UInt32
    var saturation: Float
    var contrast: Float
}

public enum PostProcessingError: Error {
    case cannotCreateCommandQueue
    case cannotLoadShaders
    case cannotCreateTexture
    case cannotCreateCommandBuffer
}
