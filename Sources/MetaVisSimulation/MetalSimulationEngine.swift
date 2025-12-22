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
    private var lutCache: [UUID: MTLTexture] = [:] // Cache 3D LUTs per node
    private var waveformBuffer: MTLBuffer?
    private let clipReader: ClipReader
    private let texturePool: TexturePool
    private var isConfigured: Bool = false

    private let maskDevice: MaskDevice
    private let maskTextureCache: CVMetalTextureCache?

    private var renderWarnings: [String] = []

    public enum EngineMode: Sendable, Equatable {
        case development
        case production
    }

    private let mode: EngineMode

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
                          "ClearColor",        // Solid fills (empty timeline fallback)
                    "ColorSpace",         // IDT/ODT transforms
                          "ACES",               // Shared ACES helpers (ToneMapping/Grading)
                      "Procedural",         // Shared procedural helpers (volumetric nebula)
                    "Noise",              // Shared noise helpers (used by blur/bokeh)
                    "FaceEnhance",        // fx_face_enhance / fx_beauty_enhance
                      "FaceMaskGenerator",  // fx_generate_face_mask
                                        "MaskSources",        // source_person_mask
                                        "MaskedColorGrade",   // fx_masked_grade
                    "FormatConversion",   // RGBA→BGRA swizzle
                    "Compositor",         // Multi-clip alpha blending
                    "Blur",               // fx_blur_h / fx_blur_v
                          "ToneMapping",        // fx_tonemap_aces / fx_tonemap_pq
                          "ColorGrading",       // fx_color_grade_simple / fx_apply_lut
                    "Macbeth",            // Procedural color chart
                    "SMPTE",              // Procedural bars
                    "ZonePlate",          // Procedural zone plate
                      "DepthOne",           // Deterministic depth=1 generator (nebula debug)
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
            || lib.makeFunction(name: "clear_color") == nil
            || lib.makeFunction(name: "fx_beauty_enhance") == nil
            || lib.makeFunction(name: "fx_face_enhance") == nil
            || lib.makeFunction(name: "fx_generate_face_mask") == nil
            || lib.makeFunction(name: "fx_masked_grade") == nil
            || lib.makeFunction(name: "source_person_mask") == nil
            || lib.makeFunction(name: "fx_volumetric_nebula") == nil
            || lib.makeFunction(name: "fx_volumetric_composite") == nil) {
            if mode == .production {
                throw RuntimeError("Bundled Metal library is missing required kernels")
            }
            logDebug("⚠️ Bundled library missing required kernels; recompiling from bundle sources")
            self.library = try await compileLibraryFromBundledMetalSources(files: [
                "ClearColor",
                "ColorSpace",
                "ACES",
                "Procedural",
                "Noise",
                "FaceEnhance",
                "FaceMaskGenerator",
                "MaskSources",
                "MaskedColorGrade",
                "FormatConversion",
                "Compositor",
                "Blur",
                "ToneMapping",
                "ColorGrading",
                "Macbeth",
                "SMPTE",
                "ZonePlate",
                "DepthOne",
                "StarField",
                "VolumetricNebula",
                "Watermark"
            ], bundle: GraphicsBundleHelper.bundle)
        }
        
        if self.library == nil {
            logDebug("⚠️ Metal Library not found! Shaders will fail.")
        }
        
        // Pre-warm Pipelines for Core Shaders
        try await cachePipeline(name: "clear_color")
        try await cachePipeline(name: "idt_rec709_to_acescg")
        try await cachePipeline(name: "odt_acescg_to_rec709")
        try await cachePipeline(name: "fx_generate_face_mask") // Vision Mask Gen parameters
        try await cachePipeline(name: "fx_masked_grade")
        try await cachePipeline(name: "source_person_mask")
        
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
        try await cachePipeline(name: "depth_one")
        try await cachePipeline(name: "fx_starfield")
        try await cachePipeline(name: "fx_volumetric_nebula")
        try await cachePipeline(name: "fx_volumetric_composite")

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
        renderWarnings.removeAll(keepingCapacity: true)

        guard let tex = try await internalRender(request: request) else {
            return RenderResult(imageBuffer: nil, metadata: ["error": "Root node texture missing"])
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
    
    /// Renders directly into a CVPixelBuffer (for export).
    public func render(request: RenderRequest, to cvPixelBuffer: CVPixelBuffer, watermark: WatermarkSpec? = nil) async throws {
        let dstW = CVPixelBufferGetWidth(cvPixelBuffer)
        let dstH = CVPixelBufferGetHeight(cvPixelBuffer)

        guard let rootTex = try await internalRender(request: request, overrideWidth: dstW, overrideHeight: dstH) else {
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
        var textureCache: CVMetalTextureCache?
        let result = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        guard result == kCVReturnSuccess, let cache = textureCache else {
             throw RuntimeError("Failed to create Texture Cache")
        }
        
        // 2. Wrap CVPixelBuffer in Metal Texture
        let width = dstW
        let height = dstH
        let pixelFormat = CVPixelBufferGetPixelFormatType(cvPixelBuffer)

        let metalPixelFormat: MTLPixelFormat
        switch pixelFormat {
        case kCVPixelFormatType_64RGBAHalf:
            metalPixelFormat = .rgba16Float
        case kCVPixelFormatType_32BGRA:
            metalPixelFormat = .bgra8Unorm
        default:
            throw RuntimeError("Unsupported CVPixelBuffer pixel format: \(pixelFormat)")
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

        // 3. Encode into pixel buffer
        // Use compute kernels instead of blit.copy() since CVMetalTexture-backed textures
        // may not advertise blit usage and can yield black/undefined results.
        guard let buffer = commandQueue.makeCommandBuffer() else { return }
        if pixelFormat == kCVPixelFormatType_64RGBAHalf {
            guard let pso = try ensurePipelineState(name: "source_texture") else {
                throw RuntimeError("Copy shader not available")
            }
            guard let encoder = buffer.makeComputeCommandEncoder() else { return }
            encoder.setComputePipelineState(pso)
            encoder.setTexture(rootTex, index: 0)
            encoder.setTexture(mtlTex, index: 1)

            let tw = pso.threadExecutionWidth
            let th = max(1, pso.maxTotalThreadsPerThreadgroup / tw)
            encoder.dispatchThreads(
                MTLSize(width: width, height: height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: tw, height: th, depth: 1)
            )
            encoder.endEncoding()
        } else if pixelFormat == kCVPixelFormatType_32BGRA {
            guard let pso = try ensurePipelineState(name: "rgba_to_bgra") else {
                throw RuntimeError("Format conversion shader not available")
            }
            guard let encoder = buffer.makeComputeCommandEncoder() else { return }
            encoder.setComputePipelineState(pso)
            encoder.setTexture(rootTex, index: 0)
            encoder.setTexture(mtlTex, index: 1)

            let tw = pso.threadExecutionWidth
            let th = max(1, pso.maxTotalThreadsPerThreadgroup / tw)
            encoder.dispatchThreads(
                MTLSize(width: width, height: height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: tw, height: th, depth: 1)
            )
            encoder.endEncoding()
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
        overrideHeight: Int? = nil
    ) async throws -> MTLTexture? {
        if !isConfigured {
            try await configure()
        }

        renderWarnings.removeAll(keepingCapacity: true)

        guard let buffer = commandQueue.makeCommandBuffer() else {
            throw RuntimeError("CommandBuffer failed")
        }
        
        var textureMap: [UUID: MTLTexture] = [:]

        // Track how many downstream consumers each node output has so we can reuse
        // intermediate textures within a single frame and avoid GPU OOM.
        var remainingUses: [UUID: Int] = [:]
        remainingUses.reserveCapacity(request.graph.nodes.count)
        for node in request.graph.nodes {
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
        
        for node in request.graph.nodes {
            if node.shader == "source_texture" {
                try await prepareSourceTexture(for: node, request: request, width: width, height: height, textureMap: &textureMap)
            }
            if node.shader == "source_person_mask" {
                try await preparePersonMaskTexture(for: node, request: request, width: width, height: height, textureMap: &textureMap)
            }

            try encodeNode(
                node,
                commandBuffer: buffer,
                textureMap: &textureMap,
                width: width,
                height: height,
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
        reusableByKey: inout [TexturePool.Key: [MTLTexture]],
        retainForFrame: (MTLTexture) -> Void
    ) throws {
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
        
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pso)
        
        // A. Bind Inputs
        // Convention: Texture Index 0 is Source, unless shader requires multiple inputs.
        if node.shader == "compositor_crossfade" || node.shader == "compositor_dip" || node.shader == "compositor_wipe" {
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
        } else if node.shader == "fx_volumetric_nebula" {
            // VolumetricNebula.metal expects depthTexture at texture(0)
            if let depthID = node.inputs["depth"], let depthTex = textureMap[depthID] {
                encoder.setTexture(depthTex, index: 0)
            }
        } else if node.shader == "fx_volumetric_composite" {
            // VolumetricNebula.metal composite expects scene at texture(0) and volumetric at texture(1)
            if let sceneID = node.inputs["scene"], let sceneTex = textureMap[sceneID] {
                encoder.setTexture(sceneTex, index: 0)
            }
            if let volID = node.inputs["volumetric"], let volTex = textureMap[volID] {
                encoder.setTexture(volTex, index: 1)
            }
        } else if node.shader == "source_texture" || node.shader == "source_person_mask" {
            // Video source nodes: we preloaded the source texture into textureMap[node.id] before encoding.
            if let src = textureMap[node.id] {
                encoder.setTexture(src, index: 0)
            }
        } else if let inputID = (node.inputs["input"] ?? node.inputs["source"]) {
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
        } else if node.shader == "source_linear_ramp" || node.shader == "source_test_color" {
            // Source Node: No input texture needed.
        }

        // Bind any additional named inputs (e.g. masks) for multi-input features.
        // Convention: primary input uses texture(0) and output uses texture(1) for most kernels.
        // We bind extra inputs starting at texture(2), in a stable order.
        do {
            let extraStartIndex: Int = (node.shader == "compositor_crossfade" || node.shader == "compositor_dip" || node.shader == "compositor_wipe" || node.shader == "compositor_alpha_blend") ? 3 : 2

            var extraKeys = Array(node.inputs.keys)
            extraKeys.removeAll(where: { $0 == "input" || $0 == "source" })

            func priority(_ k: String) -> (Int, String) {
                if k == "mask" || k == "faceMask" { return (0, k) }
                return (1, k)
            }
            extraKeys.sort { priority($0) < priority($1) }

            var texIndex = extraStartIndex
            for key in extraKeys {
                guard let inputID = node.inputs[key], let tex = textureMap[inputID] else { continue }
                encoder.setTexture(tex, index: texIndex)
                texIndex += 1
            }
        }
        
        // Helper to create texture with request resolution
        // Use arguments passed to function
        
        // B. Bind Outputs
        let outputUsage: MTLTextureUsage = [.shaderRead, .shaderWrite]
        let outputKey = TexturePool.Key(
            width: width,
            height: height,
            pixelFormat: .rgba16Float,
            usageRaw: UInt64(outputUsage.rawValue),
            storageModeRaw: UInt64(MTLStorageMode.private.rawValue)
        )
        let destTex: MTLTexture
        if var bucket = reusableByKey[outputKey], let reused = bucket.popLast() {
            reusableByKey[outputKey] = bucket
            destTex = reused
        } else {
            guard let fresh = texturePool.checkout(width: width, height: height, pixelFormat: .rgba16Float, usage: outputUsage) else {
                logDebug("❌ Texture allocation failed (w=\(width) h=\(height)) for node \(node.name) [\(node.shader)]")
                return
            }
            destTex = fresh
        }
        retainForFrame(destTex)
        let outputTextureIndex: Int
        if node.shader == "fx_generate_face_mask" {
            // FaceMaskGenerator.metal uses output texture(0).
            outputTextureIndex = 0
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
        } else if node.shader == "fx_tonemap_aces" {
            // ToneMapping.metal: constant float &exposure [[buffer(0)]]
            bindFloat("exposure", 0)
        } else if node.shader == "fx_tonemap_pq" {
            // ToneMapping.metal: constant float &maxNits [[buffer(0)]]
            bindFloat("maxNits", 0)
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
