import Foundation
@preconcurrency import Metal
import Shared

/// Renders image animation with easing and transforms
public actor ImageAnimationRenderer {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let imageLoader: ImageLoader

    private var transformPipeline: MTLComputePipelineState?
    private var lanczos3Pipeline: MTLComputePipelineState?

    public init(device: MTLDevice, commandQueue: MTLCommandQueue) {
        self.device = device
        self.commandQueue = commandQueue
        imageLoader = ImageLoader(device: device, commandQueue: commandQueue)
    }

    /// Render animation from request
    public func renderAnimation(
        request: ImageAnimationRequest
    ) async throws -> AsyncStream<MTLTexture> {
        // Load source image
        let sourceTexture = try imageLoader.loadTexture(from: request.imagePath)

        // Setup shaders
        try setupPipelines(useHighQuality: request.quality?.useLanczos3 ?? false)

        // Generate keyframes
        let keyframes = try generateKeyframes(from: request.animation)

        // Calculate frame count
        let fps = request.output.fps
        let duration = request.animation.duration
        let frameCount = Int(duration * Double(fps))

        // Create output stream
        return AsyncStream { continuation in
            Task {
                for frameIndex in 0 ..< frameCount {
                    let time = Double(frameIndex) / Double(fps)

                    // Interpolate transform at current time
                    let transform = interpolateTransform(
                        at: time,
                        keyframes: keyframes,
                        easing: request.animation.easing
                    )

                    // Render frame
                    let frame = try await renderFrame(
                        source: sourceTexture,
                        transform: transform,
                        outputSize: (request.output.width, request.output.height),
                        quality: request.quality
                    )

                    continuation.yield(frame)
                }

                continuation.finish()
            }
        }
    }

    /// Setup Metal compute pipelines
    private func setupPipelines(useHighQuality: Bool) throws {
        // Load shader library - try to compile from source for SPM compatibility
        let library: MTLLibrary

        // Load ColorSpace.metal first
        var shaderSource = ""
        if let colorSpacePath = Bundle.module.path(forResource: "ColorSpace", ofType: "metal"),
           let colorSpaceSource = try? String(contentsOfFile: colorSpacePath) {
            shaderSource += colorSpaceSource + "\n"
        }

        // Try to find and compile ImageTransform.metal from bundle
        if let bundlePath = Bundle.module.path(forResource: "ImageTransform", ofType: "metal") {
            print("[ImageRenderer] Found shader at: \(bundlePath)")
            if let transformSource = try? String(contentsOfFile: bundlePath) {
                shaderSource += transformSource
                print("[ImageRenderer] Loaded shader source (\(shaderSource.count) chars)")
                do {
                    library = try device.makeLibrary(source: shaderSource, options: nil)
                    print("[ImageRenderer] Compiled shader library successfully")
                } catch {
                    print("[ImageRenderer] Failed to compile shader: \(error)")
                    throw ImageRendererError.unableToLoadShaderLibrary
                }
            } else {
                print("[ImageRenderer] Failed to read shader source")
                throw ImageRendererError.unableToLoadShaderLibrary
            }
        } else if let defaultLibrary = device.makeDefaultLibrary() {
            print("[ImageRenderer] Using default library")
            library = defaultLibrary
        } else {
            print("[ImageRenderer] No shader library found")
            throw ImageRendererError.unableToLoadShaderLibrary
        }

        // Basic transform pipeline
        guard let transformFunction = library.makeFunction(name: "transform_image") else {
            throw ImageRendererError.shaderNotFound("transform_image")
        }
        transformPipeline = try device.makeComputePipelineState(function: transformFunction)

        // High-quality Lanczos3 pipeline
        if useHighQuality {
            guard let lanczosFunction = library.makeFunction(name: "transform_image_lanczos3") else {
                throw ImageRendererError.shaderNotFound("transform_image_lanczos3")
            }
            lanczos3Pipeline = try device.makeComputePipelineState(function: lanczosFunction)
        }
    }

    /// Generate keyframes from animation config
    public nonisolated func publicGenerateKeyframes(from config: ImageAnimationConfig) throws -> [TransformKeyframe] {
        return try generateKeyframes(from: config)
    }

    /// Generate keyframes from animation config (internal)
    private nonisolated func generateKeyframes(from config: ImageAnimationConfig) throws -> [TransformKeyframe] {
        // If custom keyframes provided, use them
        if let customKeyframes = config.keyframes, !customKeyframes.isEmpty {
            return customKeyframes
        }

        // Otherwise, generate from motion pattern
        return try generateKeyframesFromPattern(
            pattern: config.motion,
            duration: config.duration
        )
    }

    /// Generate keyframes from motion pattern
    private nonisolated func generateKeyframesFromPattern(
        pattern: MotionPattern,
        duration: Double
    ) throws -> [TransformKeyframe] {
        switch pattern {
        case .kenBurns:
            // Classic Ken Burns: slow zoom + subtle pan
            return [
                TransformKeyframe(time: 0, translation: [0, 0], scale: [1.0, 1.0], rotation: 0, opacity: 1.0),
                TransformKeyframe(time: duration, translation: [50, 30], scale: [1.2, 1.2], rotation: 0, opacity: 1.0)
            ]

        case .zoom:
            // Pure zoom
            return [
                TransformKeyframe(time: 0, translation: [0, 0], scale: [1.0, 1.0], rotation: 0, opacity: 1.0),
                TransformKeyframe(time: duration, translation: [0, 0], scale: [1.5, 1.5], rotation: 0, opacity: 1.0)
            ]

        case .pan:
            // Horizontal pan
            return [
                TransformKeyframe(time: 0, translation: [-100, 0], scale: [1.2, 1.2], rotation: 0, opacity: 1.0),
                TransformKeyframe(time: duration, translation: [100, 0], scale: [1.2, 1.2], rotation: 0, opacity: 1.0)
            ]

        case .rotate:
            // Rotation around center
            return [
                TransformKeyframe(time: 0, translation: [0, 0], scale: [1.0, 1.0], rotation: 0, opacity: 1.0),
                TransformKeyframe(time: duration, translation: [0, 0], scale: [1.0, 1.0], rotation: 15, opacity: 1.0)
            ]

        case .parallax, .custom:
            throw ImageRendererError.unsupportedMotionPattern(pattern)
        }
    }

    /// Interpolate transform at given time using keyframes
    private nonisolated func interpolateTransform(
        at time: Double,
        keyframes: [TransformKeyframe],
        easing: EasingFunction
    ) -> TransformParams {
        // Find surrounding keyframes
        guard !keyframes.isEmpty else {
            return TransformParams()
        }

        // Before first keyframe
        if time <= keyframes.first!.time {
            return keyframeToParams(keyframes.first!)
        }

        // After last keyframe
        if time >= keyframes.last!.time {
            return keyframeToParams(keyframes.last!)
        }

        // Find interpolation range
        var startFrame = keyframes[0]
        var endFrame = keyframes[0]

        for i in 0 ..< keyframes.count - 1 {
            if time >= keyframes[i].time && time <= keyframes[i + 1].time {
                startFrame = keyframes[i]
                endFrame = keyframes[i + 1]
                break
            }
        }

        // Calculate normalized time (0-1)
        let duration = endFrame.time - startFrame.time
        let localTime = time - startFrame.time
        let t = duration > 0 ? (localTime / duration) : 0.0

        // Apply easing
        let easedT = applyEasing(t: t, function: easing)

        // Interpolate values
        let translation = SIMD2<Float>(
            Float(lerp(startFrame.translation[0], endFrame.translation[0], easedT)),
            Float(lerp(startFrame.translation[1], endFrame.translation[1], easedT))
        )

        let scale = SIMD2<Float>(
            Float(lerp(startFrame.scale[0], endFrame.scale[0], easedT)),
            Float(lerp(startFrame.scale[1], endFrame.scale[1], easedT))
        )

        let rotation = Float(lerp(startFrame.rotation, endFrame.rotation, easedT))
        let opacity = Float(lerp(startFrame.opacity, endFrame.opacity, easedT))

        let anchor = SIMD2<Float>(
            Float(startFrame.anchor?[0] ?? 0.5),
            Float(startFrame.anchor?[1] ?? 0.5)
        )

        return TransformParams(
            translation: translation,
            scale: scale,
            rotation: rotation * .pi / 180.0, // degrees to radians
            anchor: anchor,
            opacity: opacity
        )
    }

    /// Convert keyframe to transform params
    private nonisolated func keyframeToParams(_ keyframe: TransformKeyframe) -> TransformParams {
        let trans = SIMD2<Float>(Float(keyframe.translation[0]), Float(keyframe.translation[1]))
        let scl = SIMD2<Float>(Float(keyframe.scale[0]), Float(keyframe.scale[1]))
        let rot = Float(keyframe.rotation) * .pi / 180.0
        let anc = SIMD2<Float>(
            Float(keyframe.anchor?[0] ?? 0.5),
            Float(keyframe.anchor?[1] ?? 0.5)
        )
        let opa = Float(keyframe.opacity)

        return TransformParams(
            translation: trans,
            scale: scl,
            rotation: rot,
            anchor: anc,
            opacity: opa
        )
    }

    /// Apply easing function
    private nonisolated func applyEasing(t: Double, function: EasingFunction) -> Double {
        switch function {
        case .linear:
            return t

        case .easeIn:
            return t * t

        case .easeOut:
            return 1 - (1 - t) * (1 - t)

        case .easeInOut:
            if t < 0.5 {
                return 2 * t * t
            } else {
                return 1 - pow(-2 * t + 2, 2) / 2
            }

        case .cubicBezier:
            // Standard cubic bezier (0.42, 0, 0.58, 1)
            return cubicBezier(t: t, p1: 0.42, p2: 0.58)
        }
    }

    /// Cubic bezier interpolation
    private nonisolated func cubicBezier(t: Double, p1: Double, p2: Double) -> Double {
        let t2 = t * t
        let t3 = t2 * t
        let mt = 1 - t
        let mt2 = mt * mt

        return 3 * mt2 * t * p1 + 3 * mt * t2 * p2 + t3
    }

    /// Linear interpolation
    private nonisolated func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        return a + (b - a) * t
    }

    /// Render single frame with transform (public for job queue)
    public func publicRenderFrame(
        source: MTLTexture,
        keyframes: [TransformKeyframe],
        time: Double,
        easing: EasingFunction,
        outputSize: (width: Int, height: Int),
        quality: ImageQualityConfig?
    ) async throws -> MTLTexture {
        // Setup pipelines if not already done
        try setupPipelines(useHighQuality: quality?.useLanczos3 ?? false)

        // Interpolate transform at current time
        let transform = interpolateTransform(at: time, keyframes: keyframes, easing: easing)

        // Render the frame
        return try await renderFrame(
            source: source,
            transform: transform,
            outputSize: outputSize,
            quality: quality
        )
    }

    /// Render single frame with explicit transform parameters
    public func renderSingleFrame(
        source: MTLTexture,
        transform: TransformParams,
        outputSize: (width: Int, height: Int),
        quality: ImageQualityConfig? = nil
    ) async throws -> SendableTexture {
        // Setup pipelines if not already done
        try setupPipelines(useHighQuality: quality?.useLanczos3 ?? false)

        let texture = try await renderFrame(
            source: source,
            transform: transform,
            outputSize: outputSize,
            quality: quality
        )
        return SendableTexture(texture)
    }

    /// Render single frame with transform (internal)
    private func renderFrame(
        source: MTLTexture,
        transform: TransformParams,
        outputSize: (width: Int, height: Int),
        quality: ImageQualityConfig?
    ) async throws -> MTLTexture {
        // Create output texture from pool
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: outputSize.width,
            height: outputSize.height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .shaderWrite]

        guard let outputTexture = device.makeTexture(descriptor: textureDescriptor) else {
            throw ImageRendererError.unableToCreateTexture
        }

        // Choose pipeline based on quality
        let pipeline = (quality?.useLanczos3 ?? false) ? lanczos3Pipeline : transformPipeline
        guard let pipelineState = pipeline else {
            throw ImageRendererError.pipelineNotInitialized
        }

        // Create command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw ImageRendererError.unableToCreateCommandBuffer
        }

        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(outputTexture, index: 1)

        var params = transform

        // Check if source texture is sRGB-tagged (hardware decoding)
        // If so, the sampler returns Linear values, so we shouldn't linearize again in shader.
        print("[ImageRenderer] Input Texture Format: \(source.pixelFormat.rawValue)")
        print("[ImageRenderer] Input Transfer Function: \(params.inputTransferFunction)")
        if source.pixelFormat == .bgra8Unorm_srgb || source.pixelFormat == .rgba8Unorm_srgb {
            print("[ImageRenderer] Detected sRGB texture format, disabling shader linearization")
            params.inputTransferFunction = 0 // Linear
        }
        
        print("[ImageRenderer] Input Texture Format: \(source.pixelFormat.rawValue)")
        print("[ImageRenderer] Params: CS=\(params.inputColorSpace), TF=\(params.inputTransferFunction)")

        encoder.setBytes(&params, length: MemoryLayout<TransformParams>.size, index: 0)

        // Calculate thread groups
        let w = pipelineState.threadExecutionWidth
        let h = pipelineState.maxTotalThreadsPerThreadgroup / w
        let threadsPerThreadgroup = MTLSizeMake(w, h, 1)
        let threadsPerGrid = MTLSizeMake(outputSize.width, outputSize.height, 1)

        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()

        return try await withCheckedThrowingContinuation { continuation in
            commandBuffer.addCompletedHandler { _ in
                continuation.resume(returning: outputTexture)
            }
            commandBuffer.commit()
        }
    }
}

/// Transform parameters matching Metal shader struct
public struct TransformParams: Sendable {
    public var translation: SIMD2<Float>
    public var scale: SIMD2<Float>
    public var anchor: SIMD2<Float>
    public var shadowOffset: SIMD2<Float>

    public var borderColor: SIMD4<Float>
    public var shadowColor: SIMD4<Float>

    public var rotation: Float
    public var opacity: Float
    public var borderWidth: Float
    public var shadowRadius: Float
    public var shadowOpacity: Float

    public var time: Float
    public var shimmerSpeed: Float
    public var shimmerIntensity: Float
    public var shimmerWidth: Float

    public var inputColorSpace: UInt32
    public var inputTransferFunction: UInt32
    public var hdrScalingFactor: Float

    private var _padding: Float = 0

    public init(
        translation: SIMD2<Float> = .zero,
        scale: SIMD2<Float> = SIMD2(1, 1),
        rotation: Float = 0,
        anchor: SIMD2<Float> = SIMD2(0.5, 0.5),
        opacity: Float = 1.0,
        borderColor: SIMD4<Float> = .zero,
        borderWidth: Float = 0,
        shadowRadius: Float = 0,
        shadowOpacity: Float = 0,
        shadowOffset: SIMD2<Float> = .zero,
        shadowColor: SIMD4<Float> = .zero,
        time: Float = 0,
        shimmerSpeed: Float = 0,
        shimmerIntensity: Float = 0,
        shimmerWidth: Float = 0,
        inputColorSpace: UInt32 = 0, // sRGB
        inputTransferFunction: UInt32 = 1, // sRGB
        hdrScalingFactor: Float = 100.0
    ) {
        self.translation = translation
        self.scale = scale
        self.anchor = anchor
        self.shadowOffset = shadowOffset
        self.borderColor = borderColor
        self.shadowColor = shadowColor
        self.rotation = rotation
        self.opacity = opacity
        self.borderWidth = borderWidth
        self.shadowRadius = shadowRadius
        self.shadowOpacity = shadowOpacity
        self.time = time
        self.shimmerSpeed = shimmerSpeed
        self.shimmerIntensity = shimmerIntensity
        self.shimmerWidth = shimmerWidth
        self.inputColorSpace = inputColorSpace
        self.inputTransferFunction = inputTransferFunction
        self.hdrScalingFactor = hdrScalingFactor
    }
}

public enum ImageRendererError: Error {
    case unableToLoadShaderLibrary
    case shaderNotFound(String)
    case unableToCreateTexture
    case unableToCreateCommandBuffer
    case pipelineNotInitialized
    case unsupportedMotionPattern(MotionPattern)
}
