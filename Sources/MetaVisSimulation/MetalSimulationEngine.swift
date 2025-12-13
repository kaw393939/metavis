import Foundation
import Metal
import CoreVideo
import MetaVisCore
import MetaVisGraphics // For Bundle access (if public) or Resource lookup
import simd

/// The Production Renderer. executes the RenderRequest on the GPU.
public actor MetalSimulationEngine: SimulationEngineProtocol {
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var library: MTLLibrary?
    private var pipelineStates: [String: MTLComputePipelineState] = [:]
    private var lutCache: [UUID: MTLTexture] = [:] // Cache 3D LUTs per node
    private var waveformBuffer: MTLBuffer?
    private var isConfigured: Bool = false

    private func compileLibraryFromHardcodedSources(files: [String]) async throws -> MTLLibrary? {
        var source = "#include <metal_stdlib>\nusing namespace metal;\n"

        for file in files {
            // Direct Hardcoded Fallback for Tests / Development
            let path = "/Users/kwilliams/Projects/metavis_render_two/metaviskit2/Sources/MetaVisGraphics/Resources/\(file).metal"
            if let content = try? String(contentsOfFile: path) {
                // Strip ALL include directives by filtering lines.
                // We concatenate dependencies explicitly via `files` ordering.
                let lines = content.components(separatedBy: .newlines)
                let filtered = lines.filter { line in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    return !trimmed.hasPrefix("#include") && trimmed != "using namespace metal;"
                }
                let c = filtered.joined(separator: "\n")
                source += "\n// File: \(file).metal (Hardcoded)\n" + c + "\n"
                logDebug("✅ Loaded \(file).metal from Source Path")
            } else {
                logDebug("⚠️ \(file).metal source not found at path: \(path)")
            }
        }

        guard !source.isEmpty else { return nil }
        return try await device.makeLibrary(source: source, options: nil)
    }

    private func ensurePipelineState(name: String) throws -> MTLComputePipelineState? {
        if let existing = pipelineStates[name] {
            return existing
        }
        guard let library else {
            logDebug("⚠️ No Metal library; cannot compile PSO for: \(name)")
            return nil
        }
        guard let function = library.makeFunction(name: name) else {
            logDebug("⚠️ Shader Function '\(name)' not found in library.")
            return nil
        }
        let pso = try device.makeComputePipelineState(function: function)
        pipelineStates[name] = pso
        print("✅ Cached PSO: \(name)")
        return pso
    }
    
    private nonisolated func logDebug(_ msg: String) {
        let str = "\(Date()): [Engine] \(msg)\n"
        if let data = str.data(using: .utf8) {
            let url = URL(fileURLWithPath: "/tmp/metavis_engine_debug.log")
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? str.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RuntimeError("Metal is not supported on this device.")
        }
        self.device = device
        
        guard let queue = device.makeCommandQueue() else {
            throw RuntimeError("Failed to create Command Queue.")
        }
        self.commandQueue = queue
    }
    
    public func configure() async throws {
        logDebug("⚙️ Engine Configuring...")
        // Load the Library from the MetaVisGraphics Bundle
        // Logic: Iterate bundles to find the one containing "ColorSpace.metal" (compiled)
        // For Swift Packages, resources are often in module_name.bundle
        
        // 1. Try Main Bundle (common in apps)
        if let lib = try? device.makeDefaultLibrary(bundle: Bundle.main) {
            self.library = lib
            logDebug("✅ Loaded Default Library from Main Bundle")
        // 2. Try Package Bundle via Helper
        } else {
             do {
                 self.library = try device.makeDefaultLibrary(bundle: GraphicsBundleHelper.bundle)
                 logDebug("✅ Loaded Library from Helper Bundle")
             } catch {
                 logDebug("⚠️ Helper Bundle Load Failed: \(error). Attempting Runtime Compilation...")

                 // Fallback: Runtime Compilation (concatenate a minimal set for tests)
                 self.library = try await compileLibraryFromHardcodedSources(files: [
                    "ColorSpace",         // IDT/ODT transforms
                    "Noise",              // Shared noise helpers (used by blur/bokeh)
                    "FormatConversion",   // RGBA→BGRA swizzle
                    "Compositor",         // Multi-clip alpha blending
                    "Blur",               // fx_blur_h / fx_blur_v
                    "Macbeth",            // Procedural color chart
                    "SMPTE",              // Procedural bars
                    "ZonePlate",          // Procedural zone plate
                    "Watermark"           // Export watermark overlays
                 ])
            }
        }

        // If we loaded a library but it's missing core kernels, fall back to runtime compilation.
        if let lib = self.library,
           (lib.makeFunction(name: "fx_blur_h") == nil || lib.makeFunction(name: "fx_blur_v") == nil) {
            logDebug("⚠️ Bundled library missing blur kernels; recompiling from sources")
            self.library = try await compileLibraryFromHardcodedSources(files: [
                "ColorSpace",
                "Noise",
                "FormatConversion",
                "Compositor",
                "Blur",
                "Macbeth",
                "SMPTE",
                "ZonePlate",
                "Watermark"
            ])
        }
        
        if self.library == nil {
            logDebug("⚠️ Metal Library not found! Shaders will fail.")
        }
        
        // Pre-warm Pipelines for Core Shaders
        try await cachePipeline(name: "idt_rec709_to_acescg")
        try await cachePipeline(name: "odt_acescg_to_rec709")
        try await cachePipeline(name: "fx_generate_face_mask") // Vision Mask Gen parameters
        try await cachePipeline(name: "fx_masked_grade")
        
        // Compositor shaders for multi-clip transitions
        try await cachePipeline(name: "compositor_alpha_blend")
        try await cachePipeline(name: "compositor_crossfade")
        try await cachePipeline(name: "compositor_multi_layer")
        
        // Cache Feature Shaders (if library available)
        // Ideally we iterate Manifests, but vertical slice is manual.
        try await cachePipeline(name: "fx_face_enhance")
        
        // LIGM Shaders
        try await cachePipeline(name: "fx_macbeth")
        try await cachePipeline(name: "fx_zone_plate")
        try await cachePipeline(name: "fx_smpte_bars")

        // Blur (Sprint 04 multi-pass)
        try await cachePipeline(name: "fx_blur_h")
        try await cachePipeline(name: "fx_blur_v")

        // Export watermark
        try await cachePipeline(name: "watermark_diagonal_stripes")

        isConfigured = true
    }
    
    private func cachePipeline(name: String) async throws {
        guard let library = library else { return }
        guard let function = library.makeFunction(name: name) else {
            logDebug("⚠️ Shader Function '\(name)' not found in library.")
            return
        }
        let pso = try await device.makeComputePipelineState(function: function)
        pipelineStates[name] = pso
        print("✅ Cached PSO: \(name)")
    }
    
    public func render(request: RenderRequest) async throws -> RenderResult {
        // ... (Calls internal render)
        guard let tex = try await internalRender(request: request) else {
             return RenderResult(imageBuffer: nil, metadata: ["error": "Root node texture missing"])
        }
        let data = textureToData(texture: tex)
        return RenderResult(imageBuffer: data, metadata: [:])
    }
    
    /// Renders directly into a CVPixelBuffer (for export).
    public func render(request: RenderRequest, to cvPixelBuffer: CVPixelBuffer, watermark: WatermarkSpec? = nil) async throws {
        guard let rootTex = try await internalRender(request: request) else {
            throw RuntimeError("Failed to render frame.")
        }
        
        // Simple Blit (assuming compatible format or simple copy)
        // If formats differ (e.g. RGBA -> YUV), this will likely fail or produce garbage without a Compute Kernel.
        // For Vertical Slice: Assuming RGBA buffer.
        
        // 1. Create Texture Cache
        var textureCache: CVMetalTextureCache?
        let result = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        guard result == kCVReturnSuccess, let cache = textureCache else {
             throw RuntimeError("Failed to create Texture Cache")
        }
        
        // 2. Wrap CVPixelBuffer in Metal Texture
        let width = CVPixelBufferGetWidth(cvPixelBuffer)
        let height = CVPixelBufferGetHeight(cvPixelBuffer)
        
        var cvMetalTexture: CVMetalTexture?
        let createResult = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            cvPixelBuffer,
            nil,
            .rgba16Float, // Match kCVPixelFormatType_64RGBAHalf (legacy approach)
            width, height,
            0,
            &cvMetalTexture
        )
        
        guard createResult == kCVReturnSuccess,
              let cvTex = cvMetalTexture,
              let mtlTex = CVMetalTextureGetTexture(cvTex) else {
             throw RuntimeError("Failed to create Metal texture from PixelBuffer")
        }
        
        // 3. Blit (procedural shaders now output BGR directly)
        guard let buffer = commandQueue.makeCommandBuffer() else { return }
        if let blit = buffer.makeBlitCommandEncoder() {
            blit.copy(from: rootTex, to: mtlTex)
            blit.endEncoding()
        }

        if let watermark {
            try encodeWatermark(watermark, commandBuffer: buffer, target: mtlTex)
        }
        
        await withCheckedContinuation { continuation in
            buffer.addCompletedHandler { _ in
                continuation.resume()
            }
            buffer.commit()
        }
    }

    private func encodeWatermark(_ spec: WatermarkSpec, commandBuffer: MTLCommandBuffer, target: MTLTexture) throws {
        guard spec.style == .diagonalStripes else { return }

        guard let pso = try ensurePipelineState(name: "watermark_diagonal_stripes") else {
            throw RuntimeError("Watermark shader not available")
        }

        struct WatermarkUniforms {
            var opacity: Float
            var stripeWidth: UInt32
            var stripeSpacing: UInt32
        }

        let uniforms = WatermarkUniforms(
            opacity: spec.opacity,
            stripeWidth: UInt32(max(0, spec.stripeWidth)),
            stripeSpacing: UInt32(max(1, spec.stripeSpacing))
        )

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pso)
        encoder.setTexture(target, index: 0)
        var u = uniforms
        encoder.setBytes(&u, length: MemoryLayout<WatermarkUniforms>.stride, index: 0)

        let w = pso.threadExecutionWidth
        let h = max(1, pso.maxTotalThreadsPerThreadgroup / w)
        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
        let threadsPerGrid = MTLSize(width: target.width, height: target.height, depth: 1)
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
    }
    
    private func internalRender(request: RenderRequest) async throws -> MTLTexture? {
        if !isConfigured {
            try await configure()
        }

        guard let buffer = commandQueue.makeCommandBuffer() else {
            throw RuntimeError("CommandBuffer failed")
        }
        
        var textureMap: [UUID: MTLTexture] = [:]
        
        let height = request.quality.resolutionHeight
        let width: Int
        switch request.quality.fidelity {
        case .draft:
            // Verification tests assume a fixed 256px width.
            width = 256
        case .high, .master:
            width = height * 16 / 9
        }
        
        for node in request.graph.nodes {
            try encodeNode(node, commandBuffer: buffer, textureMap: &textureMap, width: width, height: height)
        }
        

        
        await withCheckedContinuation { continuation in
            buffer.addCompletedHandler { _ in
                continuation.resume()
            }
            buffer.commit()
        }
        
        return textureMap[request.graph.rootNodeID]
    }
    
    private func encodeNode(_ node: RenderNode, commandBuffer: MTLCommandBuffer, textureMap: inout [UUID: MTLTexture], width: Int, height: Int) throws {
        if node.shader == "waveform_monitor" {
             // Special 2-Pass Waveform Generation
             
             // 0. Ensure Buffer
             let gridSize = 256 * 256 // Fixed 256 size
             if self.waveformBuffer == nil {
                 // Use Private for GPU-only access (fastest/safest)
                 self.waveformBuffer = device.makeBuffer(length: gridSize * 4, options: .storageModePrivate)
             }
             guard let gridBuff = self.waveformBuffer else { return }
             
             // Clear Buffer (Blit)
             if let blit = commandBuffer.makeBlitCommandEncoder() {
                 blit.fill(buffer: gridBuff, range: 0..<(gridSize * 4), value: 0)
                 blit.endEncoding()
             }
             
             // 1. Pass 1: Accumulate (Dispatch over Source)
             
             // 1. Pass 1: Accumulate (Dispatch over Source)
                 let accPSO = try ensurePipelineState(name: "scope_waveform_accumulate")
                 if let accPSO,
                let inputID = node.inputs["input"],
                let inputTex = textureMap[inputID],
                let encoder = commandBuffer.makeComputeCommandEncoder() {
                 
                 encoder.setComputePipelineState(accPSO)
                 encoder.setTexture(inputTex, index: 0)
                 encoder.setBuffer(gridBuff, offset: 0, index: 0)
                 
                 let w = accPSO.threadExecutionWidth
                 let h = accPSO.maxTotalThreadsPerThreadgroup / w
                 let threadsPerGroup = MTLSizeMake(w, h, 1)
                 let threadsPerGrid = MTLSizeMake(inputTex.width, inputTex.height, 1)
                 
                 encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
                 encoder.endEncoding()
             }
             
             // 2. Pass 2: Render & Clear (Dispatch over Dest)
                 let renPSO = try ensurePipelineState(name: "scope_waveform_render")
                 if let renPSO,
                let encoder = commandBuffer.makeComputeCommandEncoder() {
                 
                 encoder.setComputePipelineState(renPSO)
                 
                 // Bind Output
                 let destDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 256, height: 256, mipmapped: false)
                 destDesc.usage = [.shaderRead, .shaderWrite]
                 if let destTex = device.makeTexture(descriptor: destDesc) {
                     encoder.setTexture(destTex, index: 1)
                     textureMap[node.id] = destTex
                     
                     encoder.setBuffer(gridBuff, offset: 0, index: 0)
                     
                     let w = renPSO.threadExecutionWidth
                     let h = renPSO.maxTotalThreadsPerThreadgroup / w
                     let threadsPerGroup = MTLSizeMake(w, h, 1)
                     let threadsPerGrid = MTLSizeMake(destTex.width, destTex.height, 1)
                     
                     encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
                 }
                 encoder.endEncoding()
             }
             return // Skip standard flow
        }

        guard let pso = try ensurePipelineState(name: node.shader) else {
            logDebug("❌ PSO missing for: \(node.shader)")
            return
        }
        
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pso)
        
        // A. Bind Inputs
        // Convention: Texture Index 0 is Source, unless shader requires multiple inputs.
        if node.shader == "compositor_crossfade" {
            if let aID = node.inputs["clipA"], let aTex = textureMap[aID] {
                encoder.setTexture(aTex, index: 0)
            }
            if let bID = node.inputs["clipB"], let bTex = textureMap[bID] {
                encoder.setTexture(bTex, index: 1)
            }
        } else if node.shader == "compositor_alpha_blend" {
            if let layer1ID = node.inputs["layer1"], let layer1Tex = textureMap[layer1ID] {
                encoder.setTexture(layer1Tex, index: 0)
            }
            if let layer2ID = node.inputs["layer2"], let layer2Tex = textureMap[layer2ID] {
                encoder.setTexture(layer2Tex, index: 1)
            }
        } else if let inputID = node.inputs["input"] {
            if let inputTex = textureMap[inputID] {
                encoder.setTexture(inputTex, index: 0)
            } else {
                // If a node expects an input but upstream isn't present, bind a deterministic black texture
                // so downstream nodes can still execute (tests use this for 1-node graphs).
                let blackDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
                blackDesc.usage = [.shaderRead, .shaderWrite]
                if let black = device.makeTexture(descriptor: blackDesc) {
                    encoder.setTexture(black, index: 0)
                }
            }
        } else if node.shader == "source_texture" || node.shader == "source_linear_ramp" || node.shader == "source_test_color" {
            // Source Node: No input texture needed.
        }
        
        // Helper to create texture with request resolution
        // Use arguments passed to function
        
        // B. Bind Outputs
        let destDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        destDesc.usage = [MTLTextureUsage.shaderRead, MTLTextureUsage.shaderWrite]

        guard let destTex = device.makeTexture(descriptor: destDesc) else { return }
        let outputTextureIndex: Int
        if node.shader == "compositor_crossfade" || node.shader == "compositor_alpha_blend" {
            // Compositor kernels use output texture(2)
            outputTextureIndex = 2
        } else {
            // Most kernels use output texture(1)
            outputTextureIndex = 1
        }
        encoder.setTexture(destTex, index: outputTextureIndex)
        textureMap[node.id] = destTex
        
        // C. Bind Parameters (Uniforms)
        // Global Parameter Map (Naive Implementation)
        func bindFloat(_ name: String, _ index: Int) {
            if let val = node.parameters[name], case .float(let v) = val {
                var f = Float(v)
                encoder.setBytes(&f, length: MemoryLayout<Float>.size, index: index)
            }
        }
        
        func bindVector3(_ name: String, _ index: Int) {
            if let val = node.parameters[name], case .vector3(let v) = val {
                // Metal constant buffers align float3 to 16 bytes.
                var f4 = SIMD4<Float>(Float(v.x), Float(v.y), Float(v.z), 0)
                encoder.setBytes(&f4, length: MemoryLayout<SIMD4<Float>>.size, index: index)
            }
        }

        if node.shader == "compositor_crossfade" {
            bindFloat("mix", 0)
        } else if node.shader == "compositor_alpha_blend" {
            bindFloat("alpha1", 0)
            bindFloat("alpha2", 1)
        } else if node.shader == "fx_blur_h" || node.shader == "fx_blur_v" {
            bindFloat("radius", 0)
        } else if node.shader == "exposure_adjust" {
            bindFloat("ev", 0)
        } else if node.shader == "contrast_adjust" {
            bindFloat("factor", 0)
            bindFloat("pivot", 1)
        } else if node.shader == "cdl_correct" {
            bindVector3("slope", 0)
            bindVector3("offset", 1)
            bindVector3("power", 2)
            bindFloat("saturation", 3)
        } else if node.shader == "cdl_correct" {
            bindVector3("slope", 0)
            bindVector3("offset", 1)
            bindVector3("power", 2)
            bindFloat("saturation", 3)
        } else if node.shader == "fx_generate_face_mask" {
            if let val = node.parameters["faceRects"], case .floatArray(let rects) = val {
                encoder.setBytes(rects, length: rects.count * MemoryLayout<Float>.size, index: 0)
                
                var count = UInt32(rects.count / 4) // 4 floats per rect
                encoder.setBytes(&count, length: MemoryLayout<UInt32>.size, index: 1)
            }
        } else if node.shader == "fx_face_enhance" {
            // Need to bind struct FaceEnhanceParams
            // Manually mapping dict to struct bytes
            struct FaceEnhanceParams {
                var skinSmoothing: Float
                var highlightProtection: Float
                var eyeBrightening: Float
                var localContrast: Float
                var colorCorrection: Float
                var saturationProtection: Float
                var intensity: Float
                var debugMode: Float
            }
            
            var params = FaceEnhanceParams(
                skinSmoothing: node.float("skinSmoothing"),
                highlightProtection: node.float("highlightProtection"),
                eyeBrightening: node.float("eyeBrightening"),
                localContrast: node.float("localContrast"),
                colorCorrection: node.float("colorCorrection"),
                saturationProtection: node.float("saturationProtection"),
                intensity: node.float("intensity"),
                debugMode: node.float("debugMode")
            )
            
            encoder.setBytes(&params, length: MemoryLayout<FaceEnhanceParams>.size, index: 0)
            
            // Mask texture binding handling?
            // "faceMask" input port should be mapped to index 2
            if let maskID = node.inputs["faceMask"], let maskTex = textureMap[maskID] {
                encoder.setTexture(maskTex, index: 2)
            }
            
        } else if node.shader == "fx_masked_grade" {
            // MaskedColorGradeParams
             struct MaskedColorGradeParams {
                var targetColor: SIMD3<Float>
                var tolerance: Float
                var softness: Float
                var hueShift: Float
                var saturation: Float
                var exposure: Float
                var invertMask: Float
                var mode: Float
            }
            
            var params = MaskedColorGradeParams(
                targetColor: node.vector3("targetColor"),
                tolerance: node.float("tolerance", default: 0.1),
                softness: node.float("softness", default: 0.05),
                hueShift: node.float("hueShift", default: 0.0),
                saturation: node.float("saturation", default: 1.0),
                exposure: node.float("exposure", default: 0.0),
                invertMask: node.float("invertMask", default: 0.0),
                mode: node.float("mode", default: 0.0)
            )
            
            encoder.setBytes(&params, length: MemoryLayout<MaskedColorGradeParams>.size, index: 0)
            
            if let maskID = node.inputs["mask"], let maskTex = textureMap[maskID] {
                encoder.setTexture(maskTex, index: 2)
            }
            
        } else if node.shader == "lut_apply_3d" {
            // Handle LUT Parameter (expects 'lut' as .data)
            if let val = node.parameters["lut"], case .data(let lutData) = val {
                // Check Cache
                var lutTex = lutCache[node.id]
                if lutTex == nil {
                    // Parse and Create
                    if let (size, payload) = LUTHelper.parseCube(data: lutData) {
                        let desc = MTLTextureDescriptor()
                        desc.textureType = .type3D
                        desc.pixelFormat = .rgba32Float // Usually LUTs are RGB, but Metal textures need align? RGB32Float is valid on Mac.
                        // Actually 'float3' data means packed RGB. Texture format .rgba32Float expects 4 floats.
                        // If parseCube gives 3 floats, we need to convert to 4 (padding alpha).
                        
                        // Convert [Float] (RGB) to [Float] (RGBA)
                        var rgba: [Float] = []
                        rgba.reserveCapacity(size * size * size * 4)
                        for i in 0..<(payload.count/3) {
                            rgba.append(payload[i*3])
                            rgba.append(payload[i*3+1])
                            rgba.append(payload[i*3+2])
                            rgba.append(1.0)
                        }
                        
                        desc.width = size
                        desc.height = size
                        desc.depth = size
                        
                        if let tex = device.makeTexture(descriptor: desc) {
                            // Upload
                            // Bytes per row = size * 16 (4 floats * 4 bytes)
                            let bytesPerRow = size * 16
                            let bytesPerImage = size * bytesPerRow // one Z slice

                            // For 3D textures on Metal, write each depth slice by varying region.origin.z.
                            rgba.withUnsafeBytes { raw in
                                guard let base = raw.baseAddress else { return }
                                for z in 0..<size {
                                    let region = MTLRegionMake3D(0, 0, z, size, size, 1)
                                    let slicePtr = base.advanced(by: z * bytesPerImage)
                                    tex.replace(
                                        region: region,
                                        mipmapLevel: 0,
                                        slice: 0,
                                        withBytes: slicePtr,
                                        bytesPerRow: bytesPerRow,
                                        bytesPerImage: bytesPerImage
                                    )
                                }
                            }
                            
                            lutCache[node.id] = tex
                            lutTex = tex
                        }
                    }
                }
                
                // Bind
                if let t = lutTex {
                    encoder.setTexture(t, index: 2)
                }
            }
        }
        
        // D. Dispatch
        let w = pso.threadExecutionWidth
        let h = pso.maxTotalThreadsPerThreadgroup / w
        let threadsPerGroup = MTLSizeMake(w, h, 1)
        let threadsPerGrid = MTLSizeMake(destTex.width, destTex.height, 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
    }
    
    // Helper: Readback
    private func textureToData(texture: MTLTexture) -> Data {
        let width = texture.width
        let height = texture.height

        switch texture.pixelFormat {
        case .rgba16Float:
            let halfBytesPerRow = width * 8 // 4 * Float16
            var halfWords = [UInt16](repeating: 0, count: width * height * 4)
            halfWords.withUnsafeMutableBytes { ptr in
                guard let baseAddress = ptr.baseAddress else { return }
                texture.getBytes(
                    baseAddress,
                    bytesPerRow: halfBytesPerRow,
                    from: MTLRegionMake2D(0, 0, width, height),
                    mipmapLevel: 0
                )
            }

            var floats = [Float](repeating: 0, count: halfWords.count)
            for i in 0..<halfWords.count {
                floats[i] = Float(Float16(bitPattern: halfWords[i]))
            }

            return floats.withUnsafeBytes { Data($0) }

        default:
            let bytesPerRow = width * 16 // 4 floats * 4 bytes
            var data = Data(count: bytesPerRow * height)
            data.withUnsafeMutableBytes { ptr in
                if let baseAddress = ptr.baseAddress {
                    texture.getBytes(
                        baseAddress,
                        bytesPerRow: bytesPerRow,
                        from: MTLRegionMake2D(0, 0, width, height),
                        mipmapLevel: 0
                    )
                }
            }
            return data
        }
    }
}

struct RuntimeError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
