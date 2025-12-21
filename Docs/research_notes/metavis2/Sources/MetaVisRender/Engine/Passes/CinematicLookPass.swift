// CinematicLookPass.swift
// MetaVisRender
//
// Created for Sprint 15: Cinematic Effects Pipeline
// Applies unified cinematic look (halation, bloom, grain, vignette, etc.)

import Metal
import MetalPerformanceShaders
import simd

// MARK: - CinematicLookPass

/// Unified pass for applying cinematic post-processing effects.
///
/// This pass applies effects in a physically-correct order:
/// 1. Lens distortion + chromatic aberration (input space)
/// 2. Face enhancement (AI-powered, before other effects)
/// 3. Bloom extraction + blur
/// 4. Halation extraction + blur  
/// 5. Anamorphic streak extraction + blur
/// 6. Composite bloom/halation/anamorphic
/// 7. Light leaks (additive)
/// 8. Diffusion (soft glow)
/// 9. Color grading (LUT)
/// 10. Tone mapping
/// 11. Vignette
/// 12. Film grain (output space)
///
/// All intermediate textures use the TexturePool for memory efficiency.
public class CinematicLookPass: RenderPass {
    public var label: String = "Cinematic Look Pass"
    
    // MARK: - Pipeline States
    
    private var halationThresholdPipeline: MTLComputePipelineState?
    private var halationCompositePipeline: MTLComputePipelineState?
    private var bloomPrefilterPipeline: MTLComputePipelineState?
    private var bloomDownsamplePipeline: MTLComputePipelineState?
    private var bloomUpsamplePipeline: MTLComputePipelineState?
    private var bloomCompositePipeline: MTLComputePipelineState?
    private var anamorphicThresholdPipeline: MTLComputePipelineState?
    private var anamorphicCompositePipeline: MTLComputePipelineState?
    private var lensSystemPipeline: MTLComputePipelineState?
    private var vignettePipeline: MTLComputePipelineState?
    private var filmGrainPipeline: MTLComputePipelineState?
    private var tonemapPipeline: MTLComputePipelineState?
    private var lutPipeline: MTLComputePipelineState?
    private var spectralDispersionPipeline: MTLComputePipelineState?
    private var lightLeakPipeline: MTLComputePipelineState?
    
    /// Face enhancement sub-pass
    private var faceEnhancePass: FaceEnhancePass?
    
    /// Background blur sub-pass
    private var backgroundBlurPass: BackgroundBlurPass?
    
    /// Gaussian blur for halation/diffusion
    private var gaussianBlur: MPSImageGaussianBlur?
    
    /// Box blur for anamorphic streaks (horizontal only)
    private var horizontalBlur: MPSImageBox?
    
    // MARK: - Uniforms
    
    /// Halation composite uniforms (matches shader struct)
    private struct HalationCompositeUniforms {
        var intensity: Float
        var time: Float
        var radialFalloff: Int32
        var _pad3: Float
        var tint: SIMD3<Float>
        var _pad4: Float
    }
    
    /// Film grain uniforms (matches shader struct)
    private struct FilmGrainUniforms {
        var time: Float
        var intensity: Float
        var size: Float
        var shadowBoost: Float
    }
    
    /// Vignette uniforms (matches shader struct)
    private struct VignetteParams {
        var sensorWidth: Float
        var focalLength: Float
        var intensity: Float
        var smoothness: Float
        var roundness: Float
        var padding: Float
    }
    
    /// Lens system uniforms (matches shader struct)
    private struct LensSystemParams {
        var k1: Float
        var k2: Float
        var chromaticAberration: Float
        var padding: Float
    }
    
    /// Bloom composite uniforms
    private struct BloomCompositeUniforms {
        var intensity: Float
        var preservation: Float
    }
    
    /// Anamorphic composite uniforms
    private struct AnamorphicCompositeUniforms {
        var intensity: Float
        var tint: SIMD3<Float>
    }
    
    /// Spectral dispersion uniforms (matches shader struct)
    private struct SpectralDispersionParams {
        var intensity: Float
        var spread: Float
        var center: SIMD2<Float>
        var falloff: Float
        var angle: Float
        var samples: UInt32
        var padding: UInt32
    }
    
    /// Light leak uniforms (matches shader struct)
    private struct LightLeakParams {
        var intensity: Float
        var tint: SIMD3<Float>
        var position: SIMD2<Float>
        var size: Float
        var softness: Float
        var angle: Float
        var animation: Float
        var mode: UInt32
        var padding: UInt32
    }
    
    // MARK: - Configuration
    
    /// Current cinematic look settings
    public var look: CinematicLook = .none
    
    /// Current frame time (for animated effects)
    public var time: Float = 0.0
    
    /// Input texture
    public var inputTexture: MTLTexture?
    
    /// Output texture (if nil, writes back to input)
    public var outputTexture: MTLTexture?
    
    /// Vision provider for AI features (face enhancement)
    public var visionProvider: VisionProvider?
    
    // MARK: - Initialization
    
    public init() {}
    
    public func setup(device: MTLDevice, library: MTLLibrary) throws {
        // Load compute pipelines
        if let fn = library.makeFunction(name: "fx_halation_threshold") {
            halationThresholdPipeline = try device.makeComputePipelineState(function: fn)
        }
        if let fn = library.makeFunction(name: "fx_halation_composite") {
            halationCompositePipeline = try device.makeComputePipelineState(function: fn)
        }
        if let fn = library.makeFunction(name: "fx_bloom_prefilter") {
            bloomPrefilterPipeline = try device.makeComputePipelineState(function: fn)
        }
        if let fn = library.makeFunction(name: "fx_bloom_downsample") {
            bloomDownsamplePipeline = try device.makeComputePipelineState(function: fn)
        }
        if let fn = library.makeFunction(name: "fx_bloom_upsample_blend") {
            bloomUpsamplePipeline = try device.makeComputePipelineState(function: fn)
        }
        if let fn = library.makeFunction(name: "fx_bloom_composite") {
            bloomCompositePipeline = try device.makeComputePipelineState(function: fn)
        }
        if let fn = library.makeFunction(name: "fx_anamorphic_threshold") {
            anamorphicThresholdPipeline = try device.makeComputePipelineState(function: fn)
        }
        if let fn = library.makeFunction(name: "fx_anamorphic_composite") {
            anamorphicCompositePipeline = try device.makeComputePipelineState(function: fn)
        }
        if let fn = library.makeFunction(name: "fx_lens_system") {
            lensSystemPipeline = try device.makeComputePipelineState(function: fn)
        }
        if let fn = library.makeFunction(name: "fx_vignette_physical") {
            vignettePipeline = try device.makeComputePipelineState(function: fn)
        }
        if let fn = library.makeFunction(name: "fx_film_grain") {
            filmGrainPipeline = try device.makeComputePipelineState(function: fn)
        }
        if let fn = library.makeFunction(name: "fx_tonemap_aces") {
            tonemapPipeline = try device.makeComputePipelineState(function: fn)
        }
        if let fn = library.makeFunction(name: "fx_apply_lut") {
            lutPipeline = try device.makeComputePipelineState(function: fn)
        }
        if let fn = library.makeFunction(name: "cs_spectral_dispersion") {
            spectralDispersionPipeline = try device.makeComputePipelineState(function: fn)
        }
        if let fn = library.makeFunction(name: "cs_light_leak") {
            lightLeakPipeline = try device.makeComputePipelineState(function: fn)
        }
        
        // Initialize MPS blur filters
        gaussianBlur = MPSImageGaussianBlur(device: device, sigma: 10.0)
        horizontalBlur = MPSImageBox(device: device, kernelWidth: 31, kernelHeight: 1)
        
        // Initialize face enhancement sub-pass
        faceEnhancePass = FaceEnhancePass()
        try faceEnhancePass?.setup(device: device, library: library)
        
        // Initialize background blur sub-pass
        backgroundBlurPass = BackgroundBlurPass()
        try backgroundBlurPass?.setup(device: device, library: library)
    }
    
    // MARK: - Execute
    
    public func execute(commandBuffer: MTLCommandBuffer, context: RenderContext) throws {
        guard look.enabled, let input = inputTexture else { return }
        
        // If no effects are enabled, skip
        guard hasAnyEffect() else { return }
        
        let output = outputTexture ?? input
        var currentTexture = input
        
        // 1. Lens effects (distortion + CA)
        if let lens = look.lens, (lens.distortion != 0 || lens.chromaticAberration != 0) {
            currentTexture = try applyLens(lens, input: currentTexture, context: context, commandBuffer: commandBuffer)
        }
        
        // 2. Face enhancement (AI-powered, before other effects modify the image)
        if let faceSettings = look.faceEnhance, faceSettings.enabled, let visionProvider = visionProvider {
            if let facePass = faceEnhancePass {
                currentTexture = try facePass.apply(
                    to: currentTexture,
                    settings: faceSettings,
                    visionProvider: visionProvider,
                    context: context,
                    commandBuffer: commandBuffer
                )
            }
        }
        
        // 2b. Background blur (after face enhancement, uses person segmentation)
        if let bgBlurSettings = look.backgroundBlur, bgBlurSettings.enabled, let visionProvider = visionProvider {
            if let bgBlurPass = backgroundBlurPass {
                bgBlurPass.settings = bgBlurSettings
                bgBlurPass.inputTexture = currentTexture
                bgBlurPass.outputTexture = nil  // In-place
                bgBlurPass.visionProvider = visionProvider
                try bgBlurPass.execute(commandBuffer: commandBuffer, context: context)
                // currentTexture remains the same (modified in-place)
            }
        }
        
        // 3-6. Bloom/Halation/Anamorphic (parallel extraction, sequential composite)
        var bloomTexture: MTLTexture?
        var halationTexture: MTLTexture?
        var anamorphicTexture: MTLTexture?
        
        if let bloom = look.bloom, bloom.intensity > 0 {
            bloomTexture = try extractBloom(bloom, input: currentTexture, context: context, commandBuffer: commandBuffer)
        }
        
        if let halation = look.halation, halation.intensity > 0 {
            halationTexture = try extractHalation(halation, input: currentTexture, context: context, commandBuffer: commandBuffer)
        }
        
        if let anamorphic = look.anamorphic, anamorphic.intensity > 0 {
            anamorphicTexture = try extractAnamorphic(anamorphic, input: currentTexture, context: context, commandBuffer: commandBuffer)
        }
        
        // Composite bloom/halation/anamorphic onto current
        if let bloom = look.bloom, let bloomTex = bloomTexture {
            currentTexture = try compositeBloom(bloom, bloomTexture: bloomTex, onto: currentTexture, context: context, commandBuffer: commandBuffer)
            context.texturePool.return(bloomTex)
        }
        
        if let halation = look.halation, let halationTex = halationTexture {
            currentTexture = try compositeHalation(halation, halationTexture: halationTex, onto: currentTexture, context: context, commandBuffer: commandBuffer)
            context.texturePool.return(halationTex)
        }
        
        if let anamorphic = look.anamorphic, let anamorphicTex = anamorphicTexture {
            currentTexture = try compositeAnamorphic(anamorphic, streakTexture: anamorphicTex, onto: currentTexture, context: context, commandBuffer: commandBuffer)
            context.texturePool.return(anamorphicTex)
        }
        
        // 6. Spectral dispersion (prismatic light splitting)
        // Applied early in the chain for physically-based look
        if let spectral = look.spectralDispersion, spectral.intensity > 0 {
            currentTexture = try applySpectralDispersion(spectral, input: currentTexture, context: context, commandBuffer: commandBuffer)
        }
        
        // 7. Light leaks (colored light bleeds)
        if let lightLeaks = look.lightLeaks, lightLeaks.intensity > 0 {
            currentTexture = try applyLightLeak(lightLeaks, input: currentTexture, context: context, commandBuffer: commandBuffer)
        }
        
        // 8. Diffusion (soft glow - use bloom with lower threshold)
        if let diffusion = look.diffusion, diffusion.intensity > 0 {
            // Diffusion is implemented as a special bloom with lower threshold
            let diffusionBloom = BloomSettings(
                intensity: diffusion.intensity,
                threshold: diffusion.threshold,
                radius: diffusion.radius
            )
            if let diffTex = try extractBloom(diffusionBloom, input: currentTexture, context: context, commandBuffer: commandBuffer) {
                currentTexture = try compositeBloom(diffusionBloom, bloomTexture: diffTex, onto: currentTexture, context: context, commandBuffer: commandBuffer)
                context.texturePool.return(diffTex)
            }
        }
        
        // 8. Color grading (LUT) - placeholder for now
        // if let colorGrading = look.colorGrading { ... }
        
        // 9. Tone mapping
        if let toneMapping = look.toneMapping {
            currentTexture = try applyToneMapping(toneMapping, input: currentTexture, context: context, commandBuffer: commandBuffer)
        }
        
        // 10. Vignette
        if let vignette = look.vignette, vignette.intensity > 0 {
            currentTexture = try applyVignette(vignette, input: currentTexture, context: context, commandBuffer: commandBuffer)
        }
        
        // 11. Film grain (last, in output space)
        if let grain = look.filmGrain, grain.intensity > 0 {
            currentTexture = try applyFilmGrain(grain, input: currentTexture, context: context, commandBuffer: commandBuffer)
        }
        
        // Copy to output if needed
        if currentTexture !== output {
            if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
                blitEncoder.copy(from: currentTexture, to: output)
                blitEncoder.endEncoding()
            }
        }
    }
    
    // MARK: - Effect Helpers
    
    private func hasAnyEffect() -> Bool {
        return look.bloom != nil ||
               look.halation != nil ||
               look.filmGrain != nil ||
               look.vignette != nil ||
               look.lens != nil ||
               look.anamorphic != nil ||
               look.toneMapping != nil ||
               look.diffusion != nil ||
               look.lightLeaks != nil ||
               look.spectralDispersion != nil ||
               look.faceEnhance != nil ||
               look.backgroundBlur != nil
    }
    
    // MARK: - Lens Effects
    
    private func applyLens(_ lens: LensSettings, input: MTLTexture, context: RenderContext, commandBuffer: MTLCommandBuffer) throws -> MTLTexture {
        guard let pipeline = lensSystemPipeline,
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return input
        }
        
        guard let output = context.texturePool.acquireIntermediate(
            pixelFormat: input.pixelFormat,
            width: input.width,
            height: input.height,
            usage: [.shaderRead, .shaderWrite]
        ) else { return input }
        
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(input, index: 0)
        encoder.setTexture(output, index: 1)
        
        var params = LensSystemParams(
            k1: lens.distortion,
            k2: lens.distortionK2,
            chromaticAberration: lens.chromaticAberration,
            padding: 0
        )
        encoder.setBytes(&params, length: MemoryLayout<LensSystemParams>.size, index: 0)
        
        dispatchThreads(encoder: encoder, pipeline: pipeline, width: output.width, height: output.height)
        encoder.endEncoding()
        
        return output
    }
    
    // MARK: - Bloom
    
    internal func extractBloom(_ bloom: BloomSettings, input: MTLTexture, context: RenderContext, commandBuffer: MTLCommandBuffer) throws -> MTLTexture? {
        guard let prefilterPipeline = bloomPrefilterPipeline,
              let downsamplePipeline = bloomDownsamplePipeline,
              let upsamplePipeline = bloomUpsamplePipeline,
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }
        
        // Prefilter (threshold + firefly reduction)
        let halfWidth = max(1, input.width / 2)
        let halfHeight = max(1, input.height / 2)
        
        guard let prefiltered = context.texturePool.acquireIntermediate(
            pixelFormat: .rgba16Float,
            width: halfWidth,
            height: halfHeight,
            usage: [.shaderRead, .shaderWrite]
        ) else { return nil }
        
        encoder.setComputePipelineState(prefilterPipeline)
        encoder.setTexture(input, index: 0)
        encoder.setTexture(prefiltered, index: 1)
        
        var threshold = bloom.threshold
        var knee = bloom.knee
        var clampMax: Float = 100.0
        encoder.setBytes(&threshold, length: 4, index: 0)
        encoder.setBytes(&knee, length: 4, index: 1)
        encoder.setBytes(&clampMax, length: 4, index: 2)
        
        dispatchThreads(encoder: encoder, pipeline: prefilterPipeline, width: halfWidth, height: halfHeight)
        
        // Downsample chain
        let mipLevels = 5
        var mipTextures: [MTLTexture] = [prefiltered]
        var currentSource = prefiltered
        
        encoder.setComputePipelineState(downsamplePipeline)
        
        for _ in 0..<mipLevels {
            let w = max(1, currentSource.width / 2)
            let h = max(1, currentSource.height / 2)
            
            guard let mip = context.texturePool.acquireIntermediate(
                pixelFormat: .rgba16Float,
                width: w,
                height: h,
                usage: [.shaderRead, .shaderWrite]
            ) else { break }
            
            encoder.setTexture(currentSource, index: 0)
            encoder.setTexture(mip, index: 1)
            dispatchThreads(encoder: encoder, pipeline: downsamplePipeline, width: w, height: h)
            
            mipTextures.append(mip)
            currentSource = mip
        }
        
        // Upsample chain
        encoder.setComputePipelineState(upsamplePipeline)
        
        for i in (0..<mipTextures.count - 1).reversed() {
            let source = mipTextures[i + 1]
            let dest = mipTextures[i]
            
            encoder.setTexture(source, index: 0)
            encoder.setTexture(dest, index: 1)
            encoder.setTexture(dest, index: 2)
            
            var radius = bloom.radius
            var weight: Float = 1.0
            encoder.setBytes(&radius, length: 4, index: 0)
            encoder.setBytes(&weight, length: 4, index: 1)
            
            dispatchThreads(encoder: encoder, pipeline: upsamplePipeline, width: dest.width, height: dest.height)
        }
        
        encoder.endEncoding()
        
        // Return intermediate mips to pool (keep first for composite)
        for i in 1..<mipTextures.count {
            context.texturePool.return(mipTextures[i])
        }
        
        return mipTextures.first
    }
    
    internal func compositeBloom(_ bloom: BloomSettings, bloomTexture: MTLTexture, onto: MTLTexture, context: RenderContext, commandBuffer: MTLCommandBuffer) throws -> MTLTexture {
        guard let pipeline = bloomCompositePipeline,
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return onto
        }
        
        guard let output = context.texturePool.acquireIntermediate(
            pixelFormat: onto.pixelFormat,
            width: onto.width,
            height: onto.height,
            usage: [.shaderRead, .shaderWrite]
        ) else { return onto }
        
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(onto, index: 0)
        encoder.setTexture(bloomTexture, index: 1)
        encoder.setTexture(output, index: 2)
        
        var uniforms = BloomCompositeUniforms(intensity: bloom.intensity, preservation: 1.0)
        encoder.setBytes(&uniforms, length: MemoryLayout<BloomCompositeUniforms>.size, index: 0)
        
        dispatchThreads(encoder: encoder, pipeline: pipeline, width: output.width, height: output.height)
        encoder.endEncoding()
        
        context.texturePool.return(onto)
        return output
    }
    
    // MARK: - Halation
    
    internal func extractHalation(_ halation: HalationSettings, input: MTLTexture, context: RenderContext, commandBuffer: MTLCommandBuffer) throws -> MTLTexture? {
        guard let thresholdPipeline = halationThresholdPipeline,
              gaussianBlur != nil,
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }
        
        // Threshold
        guard let thresholded = context.texturePool.acquireIntermediate(
            pixelFormat: .rgba16Float,
            width: input.width / 2,
            height: input.height / 2,
            usage: [.shaderRead, .shaderWrite]
        ) else { return nil }
        
        encoder.setComputePipelineState(thresholdPipeline)
        encoder.setTexture(input, index: 0)
        encoder.setTexture(thresholded, index: 1)
        
        var threshold = halation.threshold
        encoder.setBytes(&threshold, length: 4, index: 0)
        
        dispatchThreads(encoder: encoder, pipeline: thresholdPipeline, width: thresholded.width, height: thresholded.height)
        encoder.endEncoding()
        
        // Blur
        guard let blurred = context.texturePool.acquireIntermediate(
            pixelFormat: .rgba16Float,
            width: thresholded.width,
            height: thresholded.height,
            usage: [.shaderRead, .shaderWrite]
        ) else {
            context.texturePool.return(thresholded)
            return nil
        }
        
        // Create blur with appropriate sigma for halation radius
        let halationBlur = MPSImageGaussianBlur(device: context.device, sigma: halation.radius * 20.0)
        halationBlur.encode(commandBuffer: commandBuffer, sourceTexture: thresholded, destinationTexture: blurred)
        
        context.texturePool.return(thresholded)
        return blurred
    }
    
    internal func compositeHalation(_ halation: HalationSettings, halationTexture: MTLTexture, onto: MTLTexture, context: RenderContext, commandBuffer: MTLCommandBuffer) throws -> MTLTexture {
        guard let pipeline = halationCompositePipeline,
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return onto
        }
        
        guard let output = context.texturePool.acquireIntermediate(
            pixelFormat: onto.pixelFormat,
            width: onto.width,
            height: onto.height,
            usage: [.shaderRead, .shaderWrite]
        ) else { return onto }
        
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(onto, index: 0)
        encoder.setTexture(halationTexture, index: 1)
        encoder.setTexture(output, index: 2)
        
        var uniforms = HalationCompositeUniforms(
            intensity: halation.intensity,
            time: time,
            radialFalloff: halation.radialFalloff ? 1 : 0,
            _pad3: 0,
            tint: halation.tint,
            _pad4: 0
        )
        encoder.setBytes(&uniforms, length: MemoryLayout<HalationCompositeUniforms>.size, index: 0)
        
        dispatchThreads(encoder: encoder, pipeline: pipeline, width: output.width, height: output.height)
        encoder.endEncoding()
        
        context.texturePool.return(onto)
        return output
    }
    
    // MARK: - Anamorphic
    
    private func extractAnamorphic(_ anamorphic: AnamorphicSettings, input: MTLTexture, context: RenderContext, commandBuffer: MTLCommandBuffer) throws -> MTLTexture? {
        guard let thresholdPipeline = anamorphicThresholdPipeline,
              let horizontalBlur = horizontalBlur,
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }
        
        // Threshold
        guard let thresholded = context.texturePool.acquireIntermediate(
            pixelFormat: .rgba16Float,
            width: input.width / 4,
            height: input.height / 4,
            usage: [.shaderRead, .shaderWrite]
        ) else { return nil }
        
        encoder.setComputePipelineState(thresholdPipeline)
        encoder.setTexture(input, index: 0)
        encoder.setTexture(thresholded, index: 1)
        
        var threshold = anamorphic.threshold
        encoder.setBytes(&threshold, length: 4, index: 0)
        
        dispatchThreads(encoder: encoder, pipeline: thresholdPipeline, width: thresholded.width, height: thresholded.height)
        encoder.endEncoding()
        
        // Horizontal blur (multiple passes for longer streaks)
        guard let blurred = context.texturePool.acquireIntermediate(
            pixelFormat: .rgba16Float,
            width: thresholded.width,
            height: thresholded.height,
            usage: [.shaderRead, .shaderWrite]
        ) else {
            context.texturePool.return(thresholded)
            return nil
        }
        
        // Multiple blur passes for longer streaks
        let passes = Int(anamorphic.streakLength * 3)
        var source = thresholded
        var dest = blurred
        
        for _ in 0..<max(1, passes) {
            horizontalBlur.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: dest)
            swap(&source, &dest)
        }
        
        // Return the non-result texture
        if source !== thresholded {
            context.texturePool.return(thresholded)
            return source
        } else {
            context.texturePool.return(blurred)
            return source
        }
    }
    
    private func compositeAnamorphic(_ anamorphic: AnamorphicSettings, streakTexture: MTLTexture, onto: MTLTexture, context: RenderContext, commandBuffer: MTLCommandBuffer) throws -> MTLTexture {
        guard let pipeline = anamorphicCompositePipeline,
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return onto
        }
        
        guard let output = context.texturePool.acquireIntermediate(
            pixelFormat: onto.pixelFormat,
            width: onto.width,
            height: onto.height,
            usage: [.shaderRead, .shaderWrite]
        ) else { return onto }
        
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(onto, index: 0)
        encoder.setTexture(streakTexture, index: 1)
        encoder.setTexture(output, index: 2)
        
        var uniforms = AnamorphicCompositeUniforms(intensity: anamorphic.intensity, tint: anamorphic.tint)
        encoder.setBytes(&uniforms, length: MemoryLayout<AnamorphicCompositeUniforms>.size, index: 0)
        
        dispatchThreads(encoder: encoder, pipeline: pipeline, width: output.width, height: output.height)
        encoder.endEncoding()
        
        context.texturePool.return(onto)
        return output
    }
    
    // MARK: - Vignette
    
    internal func applyVignette(_ vignette: VignetteSettings, input: MTLTexture, context: RenderContext, commandBuffer: MTLCommandBuffer) throws -> MTLTexture {
        guard let pipeline = vignettePipeline,
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return input
        }
        
        guard let output = context.texturePool.acquireIntermediate(
            pixelFormat: input.pixelFormat,
            width: input.width,
            height: input.height,
            usage: [.shaderRead, .shaderWrite]
        ) else { return input }
        
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(input, index: 0)
        encoder.setTexture(output, index: 1)
        
        var params = VignetteParams(
            sensorWidth: vignette.sensorWidth,
            focalLength: vignette.focalLength,
            intensity: vignette.intensity,
            smoothness: vignette.smoothness,
            roundness: vignette.roundness,
            padding: 0
        )
        encoder.setBytes(&params, length: MemoryLayout<VignetteParams>.size, index: 0)
        
        dispatchThreads(encoder: encoder, pipeline: pipeline, width: output.width, height: output.height)
        encoder.endEncoding()
        
        context.texturePool.return(input)
        return output
    }
    
    // MARK: - Film Grain
    
    internal func applyFilmGrain(_ grain: FilmGrainSettings, input: MTLTexture, context: RenderContext, commandBuffer: MTLCommandBuffer) throws -> MTLTexture {
        guard let pipeline = filmGrainPipeline,
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return input
        }
        
        guard let output = context.texturePool.acquireIntermediate(
            pixelFormat: input.pixelFormat,
            width: input.width,
            height: input.height,
            usage: [.shaderRead, .shaderWrite]
        ) else { return input }
        
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(input, index: 0)
        encoder.setTexture(output, index: 1)
        
        var uniforms = FilmGrainUniforms(
            time: grain.animated ? time : 0,
            intensity: grain.intensity,
            size: grain.size,
            shadowBoost: grain.shadowBoost
        )
        encoder.setBytes(&uniforms, length: MemoryLayout<FilmGrainUniforms>.size, index: 0)
        
        dispatchThreads(encoder: encoder, pipeline: pipeline, width: output.width, height: output.height)
        encoder.endEncoding()
        
        context.texturePool.return(input)
        return output
    }
    
    // MARK: - Spectral Dispersion
    
    /// Apply spectral dispersion (prismatic light splitting) effect.
    /// This simulates how a prism separates light into its constituent wavelengths.
    /// Operates in Linear ACEScg color space.
    private func applySpectralDispersion(_ spectral: SpectralDispersionSettings, input: MTLTexture, context: RenderContext, commandBuffer: MTLCommandBuffer) throws -> MTLTexture {
        guard let pipeline = spectralDispersionPipeline,
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return input
        }
        
        guard let output = context.texturePool.acquireIntermediate(
            pixelFormat: input.pixelFormat,
            width: input.width,
            height: input.height,
            usage: [.shaderRead, .shaderWrite]
        ) else { return input }
        
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(input, index: 0)
        encoder.setTexture(output, index: 1)
        
        // Convert angle from degrees to radians
        let angleRadians = spectral.angle * Float.pi / 180.0
        
        var params = SpectralDispersionParams(
            intensity: spectral.intensity,
            spread: spectral.spread,
            center: spectral.center,
            falloff: spectral.falloff,
            angle: angleRadians,
            samples: UInt32(max(3, min(spectral.samples, 16))),  // Clamp to 3-16
            padding: 0
        )
        encoder.setBytes(&params, length: MemoryLayout<SpectralDispersionParams>.size, index: 0)
        
        dispatchThreads(encoder: encoder, pipeline: pipeline, width: output.width, height: output.height)
        encoder.endEncoding()
        
        context.texturePool.return(input)
        return output
    }
    
    // MARK: - Light Leak
    
    /// Apply light leak effect (organic colored light bleeds).
    /// This simulates light bleeding through the camera gate in film cameras.
    /// Operates in Linear ACEScg color space for correct blending.
    private func applyLightLeak(_ lightLeak: LightLeakSettings, input: MTLTexture, context: RenderContext, commandBuffer: MTLCommandBuffer) throws -> MTLTexture {
        guard let pipeline = lightLeakPipeline,
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return input
        }
        
        guard let output = context.texturePool.acquireIntermediate(
            pixelFormat: input.pixelFormat,
            width: input.width,
            height: input.height,
            usage: [.shaderRead, .shaderWrite]
        ) else { return input }
        
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(input, index: 0)
        encoder.setTexture(output, index: 1)
        
        // Animation phase (0-1) based on time
        let animation = lightLeak.animated ? fmod(time * lightLeak.speed * 0.1, 1.0) : 0.0
        
        var params = LightLeakParams(
            intensity: lightLeak.intensity,
            tint: lightLeak.color,
            position: lightLeak.position,
            size: 0.4,              // Default size
            softness: 0.5,          // Default softness
            angle: 0.0,             // No rotation by default
            animation: animation,
            mode: 1,                // Screen blend mode
            padding: 0
        )
        encoder.setBytes(&params, length: MemoryLayout<LightLeakParams>.size, index: 0)
        
        dispatchThreads(encoder: encoder, pipeline: pipeline, width: output.width, height: output.height)
        encoder.endEncoding()
        
        context.texturePool.return(input)
        return output
    }
    
    // MARK: - Tone Mapping
    
    private func applyToneMapping(_ toneMapping: ToneMappingSettings, input: MTLTexture, context: RenderContext, commandBuffer: MTLCommandBuffer) throws -> MTLTexture {
        guard let pipeline = tonemapPipeline,
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return input
        }
        
        guard let output = context.texturePool.acquireIntermediate(
            pixelFormat: input.pixelFormat,
            width: input.width,
            height: input.height,
            usage: [.shaderRead, .shaderWrite]
        ) else { return input }
        
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(input, index: 0)
        encoder.setTexture(output, index: 1)
        
        var exposure = toneMapping.exposure
        encoder.setBytes(&exposure, length: 4, index: 0)
        
        dispatchThreads(encoder: encoder, pipeline: pipeline, width: output.width, height: output.height)
        encoder.endEncoding()
        
        context.texturePool.return(input)
        return output
    }
    
    // MARK: - Utilities
    
    private func dispatchThreads(encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, width: Int, height: Int) {
        let w = pipeline.threadExecutionWidth
        let h = pipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
        let threadsPerGrid = MTLSize(width: width, height: height, depth: 1)
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    }
}
