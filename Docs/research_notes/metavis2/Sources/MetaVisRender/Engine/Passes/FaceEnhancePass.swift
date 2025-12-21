// FaceEnhancePass.swift
// MetaVisRender
//
// AI-powered face enhancement pass for interviews and portrait video.
// Uses Apple Vision to detect faces and applies targeted enhancements.

import Metal
import MetalPerformanceShaders
import simd
import QuartzCore

// MARK: - FaceEnhancePass

/// Render pass that applies AI-driven face enhancement.
///
/// This pass:
/// 1. Uses VisionProvider to detect faces in the frame
/// 2. Generates a soft mask texture from face bounding boxes
/// 3. Applies bilateral filtering, highlight protection, and color correction
///    selectively to face regions
///
/// ## Usage
/// ```swift
/// let pass = FaceEnhancePass()
/// try pass.setup(device: device, library: library)
/// pass.settings = .interview
/// pass.inputTexture = frameTexture
/// pass.visionProvider = visionProvider
/// try pass.execute(commandBuffer: cmd, context: context)
/// ```
public class FaceEnhancePass: RenderPass {
    public var label: String = "Face Enhance Pass"
    
    // MARK: - Pipeline States
    
    private var faceEnhancePipeline: MTLComputePipelineState?
    private var generateMaskPipeline: MTLComputePipelineState?
    private var enhanceEyesPipeline: MTLComputePipelineState?
    private var combineMasksPipeline: MTLComputePipelineState?
    
    // Keep references for dynamic pipeline creation
    private var device: MTLDevice?
    private var library: MTLLibrary?
    
    // MARK: - Uniforms
    
    private struct FaceEnhanceParams {
        var skinSmoothing: Float
        var highlightProtection: Float
        var eyeBrightening: Float
        var localContrast: Float
        var colorCorrection: Float
        var saturationProtection: Float
        var intensity: Float
        var debugMode: Float
    }
    
    // MARK: - Configuration
    
    /// Face enhancement settings
    public var settings: FaceEnhanceSettings = .interview
    
    /// Input texture
    public var inputTexture: MTLTexture?
    
    /// Output texture (if nil, writes back to input)
    public var outputTexture: MTLTexture?
    
    /// Vision provider for face detection
    public var visionProvider: VisionProvider?
    
    /// Cached face mask texture
    private var faceMaskTexture: MTLTexture?
    
    /// Cached face observations
    private var cachedFaces: [FaceObservation] = []
    private var cacheTimestamp: Double = 0
    private let cacheDuration: Double = 0.1  // 100ms cache for face positions
    
    /// Buffer for face rects
    private var faceRectsBuffer: MTLBuffer?
    private var eyeRectsBuffer: MTLBuffer?
    
    // MARK: - Initialization
    
    public init() {}
    
    public func setup(device: MTLDevice, library: MTLLibrary) throws {
        // Cache device and library for dynamic pipelines
        self.device = device
        self.library = library
        
        // Load compute pipelines
        if let fn = library.makeFunction(name: "fx_face_enhance") {
            faceEnhancePipeline = try device.makeComputePipelineState(function: fn)
        }
        
        if let fn = library.makeFunction(name: "fx_generate_face_mask") {
            generateMaskPipeline = try device.makeComputePipelineState(function: fn)
        }
        
        if let fn = library.makeFunction(name: "fx_combine_masks") {
            combineMasksPipeline = try device.makeComputePipelineState(function: fn)
        }
        
        if let fn = library.makeFunction(name: "fx_enhance_eyes") {
            enhanceEyesPipeline = try device.makeComputePipelineState(function: fn)
        }
        
        // Pre-allocate buffers for up to 16 faces
        faceRectsBuffer = device.makeBuffer(length: MemoryLayout<SIMD4<Float>>.stride * 16, options: .storageModeShared)
        eyeRectsBuffer = device.makeBuffer(length: MemoryLayout<SIMD4<Float>>.stride * 2, options: .storageModeShared)
    }
    
    // MARK: - Execute
    
    public func execute(commandBuffer: MTLCommandBuffer, context: RenderContext) throws {
        guard settings.enabled,
              let input = inputTexture,
              let visionProvider = visionProvider else { return }
        
        // Skip if intensity is zero
        guard settings.intensity > 0.01 else { return }
        
        let output = outputTexture ?? input
        
        // 1. Detect faces (or use cached)
        let faces = try detectFaces(in: input, visionProvider: visionProvider)
        
        // Skip if no faces detected
        guard !faces.isEmpty else {
            // Copy input to output if needed
            if input !== output {
                if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
                    blitEncoder.copy(from: input, to: output)
                    blitEncoder.endEncoding()
                }
            }
            return
        }
        
        // 2. Optionally get person segmentation for better masking
        // Note: Segmentation is performed synchronously using a semaphore.
        // For production, consider caching segmentation results per frame.
        var segmentationMask: MTLTexture?
        if settings.useSegmentation {
            let semaphore = DispatchSemaphore(value: 0)
            var capturedMask: MTLTexture?
            
            Task {
                do {
                    capturedMask = try await getSegmentationMask(
                        in: input,
                        visionProvider: visionProvider,
                        context: context
                    )
                } catch {
                    // Segmentation failed, continue without it
                }
                semaphore.signal()
            }
            
            semaphore.wait()
            segmentationMask = capturedMask
        }
        
        // 3. Generate face mask texture
        let maskTexture = try generateFaceMask(
            faces: faces,
            width: input.width,
            height: input.height,
            context: context,
            commandBuffer: commandBuffer,
            segmentationMask: segmentationMask
        )
        
        // 4. Apply face enhancement
        if input === output {
            // In-place modification requires intermediate texture to avoid read/write conflict
            if let intermediate = context.texturePool.acquireIntermediate(
                pixelFormat: output.pixelFormat,
                width: output.width,
                height: output.height,
                usage: [.shaderRead, .shaderWrite]
            ) {
                try applyFaceEnhancement(
                    input: input,
                    output: intermediate,
                    mask: maskTexture,
                    context: context,
                    commandBuffer: commandBuffer
                )
                
                // Copy back
                if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
                    blitEncoder.copy(from: intermediate, to: output)
                    blitEncoder.endEncoding()
                }
                
                context.texturePool.return(intermediate)
            }
        } else {
            try applyFaceEnhancement(
                input: input,
                output: output,
                mask: maskTexture,
                context: context,
                commandBuffer: commandBuffer
            )
        }
        
        // 5. Optional: Eye enhancement (if landmarks available and enabled)
        if settings.eyeBrightening > 0.01 {
            let eyeRects = extractEyeRects(from: faces)
            if !eyeRects.isEmpty {
                try applyEyeEnhancement(
                    texture: output,
                    eyeRects: eyeRects,
                    context: context,
                    commandBuffer: commandBuffer
                )
            }
        }
        
        // Return textures to pool
        context.texturePool.return(maskTexture)
        if let segMask = segmentationMask {
            context.texturePool.return(segMask)
        }
    }
    
    // MARK: - Segmentation
    
    private func getSegmentationMask(
        in texture: MTLTexture,
        visionProvider: VisionProvider,
        context: RenderContext
    ) async throws -> MTLTexture? {
        do {
            let mask = try await visionProvider.segmentPeople(
                in: texture,
                quality: .balanced
            )
            return mask.texture
        } catch {
            // Segmentation failed, continue without it
            print("[FaceEnhancePass] Segmentation failed: \(error)")
            return nil
        }
    }
    
    // MARK: - Face Detection
    
    private func detectFaces(in texture: MTLTexture, visionProvider: VisionProvider) throws -> [FaceObservation] {
        // Check cache
        let now = CACurrentMediaTime()
        if now - cacheTimestamp < cacheDuration && !cachedFaces.isEmpty {
            return cachedFaces
        }
        
        // Detect faces asynchronously
        // Note: In a real implementation, this would be done ahead of time
        // to avoid blocking the render thread. For now, we use a semaphore.
        
        var faces: [FaceObservation] = []
        let semaphore = DispatchSemaphore(value: 0)
        
        
        Task {
            do {
                // Detect faces with or without landmarks based on eye enhancement needs
                let needsLandmarks = settings.eyeBrightening > 0.01
                faces = try await visionProvider.detectFaces(in: texture, landmarks: needsLandmarks)
            } catch {
                // Log error but continue (no faces)
                print("FaceEnhancePass: Face detection failed: \(error)")
            }
            semaphore.signal()
        }
        
        // Wait with timeout (increased to 0.5s to ensure detection on first frame)
        let result = semaphore.wait(timeout: .now() + 0.5)
        
        if result == .timedOut {
            print("FaceEnhancePass: Face detection timed out, using cached results")
            return cachedFaces
        }
        
        // Cache results
        cachedFaces = faces
        cacheTimestamp = now
        
        return faces
    }
    
    // MARK: - Face Mask Generation
    
    private func generateFaceMask(
        faces: [FaceObservation],
        width: Int,
        height: Int,
        context: RenderContext,
        commandBuffer: MTLCommandBuffer,
        segmentationMask: MTLTexture? = nil
    ) throws -> MTLTexture {
        guard let pipeline = generateMaskPipeline else {
            throw FaceEnhanceError.pipelineNotReady
        }
        
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw FaceEnhanceError.pipelineNotReady
        }
        
        guard let faceRectsBuffer = faceRectsBuffer else {
            throw FaceEnhanceError.pipelineNotReady
        }
        
        // Acquire mask texture
        guard let maskTexture = context.texturePool.acquireIntermediate(
            pixelFormat: .r16Float,
            width: width,
            height: height,
            usage: [.shaderRead, .shaderWrite]
        ) else {
            throw FaceEnhanceError.textureAllocationFailed
        }
        
        // Fill face rects buffer
        let faceRects = faces.prefix(16).map { face -> SIMD4<Float> in
            let bounds = face.bounds
            return SIMD4<Float>(
                Float(bounds.origin.x),
                Float(bounds.origin.y),
                Float(bounds.width),
                Float(bounds.height)
            )
        }
        
        let rectsPtr = faceRectsBuffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: 16)
        for (i, rect) in faceRects.enumerated() {
            rectsPtr[i] = rect
        }
        
        var faceCount = UInt32(faceRects.count)
        var featherAmount: Float = 0.15  // Edge softness
        
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(maskTexture, index: 0)
        encoder.setBuffer(faceRectsBuffer, offset: 0, index: 0)
        encoder.setBytes(&faceCount, length: MemoryLayout<UInt32>.size, index: 1)
        encoder.setBytes(&featherAmount, length: MemoryLayout<Float>.size, index: 2)
        
        dispatchThreads(encoder: encoder, pipeline: pipeline, width: width, height: height)
        encoder.endEncoding()
        
        // If we have segmentation, refine the mask by multiplying with person mask
        if let segMask = segmentationMask,
           let combinePipeline = combineMasksPipeline {
            
            // Create temp texture for refined mask
            guard let refinedMask = context.texturePool.acquireIntermediate(
                pixelFormat: .r16Float,
                width: width,
                height: height,
                usage: [.shaderRead, .shaderWrite]
            ) else {
                return maskTexture
            }
            
            // Use compute shader to multiply masks
            guard let combineEncoder = commandBuffer.makeComputeCommandEncoder() else {
                return maskTexture
            }
            
            combineEncoder.setComputePipelineState(combinePipeline)
            combineEncoder.setTexture(maskTexture, index: 0)
            combineEncoder.setTexture(segMask, index: 1)
            combineEncoder.setTexture(refinedMask, index: 2)
            
            dispatchThreads(encoder: combineEncoder, pipeline: combinePipeline, width: width, height: height)
            combineEncoder.endEncoding()
            
            // Return original mask to pool and use refined one
            context.texturePool.return(maskTexture)
            return refinedMask
        }
        
        return maskTexture
    }
    
    // MARK: - Face Enhancement
    
    private func applyFaceEnhancement(
        input: MTLTexture,
        output: MTLTexture,
        mask: MTLTexture,
        context: RenderContext,
        commandBuffer: MTLCommandBuffer
    ) throws {
        // Check pipeline BEFORE creating encoder
        guard let pipeline = faceEnhancePipeline else {
            throw FaceEnhanceError.pipelineNotReady
        }
        
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw FaceEnhanceError.pipelineNotReady
        }
        
        
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(input, index: 0)
        encoder.setTexture(output, index: 1)
        encoder.setTexture(mask, index: 2)
        
        var params = FaceEnhanceParams(
            skinSmoothing: settings.skinSmoothing,
            highlightProtection: settings.highlightProtection,
            eyeBrightening: settings.eyeBrightening,
            localContrast: settings.localContrast,
            colorCorrection: settings.colorCorrection,
            saturationProtection: settings.saturationProtection,
            intensity: settings.intensity,
            debugMode: settings.debugMode
        )
        encoder.setBytes(&params, length: MemoryLayout<FaceEnhanceParams>.size, index: 0)
        
        dispatchThreads(encoder: encoder, pipeline: pipeline, width: output.width, height: output.height)
        encoder.endEncoding()
    }
    
    // MARK: - Eye Enhancement
    
    private func extractEyeRects(from faces: [FaceObservation]) -> [SIMD4<Float>] {
        var eyeRects: [SIMD4<Float>] = []
        
        for face in faces {
            let bounds = face.bounds
            
            // If we have landmarks, use them for precise eye location
            if let leftEyePoint = face.landmarks?.leftEye {
                // Create rect around the eye point
                let eyeWidth = bounds.width * 0.2
                let eyeHeight = bounds.height * 0.1
                eyeRects.append(SIMD4<Float>(
                    Float(leftEyePoint.x - eyeWidth * 0.5),
                    Float(leftEyePoint.y - eyeHeight * 0.5),
                    Float(eyeWidth),
                    Float(eyeHeight)
                ))
            } else {
                // Estimate eye position from face bounds
                let eyeY = bounds.origin.y + bounds.height * 0.35
                let eyeHeight = bounds.height * 0.15
                let eyeWidth = bounds.width * 0.25
                
                // Left eye
                let leftEyeX = bounds.origin.x + bounds.width * 0.2
                eyeRects.append(SIMD4<Float>(
                    Float(leftEyeX),
                    Float(eyeY),
                    Float(eyeWidth),
                    Float(eyeHeight)
                ))
            }
            
            if let rightEyePoint = face.landmarks?.rightEye {
                // Create rect around the eye point
                let eyeWidth = bounds.width * 0.2
                let eyeHeight = bounds.height * 0.1
                eyeRects.append(SIMD4<Float>(
                    Float(rightEyePoint.x - eyeWidth * 0.5),
                    Float(rightEyePoint.y - eyeHeight * 0.5),
                    Float(eyeWidth),
                    Float(eyeHeight)
                ))
            } else {
                let eyeY = bounds.origin.y + bounds.height * 0.35
                let eyeHeight = bounds.height * 0.15
                let eyeWidth = bounds.width * 0.25
                
                // Right eye
                let rightEyeX = bounds.origin.x + bounds.width * 0.55
                eyeRects.append(SIMD4<Float>(
                    Float(rightEyeX),
                    Float(eyeY),
                    Float(eyeWidth),
                    Float(eyeHeight)
                ))
            }
            
            // Only process first face's eyes to limit complexity
            break
        }
        
        return eyeRects
    }
    
    private func applyEyeEnhancement(
        texture: MTLTexture,
        eyeRects: [SIMD4<Float>],
        context: RenderContext,
        commandBuffer: MTLCommandBuffer
    ) throws {
        guard let pipeline = enhanceEyesPipeline,
              let eyeRectsBuffer = eyeRectsBuffer else {
            return  // Eye enhancement is optional, don't throw
        }
        
        // Need intermediate texture for in-place operation
        guard let tempTexture = context.texturePool.acquireIntermediate(
            pixelFormat: texture.pixelFormat,
            width: texture.width,
            height: texture.height,
            usage: [.shaderRead, .shaderWrite]
        ) else { return }
        
        // Copy current to temp (use blit encoder first, before compute encoder)
        if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
            blitEncoder.copy(from: texture, to: tempTexture)
            blitEncoder.endEncoding()
        }
        
        // Now create compute encoder
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            context.texturePool.return(tempTexture)
            return
        }
        
        // Fill eye rects buffer
        let rectsPtr = eyeRectsBuffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: 2)
        for (i, rect) in eyeRects.prefix(2).enumerated() {
            rectsPtr[i] = rect
        }
        
        var eyeCount = UInt32(min(eyeRects.count, 2))
        var brightness = settings.eyeBrightening
        var intensity = settings.intensity
        
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(tempTexture, index: 0)
        encoder.setTexture(texture, index: 1)
        encoder.setBuffer(eyeRectsBuffer, offset: 0, index: 0)
        encoder.setBytes(&eyeCount, length: MemoryLayout<UInt32>.size, index: 1)
        encoder.setBytes(&brightness, length: MemoryLayout<Float>.size, index: 2)
        encoder.setBytes(&intensity, length: MemoryLayout<Float>.size, index: 3)
        
        dispatchThreads(encoder: encoder, pipeline: pipeline, width: texture.width, height: texture.height)
        encoder.endEncoding()
        
        context.texturePool.return(tempTexture)
    }
    
    // MARK: - Utilities
    
    private func dispatchThreads(encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, width: Int, height: Int) {
        let w = pipeline.threadExecutionWidth
        let h = pipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
        let threadsPerGrid = MTLSize(width: width, height: height, depth: 1)
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    }
    
    /// Clear cached face data
    public func clearCache() {
        cachedFaces = []
        cacheTimestamp = 0
    }
}

// MARK: - Errors

public enum FaceEnhanceError: Error, LocalizedError {
    case pipelineNotReady
    case textureAllocationFailed
    case faceDetectionFailed
    
    public var errorDescription: String? {
        switch self {
        case .pipelineNotReady:
            return "Face enhancement pipeline not initialized"
        case .textureAllocationFailed:
            return "Failed to allocate texture for face mask"
        case .faceDetectionFailed:
            return "Face detection failed"
        }
    }
}

// MARK: - RenderPass Protocol Extension

extension FaceEnhancePass {
    /// Convenience method to apply face enhancement in the cinematic look pipeline
    public func apply(
        to texture: MTLTexture,
        settings: FaceEnhanceSettings,
        visionProvider: VisionProvider,
        context: RenderContext,
        commandBuffer: MTLCommandBuffer
    ) throws -> MTLTexture {
        guard settings.enabled else { return texture }
        
        self.settings = settings
        self.inputTexture = texture
        self.visionProvider = visionProvider
        
        // Allocate output texture
        guard let output = context.texturePool.acquireIntermediate(
            pixelFormat: texture.pixelFormat,
            width: texture.width,
            height: texture.height,
            usage: [.shaderRead, .shaderWrite]
        ) else {
            return texture
        }
        
        self.outputTexture = output
        
        try execute(commandBuffer: commandBuffer, context: context)
        
        // Don't return input to pool - caller owns it
        // Only intermediate textures acquired within execute() are returned to pool
        
        return output
    }
}
