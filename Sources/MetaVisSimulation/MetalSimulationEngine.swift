import Foundation
import Metal
import CoreVideo
import os
import MetaVisCore
import MetaVisGraphics // For Bundle access (if public) or Resource lookup
import MetaVisPerception
import simd

/// The Production Renderer. executes the RenderRequest on the GPU.
public actor MetalSimulationEngine: SimulationEngineProtocol {

    private nonisolated static let logger = Logger(subsystem: "com.metavis.simulation", category: "MetalSimulationEngine")
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var library: MTLLibrary?
    private var pipelineStates: [String: MTLComputePipelineState] = [:]
    private var renderPipelineStates: [String: MTLRenderPipelineState] = [:]
    // Cache 3D LUT textures by LUT content hash so recompiling graphs doesn't trigger re-upload.
    private var lutCache: [UInt64: MTLTexture] = [:]
    private var waveformBuffer: MTLBuffer?
    private let clipReader: ClipReader
    private let texturePool: TexturePool
    private var isConfigured: Bool = false

    // Debug/perf diagnostics: populated when METAVIS_PERF_NODE_TIMING=1.
    public private(set) var lastNodeTimingReport: String?


    private let maskDevice: MaskDevice
    private let maskTextureCache: CVMetalTextureCache?

    private var renderWarnings: [String] = []

    public enum EngineMode: Sendable, Equatable {
        case development
        case production
    }

    private let mode: EngineMode

    private func fnv1a64(_ data: Data) -> UInt64 {
        var hash: UInt64 = 14695981039346656037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }

    private func compileLibraryFromBundledMetalSources(files: [String], bundle: Bundle) async throws -> MTLLibrary? {
        var source = "#include <metal_stdlib>\nusing namespace metal;\n"

        for file in files {
            let url = bundle.url(forResource: file, withExtension: "metal")
            if let url, let content = try? String(contentsOf: url) {
                // Strip ALL include directives by filtering lines.
                // We concatenate dependencies explicitly via `files` ordering.
                let lines = content.components(separatedBy: .newlines)
                let filtered = lines.filter { line in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    return !trimmed.hasPrefix("#include") && trimmed != "using namespace metal;"
                }
                let c = filtered.joined(separator: "\n")
                source += "\n// File: \(file).metal (Bundle)\n" + c + "\n"
                logDebug("✅ Loaded \(file).metal from Bundle")
            } else {
                logDebug("⚠️ \(file).metal source not found in bundle")
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

    private func ensureCrossfadeRenderPipeline(pixelFormat: MTLPixelFormat, blendingEnabled: Bool) throws -> MTLRenderPipelineState? {
        let key = "compositor_crossfade_render|pf=\(pixelFormat.rawValue)|blend=\(blendingEnabled ? 1 : 0)"
        if let existing = renderPipelineStates[key] { return existing }
        guard let library else {
            logDebug("⚠️ No Metal library; cannot compile render PSO for crossfade")
            return nil
        }
        guard let v = library.makeFunction(name: "compositor_fullscreen_vertex"),
              let f = library.makeFunction(name: "compositor_read_fragment") else {
            logDebug("⚠️ Render functions missing for crossfade")
            return nil
        }

        let d = MTLRenderPipelineDescriptor()
        d.label = key
        d.vertexFunction = v
        d.fragmentFunction = f
        d.colorAttachments[0].pixelFormat = pixelFormat

        if blendingEnabled {
            let a = d.colorAttachments[0]!
            a.isBlendingEnabled = true
            a.rgbBlendOperation = .add
            a.alphaBlendOperation = .add
            // Use constant blend color (set via encoder.setBlendColor) as the mix factor.
            // result = src * t + dst * (1 - t)
            a.sourceRGBBlendFactor = .blendColor
            a.destinationRGBBlendFactor = .oneMinusBlendColor
            a.sourceAlphaBlendFactor = .blendAlpha
            a.destinationAlphaBlendFactor = .oneMinusBlendAlpha
        }

        let pso = try device.makeRenderPipelineState(descriptor: d)
        renderPipelineStates[key] = pso
        return pso
    }
    
    private nonisolated func logDebug(_ msg: String) {
        // Avoid nondeterministic side effects by default; opt-in with env var.
        guard ProcessInfo.processInfo.environment["METAVIS_ENGINE_DEBUG_LOG"] == "1" else { return }
        Self.logger.debug("[Engine] \(msg, privacy: .public)")
    }

    public init(mode: EngineMode = .development) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RuntimeError("Metal is not supported on this device.")
        }
        self.device = device
        self.mode = mode
        
        guard let queue = device.makeCommandQueue() else {
            throw RuntimeError("Failed to create Command Queue.")
        }
        self.commandQueue = queue

        self.clipReader = ClipReader(device: device)
        self.texturePool = TexturePool(device: device)

        self.maskDevice = MaskDevice()
        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        if status == kCVReturnSuccess {
            self.maskTextureCache = cache
        } else {
            self.maskTextureCache = nil
        }
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
                                 if mode == .production {
                                         throw error
                                 }
                                 logDebug("⚠️ Helper Bundle Load Failed: \(error). Attempting Runtime Compilation...")

                 // Fallback: Runtime Compilation (concatenate a minimal set for tests)
                                 self.library = try await compileLibraryFromBundledMetalSources(files: [
                    "ColorSpace",         // IDT/ODT transforms
                          "ACES",               // Shared ACES helpers (ToneMapping/Grading)
                      "Procedural",         // Shared procedural helpers (volumetric nebula)
                    "Noise",              // Shared noise helpers (used by blur/bokeh)
                    "FaceEnhance",        // fx_face_enhance / fx_beauty_enhance
                      "FaceMaskGenerator",  // fx_generate_face_mask
									"MaskedBlur",         // fx_masked_blur
                                        "MaskedColorGrade",   // fx_masked_grade
                          "FormatConversion",   // resize_bilinear_rgba16f (explicit adapter node)
                    "Compositor",         // Multi-clip alpha blending
                    "Blur",               // fx_blur_h / fx_blur_v
                          "ToneMapping",        // fx_tonemap_aces / fx_tonemap_pq
                          "ColorGrading",       // fx_color_grade_simple / fx_apply_lut
                    "Macbeth",            // Procedural color chart
                    "SMPTE",              // Procedural bars
                    "ZonePlate",          // Procedural zone plate
                      "StarField",          // Deterministic star field generator (nebula debug)
                      "VolumetricNebula",   // Volumetric nebula raymarcher + composite
                    "Watermark"           // Export watermark overlays
                                 ], bundle: GraphicsBundleHelper.bundle)
            }
        }

        // If we loaded a library but it's missing kernels we rely on in core flows, fall back to runtime compilation.
        // (This keeps AutoEnhance/Beauty from silently producing black frames when the packaged metallib is incomplete.)
        if let lib = self.library,
           (lib.makeFunction(name: "fx_blur_h") == nil
            || lib.makeFunction(name: "fx_blur_v") == nil
            || lib.makeFunction(name: "fx_beauty_enhance") == nil
            || lib.makeFunction(name: "fx_face_enhance") == nil
            || lib.makeFunction(name: "fx_generate_face_mask") == nil
            || lib.makeFunction(name: "fx_masked_grade") == nil
            || lib.makeFunction(name: "fx_volumetric_nebula") == nil
            || lib.makeFunction(name: "fx_volumetric_composite") == nil) {
            if mode == .production {
                throw RuntimeError("Bundled Metal library is missing required kernels")
            }
            logDebug("⚠️ Bundled library missing required kernels; recompiling from bundle sources")
            self.library = try await compileLibraryFromBundledMetalSources(files: [
                "ColorSpace",
                "ACES",
                "Procedural",
                "Noise",
                "FaceEnhance",
                "FaceMaskGenerator",
                "MaskedBlur",
                "MaskedColorGrade",
                "FormatConversion",
                "Compositor",
                "Blur",
                "ToneMapping",
                "ColorGrading",
                "Macbeth",
                "SMPTE",
                "ZonePlate",
                "StarField",
                "VolumetricNebula",
                "Watermark"
            ], bundle: GraphicsBundleHelper.bundle)
        }
        
        if self.library == nil {
            logDebug("⚠️ Metal Library not found! Shaders will fail.")
        }
        
        // Pre-warm Pipelines for Core Shaders
        try await cachePipeline(name: "idt_rec709_to_acescg")
        try await cachePipeline(name: "odt_acescg_to_rec709")
        try await cachePipeline(name: "odt_acescg_to_rec709_studio")
        try await cachePipeline(name: "odt_acescg_to_rec709_studio_tuned")
        try await cachePipeline(name: "lut_apply_3d")
        try await cachePipeline(name: "lut_apply_3d_rgba16f")
        try await cachePipeline(name: "odt_acescg_to_pq1000")
        try await cachePipeline(name: "fx_generate_face_mask") // Vision Mask Gen parameters
        try await cachePipeline(name: "fx_masked_grade")
        
        // Compositor shaders for multi-clip transitions
        try await cachePipeline(name: "compositor_alpha_blend")
        try await cachePipeline(name: "compositor_crossfade")
        try await cachePipeline(name: "compositor_dip")
        try await cachePipeline(name: "compositor_wipe")
        try await cachePipeline(name: "compositor_multi_layer")
        
        // Cache Feature Shaders (if library available)
        // Ideally we iterate Manifests, but vertical slice is manual.
        try await cachePipeline(name: "fx_face_enhance")
        try await cachePipeline(name: "fx_beauty_enhance")
        
        // LIGM Shaders
        try await cachePipeline(name: "fx_macbeth")
        try await cachePipeline(name: "fx_zone_plate")
        try await cachePipeline(name: "fx_smpte_bars")

        // Volumetric nebula
        try await cachePipeline(name: "fx_starfield")
        try await cachePipeline(name: "fx_volumetric_nebula")
        try await cachePipeline(name: "fx_volumetric_composite")

        // Blur (Sprint 04 multi-pass)
        try await cachePipeline(name: "fx_blur_h")
        try await cachePipeline(name: "fx_blur_v")
        try await cachePipeline(name: "fx_mip_blur")

        // Export watermark
        try await cachePipeline(name: "watermark_diagonal_stripes")

        // Mixed-resolution edge adapter (explicit node only)
        try await cachePipeline(name: "resize_bilinear_rgba16f")
        try await cachePipeline(name: "resize_bicubic_rgba16f")

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
        try await render(request: request, captureNodeTimings: false)
    }

    public func render(request: RenderRequest, captureNodeTimings: Bool) async throws -> RenderResult {
        // ... (Calls internal render)
        renderWarnings.removeAll(keepingCapacity: true)

        guard let tex = try await internalRender(request: request, captureNodeTimings: captureNodeTimings) else {
            return RenderResult(imageBuffer: nil, metadata: ["error": "Root node texture missing"])
        }

        // Perf/benchmark mode: allow skipping the expensive CPU readback path.
        // This is opt-in and only intended for tests/metrics.
        if request.skipReadback || ProcessInfo.processInfo.environment["METAVIS_SKIP_READBACK"] == "1" {
            var metadata: [String: String] = [:]
            if !renderWarnings.isEmpty {
                metadata["warnings"] = renderWarnings.joined(separator: " | ")
            }
            if let report = lastNodeTimingReport {
                metadata["nodeTimings"] = report
            }
            texturePool.checkin(tex)
            return RenderResult(imageBuffer: nil, metadata: metadata)
        }

        let readableTex: MTLTexture
        var stagingTex: MTLTexture?
        if tex.storageMode == .private {
            guard let copied = try await makeCPUReadableCopy(texture: tex) else {
                texturePool.checkin(tex)
                return RenderResult(imageBuffer: nil, metadata: ["error": "Failed to stage GPU texture for CPU readback"])
            }
            readableTex = copied
            stagingTex = copied
        } else {
            readableTex = tex
        }

        let data = textureToData(texture: readableTex)
        if let stagingTex {
            texturePool.checkin(stagingTex)
        }
        texturePool.checkin(tex)

        var metadata: [String: String] = [:]
        if !renderWarnings.isEmpty {
            metadata["warnings"] = renderWarnings.joined(separator: " | ")
        }
        if let report = lastNodeTimingReport {
            metadata["nodeTimings"] = report
        }
        return RenderResult(imageBuffer: data, metadata: metadata)
    }

    private func makeCPUReadableCopy(texture: MTLTexture) async throws -> MTLTexture? {
        let usage: MTLTextureUsage = [.shaderRead, .shaderWrite]
        guard let staging = texturePool.checkout(
            width: texture.width,
            height: texture.height,
            pixelFormat: texture.pixelFormat,
            usage: usage,
            storageMode: .shared
        ) else {
            return nil
        }

        guard let buffer = commandQueue.makeCommandBuffer(),
              let blit = buffer.makeBlitCommandEncoder() else {
            texturePool.checkin(staging)
            return nil
        }

        blit.copy(from: texture, to: staging)
        blit.endEncoding()

        await withCheckedContinuation { continuation in
            buffer.addCompletedHandler { _ in
                continuation.resume()
            }
            buffer.commit()
        }

        return staging
    }

    struct NodeTiming {
        var name: String
        var shader: String
        var gpuMs: Double?
    }

    private func makeMipmappedCopy(source: MTLTexture, commandBuffer: MTLCommandBuffer, mipLevelCount: Int) -> MTLTexture? {
        // Only 2D textures are supported in this path.
        guard source.textureType == .type2D else { return nil }

        // Create a mipmapped texture that matches the source format.
        let usage: MTLTextureUsage = [.shaderRead, .shaderWrite]
        guard let mipTex = texturePool.checkout(
            width: source.width,
            height: source.height,
            pixelFormat: source.pixelFormat,
            usage: usage,
            storageMode: .private,
            mipmapped: true,
            mipLevelCount: mipLevelCount
        ) else {
            return nil
        }

        guard let blit = commandBuffer.makeBlitCommandEncoder() else {
            texturePool.checkin(mipTex)
            return nil
        }

        let size = MTLSize(width: source.width, height: source.height, depth: 1)
        blit.copy(
            from: source,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: size,
            to: mipTex,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )

        // Hardware mip pyramid generation.
        blit.generateMipmaps(for: mipTex)
        blit.endEncoding()

        // We keep `mipTex` alive for the frame via `retainForFrame` at call sites.
        return mipTex
    }

    private func generateMips(for inputTex: MTLTexture, name: String) async throws -> (MTLTexture, NodeTiming)? {
        let fullLevels = max(1, Int(floor(log2(Double(max(1, max(inputTex.width, inputTex.height))))) + 1))
        // Always generate full chain for now or could optimize if we knew the max radius required.
        // For MaskedBlur optimization, we rely on the input texture being relatively small (downsampled), so mips are cheap.
        
        if let mipCB = commandQueue.makeCommandBuffer() {
            if let mip = makeMipmappedCopy(source: inputTex, commandBuffer: mipCB, mipLevelCount: fullLevels) {
                // Determine duration
                let start = mipCB.gpuStartTime
                await withCheckedContinuation { continuation in
                    mipCB.addCompletedHandler { _ in
                        continuation.resume()
                    }
                    mipCB.commit()
                }
                
                // Note: gpuWaitTime is not exposed in standard Metal without enabling counters,
                // but we can measure the timing if we wait.
                // Re-using the helper architecture from internalRender.
                
                let end = mipCB.gpuEndTime
                let dur = (start > 0 && end > start) ? (end - start) * 1000.0 : 0.0
                
                return (mip, NodeTiming(name: name, shader: "blit.generateMipmaps", gpuMs: dur))
            } else {
                // Failed to create mip texture
                mipCB.commit()
            }
        }
        return nil
    }
    
    /// Renders directly into a CVPixelBuffer (for export).
    public func render(request: RenderRequest, to cvPixelBuffer: CVPixelBuffer, watermark: WatermarkSpec? = nil, captureNodeTimings: Bool = false) async throws {
        let perNodeTimingEnabled = captureNodeTimings || (ProcessInfo.processInfo.environment["METAVIS_PERF_NODE_TIMING"] == "1")

        let dstW = CVPixelBufferGetWidth(cvPixelBuffer)
        let dstH = CVPixelBufferGetHeight(cvPixelBuffer)

        // For export, make the terminal node's output pixel format match the destination when possible,
        // so we can use a hardware blit copy (no swizzle/copy shaders).
        let dstPixelFormat = CVPixelBufferGetPixelFormatType(cvPixelBuffer)
        let desiredTerminalFormat: RenderNode.OutputSpec.PixelFormat = {
            switch dstPixelFormat {
            case kCVPixelFormatType_64RGBAHalf:
                return .rgba16Float
            case kCVPixelFormatType_32BGRA:
                return .bgra8Unorm
            default:
                return .rgba16Float
            }
        }()

        let exportGraph: RenderGraph = {
            let nodes = request.graph.nodes.map { n -> RenderNode in
                guard n.id == request.graph.rootNodeID else { return n }
                let out = RenderNode.OutputSpec(resolution: .full, pixelFormat: desiredTerminalFormat)
                return RenderNode(
                    id: n.id,
                    name: n.name,
                    shader: n.shader,
                    inputs: n.inputs,
                    parameters: n.parameters,
                    output: out,
                    timing: n.timing
                )
            }
            return RenderGraph(id: request.graph.id, nodes: nodes, rootNodeID: request.graph.rootNodeID)
        }()

        let exportRequest = RenderRequest(
            id: request.id,
            graph: exportGraph,
            time: request.time,
            quality: request.quality,
            assets: request.assets,
            renderFPS: request.renderFPS,
            renderPolicy: request.renderPolicy,
            edgePolicy: request.edgePolicy
        )

        guard let rootTex = try await internalRender(
            request: exportRequest,
            overrideWidth: dstW,
            overrideHeight: dstH,
            allowNonFloatTerminalOutputs: true,
            captureNodeTimings: captureNodeTimings
        ) else {
            throw RuntimeError("Failed to render frame.")
        }

        // Defensive guard: if we ever regress and render at a different size than the destination buffer,
        // fail loudly rather than silently producing partially black frames.
        if rootTex.width != dstW || rootTex.height != dstH {
            texturePool.checkin(rootTex)
            throw RuntimeError("Render size mismatch: rootTex=\(rootTex.width)x\(rootTex.height) dst=\(dstW)x\(dstH)")
        }
        
        // Simple Blit (assuming compatible format or simple copy)
        // If formats differ (e.g. RGBA -> YUV), this will likely fail or produce garbage without a Compute Kernel.
        // For Vertical Slice: Assuming RGBA buffer.
        
        // 1. Create Texture Cache
           let clock = ContinuousClock()
           let exportCPUStart = perNodeTimingEnabled ? clock.now : nil
        let cache: CVMetalTextureCache
        if let existing = self.maskTextureCache {
            cache = existing
        } else {
            var textureCache: CVMetalTextureCache?
            let result = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
            guard result == kCVReturnSuccess, let created = textureCache else {
                throw RuntimeError("Failed to create CVMetalTextureCache (status=\(result))")
            }
            cache = created
        }
        
        // 2. Wrap CVPixelBuffer in Metal Texture
        let width = dstW
        let height = dstH
        let metalPixelFormat: MTLPixelFormat
        switch dstPixelFormat {
        case kCVPixelFormatType_64RGBAHalf:
            metalPixelFormat = .rgba16Float
        case kCVPixelFormatType_32BGRA:
            metalPixelFormat = .bgra8Unorm
        default:
            throw RuntimeError("Unsupported CVPixelBuffer pixel format: \(dstPixelFormat)")
        }

        var cvMetalTexture: CVMetalTexture?
        let createResult = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            cvPixelBuffer,
            nil,
            metalPixelFormat,
            width, height,
            0,
            &cvMetalTexture
        )

        guard createResult == kCVReturnSuccess,
              let cvTex = cvMetalTexture,
              let mtlTex = CVMetalTextureGetTexture(cvTex) else {
            throw RuntimeError("Failed to create Metal texture from PixelBuffer")
        }

        if perNodeTimingEnabled, let exportCPUStart {
            let elapsed = clock.now - exportCPUStart
            let c = elapsed.components
            let seconds = Double(c.seconds) + (Double(c.attoseconds) / 1_000_000_000_000_000_000.0)
            let ms = seconds * 1000.0
            let part = String(format: "ExportCPU[cvpixelbuffer.wrap]=%.2fms", ms)
            if let existing = lastNodeTimingReport, !existing.isEmpty {
                lastNodeTimingReport = existing + " | " + part
            } else {
                lastNodeTimingReport = part
            }
        }

        // 3. Encode into pixel buffer
        // Prefer hardware blit copy (no swizzle-only shaders).
        guard let buffer = commandQueue.makeCommandBuffer() else { return }
        guard let blit = buffer.makeBlitCommandEncoder() else {
            throw RuntimeError("Failed to create blit encoder for export")
        }
        blit.copy(from: rootTex, to: mtlTex)
        blit.endEncoding()

        if let watermark {
            try encodeWatermark(watermark, commandBuffer: buffer, target: mtlTex)
        }
        
        let exportSubmitStart = perNodeTimingEnabled ? clock.now : nil
        await withCheckedContinuation { continuation in
            buffer.addCompletedHandler { _ in
                continuation.resume()
            }
            buffer.commit()
        }

        if perNodeTimingEnabled {
            let start = buffer.gpuStartTime
            let end = buffer.gpuEndTime
            let gpuMs = (start > 0 && end > 0 && end >= start) ? (end - start) * 1000.0 : 0.0

            var parts: [String] = []
            parts.reserveCapacity(2)
            parts.append(String(format: "ExportGPU[blit+watermark]=%.2fms", gpuMs))

            if let exportSubmitStart {
                let elapsed = clock.now - exportSubmitStart
                let c = elapsed.components
                let seconds = Double(c.seconds) + (Double(c.attoseconds) / 1_000_000_000_000_000_000.0)
                let wallMs = seconds * 1000.0
                parts.append(String(format: "ExportWall[submit->complete]=%.2fms", wallMs))
            }

            let suffix = parts.joined(separator: " | ")
            if let existing = lastNodeTimingReport, !existing.isEmpty {
                lastNodeTimingReport = existing + " | " + suffix
            } else {
                lastNodeTimingReport = suffix
            }
        }

        texturePool.checkin(rootTex)
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
    
    private func internalRender(
        request: RenderRequest,
        overrideWidth: Int? = nil,
        overrideHeight: Int? = nil,
        allowNonFloatTerminalOutputs: Bool = false,
        captureNodeTimings: Bool = false
    ) async throws -> MTLTexture? {
        if !isConfigured {
            try await configure()
        }

        // Sprint 24k integration hardening:
        // HDR display targets depend on kernels that may not exist in an older bundled metallib.
        // If missing, recompile from bundled sources so opt-in HDR renders are functional.
        if request.displayTarget == .hdrPQ1000 {
            let required = "odt_acescg_to_pq1000"
            let hasFn = library?.makeFunction(name: required) != nil
            if !hasFn {
                logDebug("⚠️ Missing '\(required)' in current Metal library; recompiling from bundled sources")
                self.library = try await compileLibraryFromBundledMetalSources(files: [
                    "ColorSpace",
                    "ACES",
                    "Procedural",
                    "Noise",
                    "FaceEnhance",
                    "FaceMaskGenerator",
                    "MaskedBlur",
                    "MaskedColorGrade",
                    "FormatConversion",
                    "Compositor",
                    "Blur",
                    "ToneMapping",
                    "ColorGrading",
                    "Macbeth",
                    "SMPTE",
                    "ZonePlate",
                    "StarField",
                    "VolumetricNebula",
                    "Watermark"
                ], bundle: GraphicsBundleHelper.bundle)
                pipelineStates.removeAll(keepingCapacity: true)
                // Warm the required ODT pipeline immediately so failure is explicit.
                guard try ensurePipelineState(name: required) != nil else {
                    throw RuntimeError("Required HDR ODT kernel missing after recompilation: \(required)")
                }
            }
        }

        renderWarnings.removeAll(keepingCapacity: true)

        let perNodeTimingEnabled = captureNodeTimings || (ProcessInfo.processInfo.environment["METAVIS_PERF_NODE_TIMING"] == "1")
        lastNodeTimingReport = nil

        let sharedBuffer: MTLCommandBuffer?
        if perNodeTimingEnabled {
            sharedBuffer = nil
        } else {
            guard let b = commandQueue.makeCommandBuffer() else {
                throw RuntimeError("CommandBuffer failed")
            }
            sharedBuffer = b
        }
        
        var textureMap: [UUID: MTLTexture] = [:]

        // Ensure deterministic and correct execution ordering even if the graph's node
        // array was assembled from unordered collections (e.g. dictionaries/sets).
        // We still render every node in the graph (not just reachable ones), but we
        // guarantee that a node's inputs are executed before the node.
        let orderedNodes: [RenderNode] = {
            var nodeByID: [UUID: RenderNode] = [:]
            nodeByID.reserveCapacity(request.graph.nodes.count)
            for node in request.graph.nodes {
                nodeByID[node.id] = node
            }

            enum VisitState { case visiting, visited }
            var stateByID: [UUID: VisitState] = [:]
            stateByID.reserveCapacity(request.graph.nodes.count)
            var out: [RenderNode] = []
            out.reserveCapacity(request.graph.nodes.count)

            func dfs(_ node: RenderNode) throws {
                if let state = stateByID[node.id] {
                    switch state {
                    case .visited:
                        return
                    case .visiting:
                        throw RuntimeError("RenderGraph cycle detected at node: \(node.name) [\(node.shader)]")
                    }
                }

                stateByID[node.id] = .visiting
                for inputID in node.inputs.values {
                    if let dep = nodeByID[inputID] {
                        try dfs(dep)
                    }
                }
                stateByID[node.id] = .visited
                out.append(node)
            }

            do {
                for node in request.graph.nodes {
                    try dfs(node)
                }
            } catch {
                // Fallback to provided ordering if something goes wrong, but keep the
                // failure visible to help diagnose graph construction problems.
                logDebug("⚠️ Topological sort failed: \(error). Falling back to original node order.")
                return request.graph.nodes
            }

            return out
        }()

        // Track how many downstream consumers each node output has so we can reuse
        // intermediate textures within a single frame and avoid GPU OOM.
        var remainingUses: [UUID: Int] = [:]
        remainingUses.reserveCapacity(orderedNodes.count)
        for node in orderedNodes {
            for inputID in node.inputs.values {
                remainingUses[inputID, default: 0] += 1
            }
        }

        // Per-frame reusable textures keyed by descriptor.
        var reusableByKey: [TexturePool.Key: [MTLTexture]] = [:]

        // Keep strong references to any textures we touch until the GPU work completes.
        // (Metal requires resources to stay alive until the command buffer finishes.)
        var frameTextures: [MTLTexture] = []
        frameTextures.reserveCapacity(request.graph.nodes.count)
        var frameTextureOIDs: Set<ObjectIdentifier> = []

        func retainForFrame(_ tex: MTLTexture) {
            let oid = ObjectIdentifier(tex)
            if frameTextureOIDs.insert(oid).inserted {
                frameTextures.append(tex)
            }
        }

        func reuseKey(for tex: MTLTexture) -> TexturePool.Key {
            TexturePool.Key(
                width: tex.width,
                height: tex.height,
                pixelFormat: tex.pixelFormat,
                mipLevelCount: max(1, tex.mipmapLevelCount),
                usageRaw: UInt64(tex.usage.rawValue),
                storageModeRaw: UInt64(tex.storageMode.rawValue)
            )
        }

        func canReuseInFrame(_ tex: MTLTexture) -> Bool {
            // Only reuse textures that can be written to; source textures are typically read-only.
            tex.usage.contains(.shaderWrite)
        }

        func releaseIfDead(_ nodeID: UUID) {
            guard nodeID != request.graph.rootNodeID else { return }
            guard let tex = textureMap.removeValue(forKey: nodeID) else { return }
            guard canReuseInFrame(tex) else { return }
            reusableByKey[reuseKey(for: tex), default: []].append(tex)
        }
        
        let height: Int
        let width: Int
        if let overrideWidth, let overrideHeight {
            width = overrideWidth
            height = overrideHeight
        } else {
            height = request.quality.resolutionHeight
            switch request.quality.fidelity {
            case .draft:
                // Verification tests assume a fixed 256px width.
                width = 256
            case .high, .master:
                width = height * 16 / 9
            }
        }
        


        func commitAndAwait(_ cb: MTLCommandBuffer) async {
            await withCheckedContinuation { continuation in
                cb.addCompletedHandler { _ in
                    continuation.resume()
                }
                cb.commit()
            }
        }

        func gpuMs(_ cb: MTLCommandBuffer) -> Double? {
            let start = cb.gpuStartTime
            let end = cb.gpuEndTime
            guard start > 0, end > 0, end >= start else { return nil }
            return (end - start) * 1000.0
        }

        if perNodeTimingEnabled {
            var timings: [NodeTiming] = []
            timings.reserveCapacity(orderedNodes.count + 4)

            for node in orderedNodes {
                let nodeSize = node.resolvedOutputSize(baseWidth: width, baseHeight: height)
                let outputConsumerCount = remainingUses[node.id] ?? 0

                if node.shader == "source_texture" {
                    try await prepareSourceTexture(for: node, request: request, width: nodeSize.width, height: nodeSize.height, textureMap: &textureMap)
                }
                if node.shader == "source_person_mask" {
                    try await preparePersonMaskTexture(for: node, request: request, width: nodeSize.width, height: nodeSize.height, textureMap: &textureMap)
                }

                // Split mip generation from the shader dispatch for clearer attribution.
                var input0Override: MTLTexture?
                var input1Override: MTLTexture? // New override slot for texture(1)

                if node.shader == "fx_mip_blur" {
                    // Standard blur: Input 0 needs mips.
                    if let inputID = (node.inputs["input"] ?? node.inputs["source"]), let inputTex = textureMap[inputID] {
                        if let shared = sharedBuffer {
                            // Fast path: encode on shared buffer, no wait.
                            let fullLevels = max(1, Int(floor(log2(Double(max(1, max(inputTex.width, inputTex.height))))) + 1))
                            if let mip = makeMipmappedCopy(source: inputTex, commandBuffer: shared, mipLevelCount: fullLevels) {
                                input0Override = mip
                                retainForFrame(mip)
                            }
                        } else {
                            // Slow path: independent buffer for timing.
                            if let (mip, timing) = try await generateMips(for: inputTex, name: "MipGen.Blur") {
                                input0Override = mip
                                retainForFrame(mip)
                                timings.append(timing)
                            }
                        }
                    }
                } else if node.shader == "fx_masked_blur" {
                    // Masked Blur (Dual Input): Input 1 (blur_base) needs mips.
                    if let inputID = node.inputs["blur_base"], let inputTex = textureMap[inputID] {
                        if let shared = sharedBuffer {
                             // Fast path
                             let fullLevels = max(1, Int(floor(log2(Double(max(1, max(inputTex.width, inputTex.height))))) + 1))
                             if let mip = makeMipmappedCopy(source: inputTex, commandBuffer: shared, mipLevelCount: fullLevels) {
                                 input1Override = mip
                                 retainForFrame(mip)
                             }
                        } else {
                             // Slow path
                             if let (mip, timing) = try await generateMips(for: inputTex, name: "MipGen.MaskedBlur") {
                                 input1Override = mip
                                 retainForFrame(mip)
                                 timings.append(timing)
                             }
                        }
                    } else if let inputID = node.inputs["input"] ?? node.inputs["source"], let inputTex = textureMap[inputID] {
                        // Legacy Fallback
                        if let shared = sharedBuffer {
                             let fullLevels = max(1, Int(floor(log2(Double(max(1, max(inputTex.width, inputTex.height))))) + 1))
                             if let mip = makeMipmappedCopy(source: inputTex, commandBuffer: shared, mipLevelCount: fullLevels) {
                                 input0Override = mip
                                 retainForFrame(mip)
                             }
                        } else {
                             if let (mip, timing) = try await generateMips(for: inputTex, name: "MipGen.MaskedBlurLegacy") {
                                 input0Override = mip
                                 retainForFrame(mip)
                                 timings.append(timing)
                             }
                        }
                    }
                }

                guard let nodeCB = commandQueue.makeCommandBuffer() else {
                    throw RuntimeError("CommandBuffer failed")
                }

                try encodeNode(
                    node,
                    commandBuffer: nodeCB,
                    textureMap: &textureMap,
                    width: nodeSize.width,
                    height: nodeSize.height,
                    edgePolicy: request.edgePolicy,
                    outputConsumerCount: outputConsumerCount,
                    allowNonFloatTerminalOutputs: allowNonFloatTerminalOutputs,
                    reusableByKey: &reusableByKey,
                    retainForFrame: retainForFrame,
                    input0Override: input0Override,
                    input1Override: input1Override
                )

                // After encoding the node, decrement remaining uses for its inputs.
                for inputID in node.inputs.values {
                    guard let count = remainingUses[inputID] else { continue }
                    let next = count - 1
                    remainingUses[inputID] = next
                    if next <= 0 {
                        releaseIfDead(inputID)
                    }
                }

                await commitAndAwait(nodeCB)
                timings.append(NodeTiming(name: node.name, shader: node.shader, gpuMs: gpuMs(nodeCB)))
            }

            var parts: [String] = []
            parts.reserveCapacity(timings.count)
            for t in timings {
                if let ms = t.gpuMs {
                    parts.append(String(format: "%@[%@]=%.2fms", t.name, t.shader, ms))
                } else {
                    parts.append("\(t.name)[\(t.shader)]=n/a")
                }
            }
            lastNodeTimingReport = parts.joined(separator: " | ")
        } else {
            guard let buffer = sharedBuffer else {
                throw RuntimeError("CommandBuffer missing")
            }

            for node in orderedNodes {
                let nodeSize = node.resolvedOutputSize(baseWidth: width, baseHeight: height)
                let outputConsumerCount = remainingUses[node.id] ?? 0

                if node.shader == "source_texture" {
                    try await prepareSourceTexture(for: node, request: request, width: nodeSize.width, height: nodeSize.height, textureMap: &textureMap)
                }
                if node.shader == "source_person_mask" {
                    try await preparePersonMaskTexture(for: node, request: request, width: nodeSize.width, height: nodeSize.height, textureMap: &textureMap)
                }

                try encodeNode(
                    node,
                    commandBuffer: buffer,
                    textureMap: &textureMap,
                    width: nodeSize.width,
                    height: nodeSize.height,
                    edgePolicy: request.edgePolicy,
                    outputConsumerCount: outputConsumerCount,
                    allowNonFloatTerminalOutputs: allowNonFloatTerminalOutputs,
                    reusableByKey: &reusableByKey,
                    retainForFrame: retainForFrame
                )

                // After encoding the node, decrement remaining uses for its inputs.
                for inputID in node.inputs.values {
                    guard let count = remainingUses[inputID] else { continue }
                    let next = count - 1
                    remainingUses[inputID] = next
                    if next <= 0 {
                        releaseIfDead(inputID)
                    }
                }
            }

            await withCheckedContinuation { continuation in
                buffer.addCompletedHandler { _ in
                    continuation.resume()
                }
                buffer.commit()
            }
        }

        let rootTex = textureMap[request.graph.rootNodeID]

        // Return all non-root textures to the pool for reuse on subsequent frames.
        // (checkin() is a no-op for textures not created by the pool.)
        if let rootTex {
            let rootID = ObjectIdentifier(rootTex)
            for tex in frameTextures where ObjectIdentifier(tex) != rootID {
                texturePool.checkin(tex)
            }
        } else {
            for tex in frameTextures {
                texturePool.checkin(tex)
            }
        }

        return rootTex
    }

    private func prepareSourceTexture(
        for node: RenderNode,
        request: RenderRequest,
        width: Int,
        height: Int,
        textureMap: inout [UUID: MTLTexture]
    ) async throws {
        guard let assetIDValue = node.parameters["asset_id"],
              case .string(let assetID) = assetIDValue else {
            return
        }

        let timeSeconds: Double
        if let t = node.parameters["time_seconds"], case .float(let s) = t {
            timeSeconds = s
        } else {
            timeSeconds = request.time.seconds
        }

        // Resolve sourceFn -> path/URL.
        let resolved = request.assets[assetID] ?? assetID
        let url: URL?
        if let u = URL(string: resolved), u.scheme != nil {
            url = u
        } else {
            url = URL(fileURLWithPath: resolved)
        }
        guard let assetURL = url else { return }

        let fallbackFPS: Double = {
            if let fps = request.renderFPS, fps.isFinite, fps > 0 { return fps }
            return 24.0
        }()

        do {
            let tex = try await clipReader.texture(
                assetURL: assetURL,
                timeSeconds: timeSeconds,
                width: width,
                height: height,
                fallbackFPS: fallbackFPS
            )
            textureMap[node.id] = tex

            if abs(timeSeconds) < 0.0000005 {
                // Diagnostic: sample a single pixel from the decoded source texture.
                // Only do this for 8-bit formats (float formats require different packing).
                if tex.pixelFormat == .bgra8Unorm || tex.pixelFormat == .rgba8Unorm {
                    let px = max(0, min(tex.width - 1, tex.width / 2))
                    let py = max(0, min(tex.height - 1, tex.height / 2))
                    var pixel = [UInt8](repeating: 0, count: 4)
                    tex.getBytes(
                        &pixel,
                        bytesPerRow: 4,
                        from: MTLRegionMake2D(px, py, 1, 1),
                        mipmapLevel: 0
                    )
                    logDebug("🧪 sourceTex t=0 \(assetURL.lastPathComponent) fmt=\(tex.pixelFormat) size=\(tex.width)x\(tex.height) sample(\(px),\(py)) bytes=\(pixel)")
                } else {
                    logDebug("🧪 sourceTex t=0 \(assetURL.lastPathComponent) fmt=\(tex.pixelFormat) size=\(tex.width)x\(tex.height) (skip 8-bit sample)")
                }
            }

            // Opportunistic lookahead (use render cadence when available).
            let step = 1.0 / fallbackFPS
            clipReader.prefetch(
                assetURL: assetURL,
                timeSeconds: timeSeconds + (step.isFinite && step > 0 ? step : (1.0 / 24.0)),
                width: width,
                height: height,
                fallbackFPS: fallbackFPS
            )
        } catch {
            let msg = "source_texture decode failed for \(assetURL.lastPathComponent) @ \(String(format: "%.3f", timeSeconds))s: \(error)"
            renderWarnings.append(msg)
            logDebug("❌ \(msg)")
            // If decode fails, keep a deterministic black input.
            let blackDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
            blackDesc.usage = [.shaderRead]
            blackDesc.storageMode = .shared
            if let black = device.makeTexture(descriptor: blackDesc) {
                textureMap[node.id] = black
            }
        }
    }

    private func preparePersonMaskTexture(
        for node: RenderNode,
        request: RenderRequest,
        width: Int,
        height: Int,
        textureMap: inout [UUID: MTLTexture]
    ) async throws {
        guard let assetIDValue = node.parameters["asset_id"],
              case .string(let assetID) = assetIDValue else {
            return
        }

        let timeSeconds: Double
        if let t = node.parameters["time_seconds"], case .float(let s) = t {
            timeSeconds = s
        } else {
            timeSeconds = request.time.seconds
        }

        let resolved = request.assets[assetID] ?? assetID
        let url: URL?
        if let u = URL(string: resolved), u.scheme != nil {
            url = u
        } else {
            url = URL(fileURLWithPath: resolved)
        }
        guard let assetURL = url else { return }

        let fallbackFPS: Double = {
            if let fps = request.renderFPS, fps.isFinite, fps > 0 { return fps }
            return 24.0
        }()

        let kind: MaskDevice.Kind = {
            if let v = node.parameters["kind"], case .string(let s) = v {
                if s.lowercased() == "person" { return .person }
            }
            return .foreground
        }()

        do {
            let framePB = try await clipReader.pixelBuffer(
                assetURL: assetURL,
                timeSeconds: timeSeconds,
                width: width,
                height: height,
                fallbackFPS: fallbackFPS
            )
            let maskPB = try await maskDevice.generateMask(in: framePB, kind: kind)

            if let cache = maskTextureCache {
                var cvMetalTexture: CVMetalTexture?
                let createResult = CVMetalTextureCacheCreateTextureFromImage(
                    kCFAllocatorDefault,
                    cache,
                    maskPB,
                    nil,
                    .r8Unorm,
                    width,
                    height,
                    0,
                    &cvMetalTexture
                )

                if createResult == kCVReturnSuccess,
                   let cvTex = cvMetalTexture,
                   let tex = CVMetalTextureGetTexture(cvTex) {
                    textureMap[node.id] = tex
                    return
                }
            }

            // Fallback: manual upload to an r8Unorm texture.
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: width, height: height, mipmapped: false)
            desc.usage = [.shaderRead]
            desc.storageMode = .shared
            guard let tex = device.makeTexture(descriptor: desc) else {
                throw RuntimeError("Failed to allocate mask texture")
            }

            CVPixelBufferLockBaseAddress(maskPB, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(maskPB, .readOnly) }

            guard let base = CVPixelBufferGetBaseAddress(maskPB) else {
                throw RuntimeError("Mask pixel buffer has no baseAddress")
            }
            let bytesPerRow = CVPixelBufferGetBytesPerRow(maskPB)
            tex.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: bytesPerRow
            )
            textureMap[node.id] = tex
        } catch {
            let msg = "source_person_mask failed for \(assetURL.lastPathComponent) @ \(String(format: "%.3f", timeSeconds))s: \(error)"
            renderWarnings.append(msg)
            logDebug("❌ \(msg)")

            // Deterministic black mask.
            let blackDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: width, height: height, mipmapped: false)
            blackDesc.usage = [.shaderRead]
            blackDesc.storageMode = .shared
            if let black = device.makeTexture(descriptor: blackDesc) {
                textureMap[node.id] = black
            }
        }
    }
    
    private func encodeNode(
        _ node: RenderNode,
        commandBuffer: MTLCommandBuffer,
        textureMap: inout [UUID: MTLTexture],
        width: Int,
        height: Int,
        edgePolicy: RenderRequest.EdgeCompatibilityPolicy,
        outputConsumerCount: Int,
        allowNonFloatTerminalOutputs: Bool,
        reusableByKey: inout [TexturePool.Key: [MTLTexture]],
        retainForFrame: (MTLTexture) -> Void,
        input0Override: MTLTexture? = nil,
        input1Override: MTLTexture? = nil
    ) throws {
        // Hardware/API replacement: clear nodes should not exist as compute shaders.
        // Use render-pass loadAction clears so we stay tile-friendly on TBDR GPUs.
        if node.shader == "clear_color" {
            // Allocate a render-target-capable color texture.
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
            desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
            desc.storageMode = .private
            guard let destTex = device.makeTexture(descriptor: desc) else {
                throw RuntimeError("Failed to allocate clear render target")
            }
            retainForFrame(destTex)

            let rp = MTLRenderPassDescriptor()
            rp.colorAttachments[0].texture = destTex
            rp.colorAttachments[0].loadAction = .clear
            rp.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            rp.colorAttachments[0].storeAction = .store

            guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: rp) else {
                throw RuntimeError("Failed to create render encoder for clear")
            }
            enc.endEncoding()
            textureMap[node.id] = destTex
            return
        }

        // Hardware/API replacement: depth_one should be a depthAttachment clear.
        if node.shader == "depth_one" {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: width, height: height, mipmapped: false)
            desc.usage = [.shaderRead, .renderTarget]
            desc.storageMode = .private
            guard let depthTex = device.makeTexture(descriptor: desc) else {
                throw RuntimeError("Failed to allocate depth render target")
            }
            retainForFrame(depthTex)

            let rp = MTLRenderPassDescriptor()
            rp.depthAttachment.texture = depthTex
            rp.depthAttachment.loadAction = .clear
            rp.depthAttachment.clearDepth = 1.0
            rp.depthAttachment.storeAction = .store

            guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: rp) else {
                throw RuntimeError("Failed to create render encoder for depth clear")
            }
            enc.endEncoding()
            textureMap[node.id] = depthTex
            return
        }

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
                 if let destTex = texturePool.checkout(width: 256, height: 256, pixelFormat: .rgba16Float, usage: [.shaderRead, .shaderWrite]) {
                     retainForFrame(destTex)
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

        func isAdapterShader(_ shader: String) -> Bool {
            shader == "resize_bilinear_rgba16f" || shader == "resize_bicubic_rgba16f"
        }

        func shouldSkipAutoResize(inputKey: String) -> Bool {
            // Masks are sampled in normalized coordinates in current shaders and do not require
            // identical pixel dimensions.
            inputKey == "mask" || inputKey == "faceMask"
        }

        func resizeToNodeSizeRGBA16F(_ source: MTLTexture, kernelName: String) throws -> MTLTexture {
            guard let resizePSO = try ensurePipelineState(name: kernelName) else {
                throw RuntimeError("Missing PSO: \(kernelName)")
            }

            let usage: MTLTextureUsage = [.shaderRead, .shaderWrite]
            guard let dest = texturePool.checkout(width: width, height: height, pixelFormat: .rgba16Float, usage: usage) else {
                throw RuntimeError("Failed to allocate resize dest texture (\(width)x\(height))")
            }
            retainForFrame(dest)

            guard let enc = commandBuffer.makeComputeCommandEncoder() else {
                throw RuntimeError("Failed to create resize command encoder")
            }
            enc.setComputePipelineState(resizePSO)
            enc.setTexture(source, index: 0)
            enc.setTexture(dest, index: 1)

            let w = resizePSO.threadExecutionWidth
            let h = max(1, resizePSO.maxTotalThreadsPerThreadgroup / w)
            let threadsPerGroup = MTLSizeMake(w, h, 1)
            let threadsPerGrid = MTLSizeMake(dest.width, dest.height, 1)
            enc.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
            enc.endEncoding()

            return dest
        }

        func adaptInputIfNeeded(_ tex: MTLTexture, inputKey: String) throws -> MTLTexture {
            guard tex.width != width || tex.height != height else { return tex }
            guard !isAdapterShader(node.shader) else { return tex }
            guard !shouldSkipAutoResize(inputKey: inputKey) else { return tex }

            switch edgePolicy {
            case .requireExplicitAdapters:
                renderWarnings.append(
                    "size_mismatch node=\(node.shader) input=\(inputKey) inputSize=\(tex.width)x\(tex.height) nodeSize=\(width)x\(height) (insert resize_bilinear_rgba16f)"
                )
                return tex
            case .autoResizeBilinear:
                renderWarnings.append(
                    "auto_resize node=\(node.shader) input=\(inputKey) \(tex.width)x\(tex.height)->\(width)x\(height)"
                )
                return try resizeToNodeSizeRGBA16F(tex, kernelName: "resize_bilinear_rgba16f")
            case .autoResizeBicubic:
                renderWarnings.append(
                    "auto_resize_bicubic node=\(node.shader) input=\(inputKey) \(tex.width)x\(tex.height)->\(width)x\(height)"
                )
                return try resizeToNodeSizeRGBA16F(tex, kernelName: "resize_bicubic_rgba16f")
            }
        }

        struct PendingBinding {
            var index: Int
            var key: String
            var texture: MTLTexture
        }

        var pendingBindings: [PendingBinding] = []
        pendingBindings.reserveCapacity(max(1, node.inputs.count))

        // A. Gather Inputs
        // Convention: Texture Index 0 is Source, unless shader requires multiple inputs.
        if node.shader == "compositor_crossfade" || node.shader == "compositor_dip" || node.shader == "compositor_wipe" {
            if let aID = node.inputs["clipA"], let aTex = textureMap[aID] {
                pendingBindings.append(PendingBinding(index: 0, key: "clipA", texture: aTex))
            }
            if let bID = node.inputs["clipB"], let bTex = textureMap[bID] {
                pendingBindings.append(PendingBinding(index: 1, key: "clipB", texture: bTex))
            }
        } else if node.shader == "compositor_alpha_blend" {
            if let layer1ID = node.inputs["layer1"], let layer1Tex = textureMap[layer1ID] {
                pendingBindings.append(PendingBinding(index: 0, key: "layer1", texture: layer1Tex))
            }
            if let layer2ID = node.inputs["layer2"], let layer2Tex = textureMap[layer2ID] {
                pendingBindings.append(PendingBinding(index: 1, key: "layer2", texture: layer2Tex))
            }
        } else if node.shader == "fx_volumetric_nebula" {
            // VolumetricNebula.metal expects depthTexture at texture(0)
            if let depthID = node.inputs["depth"], let depthTex = textureMap[depthID] {
                pendingBindings.append(PendingBinding(index: 0, key: "depth", texture: depthTex))
            }
        } else if node.shader == "fx_volumetric_composite" {
            // VolumetricNebula.metal composite expects scene at texture(0) and volumetric at texture(1)
            if let sceneID = node.inputs["scene"], let sceneTex = textureMap[sceneID] {
                pendingBindings.append(PendingBinding(index: 0, key: "scene", texture: sceneTex))
            }
            if let volID = node.inputs["volumetric"], let volTex = textureMap[volID] {
                pendingBindings.append(PendingBinding(index: 1, key: "volumetric", texture: volTex))
            }
        } else if node.shader == "source_texture" || node.shader == "source_person_mask" {
            // Video source nodes: we preloaded the source texture into textureMap[node.id] before encoding.
            if let src = textureMap[node.id] {
                pendingBindings.append(PendingBinding(index: 0, key: "source", texture: src))
            }
        } else if node.shader == "fx_masked_blur" {
            // MaskedBlur.metal signature (Updated for Dual Input):
            //   sharpTexture  [[texture(0)]]
            //   blurryTexture [[texture(1)]]
            //   maskTexture   [[texture(2)]]
            //   outputTexture [[texture(3)]]
            
            // 0: Sharp Source
            // Legacy/Benchmark fallback: if input0Override present (from legacy path), use it.
            // But normally input0 should be the CLEAN source.
            if let inputID = (node.inputs["input"] ?? node.inputs["source"]), let inputTex = textureMap[inputID] {
                 let tex = input0Override ?? inputTex
                 pendingBindings.append(PendingBinding(index: 0, key: "input", texture: tex))
            }

            // 1: Blurry Source (Mipmapped)
            if let override = input1Override {
                // Priority: Use the generated mip chain.
                pendingBindings.append(PendingBinding(index: 1, key: "blur_base_override", texture: override))
            } else if let blurID = node.inputs["blur_base"], let blurTex = textureMap[blurID] {
                // If no mip override (maybe generateMips failed?), try the explicit 'blur_base' input.
                pendingBindings.append(PendingBinding(index: 1, key: "blur_base", texture: blurTex))
            } else {
                 // Fallback: If no blur_base provided (legacy mode), we reused input0Override as the 'blurry' Texture?
                 // But wait, the kernel expects TWO textures.
                 // If we are in legacy mode, we might need to bind 'input' as 'blurry' too?
                 // This is dirty but keeps the benchmark from hanging the GPU.
                 if let inputID = (node.inputs["input"] ?? node.inputs["source"]), let inputTex = textureMap[inputID] {
                     let tex = input0Override ?? inputTex
                     pendingBindings.append(PendingBinding(index: 1, key: "input_as_blur", texture: tex))
                 }
            }

            // 2: Mask
            if let maskID = node.inputs["mask"], let maskTex = textureMap[maskID] {
                pendingBindings.append(PendingBinding(index: 2, key: "mask", texture: maskTex))
            }
        } else if node.shader == "fx_mip_blur" {
            // Blur.metal signature:
            //   sourceTexture [[texture(0)]] (mipmapped)
            //   destTexture   [[texture(1)]]
            if let override = input0Override {
                pendingBindings.append(PendingBinding(index: 0, key: "input", texture: override))
            } else if let inputID = (node.inputs["input"] ?? node.inputs["source"]), let inputTex = textureMap[inputID] {
                let fullLevels = max(1, Int(floor(log2(Double(max(1, max(inputTex.width, inputTex.height))))) + 1))
                let radius: Float = {
                    if let v = node.parameters["radius"], case .float(let r) = v { return Float(r) }
                    return 0
                }()
                let desiredMaxLod = max(0.0, log2(max(radius, 1.0)))
                let neededLevels = min(fullLevels, max(1, Int(ceil(Double(desiredMaxLod))) + 2))

                if let mip = makeMipmappedCopy(source: inputTex, commandBuffer: commandBuffer, mipLevelCount: neededLevels) {
                    retainForFrame(mip)
                    pendingBindings.append(PendingBinding(index: 0, key: "input", texture: mip))
                } else {
                    pendingBindings.append(PendingBinding(index: 0, key: "input", texture: inputTex))
                }
            }
        } else if let inputID = (node.inputs["input"] ?? node.inputs["source"]) {
            if let inputTex = textureMap[inputID] {
                pendingBindings.append(PendingBinding(index: 0, key: "input", texture: inputTex))
            } else {
                // If a node expects an input but upstream isn't present, bind a deterministic black texture
                // so downstream nodes can still execute (tests use this for 1-node graphs).
                let blackDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
                blackDesc.usage = [.shaderRead, .shaderWrite]
                if let black = device.makeTexture(descriptor: blackDesc) {
                    pendingBindings.append(PendingBinding(index: 0, key: "input_missing", texture: black))
                }
            }
        } else if node.shader == "source_linear_ramp" || node.shader == "source_test_color" {
            // Source Node: No input texture needed.
        }

        // Bind any additional named inputs (e.g. masks) for multi-input features.
        // Convention: primary input uses texture(0) and output uses texture(1) for most kernels.
        // We bind extra inputs starting at texture(2), in a stable order.
        do {
            let extraStartIndex: Int = (node.shader == "compositor_crossfade" || node.shader == "compositor_dip" || node.shader == "compositor_wipe" || node.shader == "compositor_alpha_blend") ? 3 : 2

            var extraKeys = Array(node.inputs.keys)
            extraKeys.removeAll(where: { $0 == "input" || $0 == "source" || (node.shader == "fx_masked_blur" && ($0 == "mask" || $0 == "blur_base")) })

            func priority(_ k: String) -> (Int, String) {
                if k == "mask" || k == "faceMask" { return (0, k) }
                return (1, k)
            }
            extraKeys.sort { priority($0) < priority($1) }

            var texIndex = extraStartIndex
            for key in extraKeys {
                guard let inputID = node.inputs[key], let tex = textureMap[inputID] else { continue }
                pendingBindings.append(PendingBinding(index: texIndex, key: key, texture: tex))
                texIndex += 1
            }
        }

        // Apply edge policy (resize inputs if required) BEFORE opening the main encoder.
        if edgePolicy != .requireExplicitAdapters || !pendingBindings.isEmpty {
            for i in pendingBindings.indices {
                pendingBindings[i].texture = try adaptInputIfNeeded(pendingBindings[i].texture, inputKey: pendingBindings[i].key)
            }
        }
        
        // B. Bind Outputs
        let outputUsage: MTLTextureUsage = (node.shader == "compositor_crossfade") ? [.renderTarget, .shaderRead, .shaderWrite] : [.shaderRead, .shaderWrite]

        let requestedOutputPixelFormat: MTLPixelFormat = {
            switch node.resolvedOutputPixelFormat() {
            case .rgba16Float: return .rgba16Float
            case .bgra8Unorm: return .bgra8Unorm
            case .rgba8Unorm: return .rgba8Unorm
            case .r8Unorm: return .r8Unorm
            case .depth32Float: return .depth32Float
            }
        }()

        // Today most kernels are authored against `texture2d<float, ...>` and the working pipeline
        // expects float intermediates. Non-float outputs are only safe for terminal nodes (no
        // downstream consumers), and only for formats we explicitly support today.
        let outputPixelFormat: MTLPixelFormat = {
            if requestedOutputPixelFormat == .rgba16Float { return .rgba16Float }

            let isTerminal = outputConsumerCount <= 0
            let isSupportedNonFloat = (requestedOutputPixelFormat == .bgra8Unorm || requestedOutputPixelFormat == .rgba8Unorm)

            if allowNonFloatTerminalOutputs && isTerminal && isSupportedNonFloat {
                return requestedOutputPixelFormat
            }

            renderWarnings.append(
                "output_format_override node=\(node.shader) requested=\(requestedOutputPixelFormat) using=rgba16Float"
            )
            return .rgba16Float
        }()

        let outputKey = TexturePool.Key(
            width: width,
            height: height,
            pixelFormat: outputPixelFormat,
            mipLevelCount: 1,
            usageRaw: UInt64(outputUsage.rawValue),
            storageModeRaw: UInt64(MTLStorageMode.private.rawValue)
        )
        let destTex: MTLTexture
        if var bucket = reusableByKey[outputKey], let reused = bucket.popLast() {
            reusableByKey[outputKey] = bucket
            destTex = reused
        } else {
            guard let fresh = texturePool.checkout(width: width, height: height, pixelFormat: outputPixelFormat, usage: outputUsage) else {
                logDebug("❌ Texture allocation failed (w=\(width) h=\(height)) for node \(node.name) [\(node.shader)]")
                return
            }
            destTex = fresh
        }
        retainForFrame(destTex)
        textureMap[node.id] = destTex

        // Special-case: Crossfade via render pipeline blending (mandated perf architecture).
        if node.shader == "compositor_crossfade" {
            let t: Float = {
                if let val = node.parameters["mix"], case .float(let v) = val { return Float(v) }
                return 0
            }()
            let tt = max(0.0, min(1.0, t))

            // Resolve inputs (post-adaptation).
            let clipA = pendingBindings.first(where: { $0.index == 0 })?.texture
            let clipB = pendingBindings.first(where: { $0.index == 1 })?.texture

            // If either side is missing, degrade deterministically.
            let aTex: MTLTexture
            let bTex: MTLTexture
            if let a = clipA, let b = clipB {
                aTex = a
                bTex = b
            } else if let a = clipA {
                aTex = a
                bTex = a
            } else if let b = clipB {
                aTex = b
                bTex = b
            } else {
                return
            }

                if let copyPSO = try ensureCrossfadeRenderPipeline(pixelFormat: destTex.pixelFormat, blendingEnabled: false),
                    let blendPSO = try ensureCrossfadeRenderPipeline(pixelFormat: destTex.pixelFormat, blendingEnabled: true) {
                    let rp = MTLRenderPassDescriptor()
                    rp.colorAttachments[0].texture = destTex
                    rp.colorAttachments[0].loadAction = .dontCare
                    rp.colorAttachments[0].storeAction = .store

                    if let re = commandBuffer.makeRenderCommandEncoder(descriptor: rp) {
                        re.setRenderPipelineState(copyPSO)
                        re.setFragmentTexture(aTex, index: 0)
                        re.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

                        re.setRenderPipelineState(blendPSO)
                        re.setBlendColor(red: tt, green: tt, blue: tt, alpha: tt)
                        re.setFragmentTexture(bTex, index: 0)
                        re.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

                        re.endEncoding()
                        return
                    }
            }
        }

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pso)

        for b in pendingBindings {
            encoder.setTexture(b.texture, index: b.index)
        }

        let outputTextureIndex: Int
        if node.shader == "fx_generate_face_mask" {
            // FaceMaskGenerator.metal uses output texture(0).
            outputTextureIndex = 0
        } else if node.shader == "fx_masked_blur" {
            // MaskedBlur.metal writes to output texture(3).
            outputTextureIndex = 3
        } else if node.shader == "fx_mip_blur" {
            // Blur.metal fx_mip_blur writes to output texture(1).
            outputTextureIndex = 1
        } else if node.shader == "fx_volumetric_composite" {
            // VolumetricNebula.metal composite uses output texture(2).
            outputTextureIndex = 2
        } else if node.shader == "compositor_crossfade" || node.shader == "compositor_dip" || node.shader == "compositor_wipe" || node.shader == "compositor_alpha_blend" {
            // Compositor kernels use output texture(2)
            outputTextureIndex = 2
        } else {
            // Most kernels use output texture(1)
            outputTextureIndex = 1
        }
        encoder.setTexture(destTex, index: outputTextureIndex)
        
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
        } else if node.shader == "compositor_dip" {
            bindFloat("progress", 0)
            bindVector3("dipColor", 1)
        } else if node.shader == "compositor_wipe" {
            bindFloat("progress", 0)
            bindFloat("direction", 1)
        } else if node.shader == "compositor_alpha_blend" {
            bindFloat("alpha1", 0)
            bindFloat("alpha2", 1)
        } else if node.shader == "fx_zone_plate" {
            bindFloat("time", 0)
        } else if node.shader == "fx_starfield" {
            bindFloat("time", 0)
        } else if node.shader == "fx_blur_h" || node.shader == "fx_blur_v" {
            bindFloat("radius", 0)
        } else if node.shader == "fx_masked_blur" {
            // MaskedBlur.metal:
            //   blurRadius [[buffer(0)]]
            //   maskThreshold [[buffer(1)]]
            bindFloat("radius", 0)
            bindFloat("threshold", 1)
        } else if node.shader == "fx_tonemap_aces" {
            // ToneMapping.metal: constant float &exposure [[buffer(0)]]
            bindFloat("exposure", 0)
        } else if node.shader == "fx_tonemap_pq" {
            // ToneMapping.metal: constant float &maxNits [[buffer(0)]]
            bindFloat("maxNits", 0)
        } else if node.shader == "odt_acescg_to_pq1000_tuned" {
            // ToneMapping.metal: tuned HDR ODT
            //   maxNits [[buffer(0)]]
            //   pqScale [[buffer(1)]]
            //   highlightDesat [[buffer(2)]]
            //   kneeNits [[buffer(3)]]
            //   gamutCompress [[buffer(4)]]
            bindFloat("maxNits", 0)
            bindFloat("pqScale", 1)
            bindFloat("highlightDesat", 2)
            bindFloat("kneeNits", 3)
            bindFloat("gamutCompress", 4)
        } else if node.shader == "odt_acescg_to_rec709_studio_tuned" {
            // ColorSpace.metal: tuned SDR ODT
            //   gamutCompress [[buffer(0)]]
            //   highlightDesatStrength [[buffer(1)]]
            //   redModStrength [[buffer(2)]]
            bindFloat("gamutCompress", 0)
            bindFloat("highlightDesatStrength", 1)
            bindFloat("redModStrength", 2)
        } else if node.shader == "fx_color_grade_simple" {
            // ColorGrading.metal: constant ColorGradeParams &params [[buffer(0)]]
            struct ColorGradeParams {
                var exposure: Float
                var contrast: Float
                var saturation: Float
                var temperature: Float
                var tint: Float
                // Match `float _padding[3]` in Metal.
                var _p0: Float
                var _p1: Float
                var _p2: Float
            }

            func f(_ key: String, default def: Float) -> Float {
                if let val = node.parameters[key], case .float(let v) = val {
                    return Float(v)
                }
                return def
            }

            var params = ColorGradeParams(
                exposure: f("exposure", default: 0),
                contrast: f("contrast", default: 1),
                saturation: f("saturation", default: 1),
                temperature: f("temperature", default: 0),
                tint: f("tint", default: 0),
                _p0: 0,
                _p1: 0,
                _p2: 0
            )
            encoder.setBytes(&params, length: MemoryLayout<ColorGradeParams>.stride, index: 0)
        } else if node.shader == "fx_false_color_turbo" {
            // ColorGrading.metal: constant FalseColorParams &params [[buffer(0)]]
            struct FalseColorParams {
                var exposure: Float
                var gamma: Float
                // Match `float _padding[2]` in Metal.
                var _p0: Float
                var _p1: Float
            }

            func f(_ key: String, default def: Float) -> Float {
                if let val = node.parameters[key], case .float(let v) = val {
                    return Float(v)
                }
                return def
            }

            var params = FalseColorParams(
                exposure: f("exposure", default: 0),
                gamma: f("gamma", default: 1),
                _p0: 0,
                _p1: 0
            )
            encoder.setBytes(&params, length: MemoryLayout<FalseColorParams>.stride, index: 0)
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
            let rects: [Float]
            if let val = node.parameters["faceRects"], case .floatArray(let r) = val {
                rects = r
            } else {
                rects = []
            }

            var count = UInt32(rects.count / 4) // 4 floats per rect
            if rects.isEmpty {
                let dummy: [Float] = [0, 0, 0, 0]
                encoder.setBytes(dummy, length: dummy.count * MemoryLayout<Float>.size, index: 0)
            } else {
                encoder.setBytes(rects, length: rects.count * MemoryLayout<Float>.size, index: 0)
            }
            encoder.setBytes(&count, length: MemoryLayout<UInt32>.size, index: 1)
        } else if node.shader == "fx_beauty_enhance" {
            struct BeautyEnhanceParams {
                var skinSmoothing: Float
                var intensity: Float
                var _p0: Float
                var _p1: Float
            }

            var params = BeautyEnhanceParams(
                skinSmoothing: node.float("skinSmoothing"),
                intensity: node.float("intensity"),
                _p0: 0,
                _p1: 0
            )
            encoder.setBytes(&params, length: MemoryLayout<BeautyEnhanceParams>.stride, index: 0)
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
            
        } else if node.shader == "lut_apply_3d" || node.shader == "lut_apply_3d_rgba16f" {
            // Handle LUT Parameter (expects 'lut' as .data)
            if let val = node.parameters["lut"], case .data(let lutData) = val {
                let lutKey = fnv1a64(lutData)
                // Check Cache
                var lutTex = lutCache[lutKey]
                if lutTex == nil {
                    // Parse and Create
                    if let (size, payload) = LUTHelper.parseCube(data: lutData) {
                        let desc = MTLTextureDescriptor()
                        desc.textureType = .type3D
                        // Use 16-bit float to reduce bandwidth/memory. Shader samples as float4.
                        desc.pixelFormat = .rgba16Float

                        // Convert [Float] (RGB) to [Float16] (RGBA), padding alpha=1.
                        var rgba16: [Float16] = []
                        rgba16.reserveCapacity(size * size * size * 4)
                        for i in 0..<(payload.count / 3) {
                            rgba16.append(Float16(payload[i * 3]))
                            rgba16.append(Float16(payload[i * 3 + 1]))
                            rgba16.append(Float16(payload[i * 3 + 2]))
                            rgba16.append(Float16(1.0))
                        }
                        
                        desc.width = size
                        desc.height = size
                        desc.depth = size
                        
                        if let tex = device.makeTexture(descriptor: desc) {
                            // Upload
                            // Bytes per row = size * 8 (4 half floats * 2 bytes)
                            let bytesPerRow = size * 8
                            let bytesPerImage = size * bytesPerRow // one Z slice

                            // For 3D textures on Metal, write each depth slice by varying region.origin.z.
                            rgba16.withUnsafeBytes { raw in
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

                            lutCache[lutKey] = tex
                            lutTex = tex
                        }
                    }
                }
                
                // Bind
                if let t = lutTex {
                    encoder.setTexture(t, index: 2)
                }
            }
        } else if node.shader == "fx_volumetric_nebula" {
            // VolumetricNebula.metal: constant VolumetricNebulaParams &params [[buffer(0)]]
            // plus gradient stops [[buffer(1)]] and gradientCount [[buffer(2)]].
            struct VolumetricNebulaParams {
                var cameraPosition: SIMD3<Float>
                var _pad0: Float
                var cameraForward: SIMD3<Float>
                var _pad1: Float
                var cameraUp: SIMD3<Float>
                var _pad2: Float
                var cameraRight: SIMD3<Float>
                var _pad3: Float
                var fov: Float
                var aspectRatio: Float
                var _pad4: SIMD2<Float>

                var volumeMin: SIMD3<Float>
                var _pad5: Float
                var volumeMax: SIMD3<Float>
                var _pad6: Float

                var baseFrequency: Float
                var octaves: Int32
                var lacunarity: Float
                var gain: Float
                var densityScale: Float
                var densityOffset: Float
                var _pad7: SIMD2<Float>

                var time: Float
                var _pad8: SIMD3<Float>
                var windVelocity: SIMD3<Float>
                var _pad9: Float

                var lightDirection: SIMD3<Float>
                var _pad10: Float
                var lightColor: SIMD3<Float>
                var ambientIntensity: Float

                var scatteringCoeff: Float
                var absorptionCoeff: Float
                var phaseG: Float
                var _pad11: Float

                var maxSteps: Int32
                var shadowSteps: Int32
                var stepSize: Float
                var _pad12: Float

                var emissionColorWarm: SIMD3<Float>
                var _pad13: Float
                var emissionColorCool: SIMD3<Float>
                var _pad14: Float
                var emissionIntensity: Float
                var hdrScale: Float
                var debugMode: Float
                var _pad15: SIMD2<Float>
            }

            struct GradientStop3D {
                var color: SIMD3<Float>
                var position: Float
            }

            var params = VolumetricNebulaParams(
                cameraPosition: node.vector3("cameraPosition"),
                _pad0: 0,
                cameraForward: node.vector3("cameraForward"),
                _pad1: 0,
                cameraUp: node.vector3("cameraUp"),
                _pad2: 0,
                cameraRight: node.vector3("cameraRight"),
                _pad3: 0,
                fov: node.float("fov"),
                aspectRatio: node.float("aspectRatio"),
                _pad4: .zero,

                volumeMin: node.vector3("volumeMin"),
                _pad5: 0,
                volumeMax: node.vector3("volumeMax"),
                _pad6: 0,

                baseFrequency: node.float("baseFrequency"),
                octaves: Int32(node.float("octaves")),
                lacunarity: node.float("lacunarity"),
                gain: node.float("gain"),
                densityScale: node.float("densityScale"),
                densityOffset: node.float("densityOffset"),
                _pad7: .zero,

                time: node.float("time"),
                _pad8: .zero,
                windVelocity: node.vector3("windVelocity"),
                _pad9: 0,

                lightDirection: node.vector3("lightDirection"),
                _pad10: 0,
                lightColor: node.vector3("lightColor"),
                ambientIntensity: node.float("ambientIntensity"),

                scatteringCoeff: node.float("scatteringCoeff"),
                absorptionCoeff: node.float("absorptionCoeff"),
                phaseG: node.float("phaseG"),
                _pad11: 0,

                maxSteps: Int32(node.float("maxSteps")),
                shadowSteps: Int32(node.float("shadowSteps")),
                stepSize: node.float("stepSize"),
                _pad12: 0,

                emissionColorWarm: node.vector3("emissionColorWarm"),
                _pad13: 0,
                emissionColorCool: node.vector3("emissionColorCool"),
                _pad14: 0,
                emissionIntensity: node.float("emissionIntensity"),
                hdrScale: node.float("hdrScale"),
                debugMode: node.float("debugMode"),
                _pad15: .zero
            )

            encoder.setBytes(&params, length: MemoryLayout<VolumetricNebulaParams>.stride, index: 0)

            // Provide a small default gradient buffer (even if unused by the kernel today).
            let gradient: [GradientStop3D] = [
                GradientStop3D(color: SIMD3<Float>(0.1, 0.2, 0.8), position: 0.0),
                GradientStop3D(color: SIMD3<Float>(1.0, 0.4, 0.1), position: 1.0)
            ]
            var gradientCount: Int32 = Int32(gradient.count)
            encoder.setBytes(gradient, length: MemoryLayout<GradientStop3D>.stride * gradient.count, index: 1)
            encoder.setBytes(&gradientCount, length: MemoryLayout<Int32>.stride, index: 2)
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
            MetalSimulationDiagnostics.incrementCPUReadback()
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
            MetalSimulationDiagnostics.incrementCPUReadback()
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
