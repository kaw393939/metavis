import CoreGraphics
import CoreText
import Foundation
@preconcurrency import Metal
import simd

/// SDF Text Renderer
/// Renders text using signed distance field technique for broadcast-quality output
/// Based on: Metal by Example, Chapter 12 (pages 114-116)
///
/// Features:
/// - Infinite scalability without blur
/// - Sharp edges at any zoom level
/// - Antialiasing through alpha blending
/// - GPU-accelerated rendering
/// - Lazy evaluation via TexturePromise
public actor SDFTextRenderer {
    // MARK: - Properties

    /// Rendering mode (Standard SDF or Multi-Channel SDF)
    public enum SDFMode: Sendable {
        case sdf // Single-channel signed distance field
        case msdf // Multi-channel signed distance field (sharp corners)
        case mtsdf // Multi-channel True SDF (sharp corners + accurate outlines)
    }

    /// Current rendering mode
    public nonisolated let mode: SDFMode

    /// Font atlas containing SDF data
    public nonisolated let fontAtlas: SDFFontAtlas

    /// Metal render pipeline for SDF text
    public nonisolated let pipeline: MTLRenderPipelineState

    /// Current pixel format
    public nonisolated let pixelFormat: MTLPixelFormat

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private nonisolated let atlasWidth: Int
    private nonisolated let atlasHeight: Int
    private nonisolated let glyphMetrics: [Character: SDFFontAtlas.GlyphMetrics]

    /// Cached sampler state to avoid recreation
    private nonisolated let samplerState: MTLSamplerState

    /// Layout engine for text positioning
    private nonisolated let layoutEngine: TextLayoutEngine

    // MARK: - Initialization

    /// Create SDF text renderer
    /// - Parameters:
    ///   - fontAtlas: Pre-generated SDF font atlas
    ///   - device: Metal device
    ///   - mode: Rendering mode (default: .sdf)
    ///   - shaderLibrary: Optional shared shader library (creates local one if nil)
    ///   - pixelFormat: Output pixel format (default: .rgba16Float)
    public init(fontAtlas: SDFFontAtlas, device: MTLDevice, mode: SDFMode = .sdf, shaderLibrary: ShaderLibrary? = nil, pixelFormat: MTLPixelFormat = .rgba16Float) throws {
        self.fontAtlas = fontAtlas
        self.device = device
        self.mode = mode
        self.pixelFormat = pixelFormat
        atlasWidth = fontAtlas.texture.width
        atlasHeight = fontAtlas.texture.height
        glyphMetrics = fontAtlas.glyphMetrics

        guard let queue = device.makeCommandQueue() else {
            throw SDFRendererError.commandQueueCreationFailed
        }
        commandQueue = queue

        // Create sampler state once
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .notMipmapped
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw SDFRendererError.samplerCreationFailed
        }
        samplerState = sampler

        // Initialize layout engine
        layoutEngine = TextLayoutEngine(fontAtlas: fontAtlas)

        // Use provided library or create local one
        let lib = shaderLibrary ?? ShaderLibrary(device: device)

        // Ensure SDFText shaders are loaded
        // Note: In production, these would be in default.metallib
        // For dev, we try to load source if function not found
        if (try? lib.makeFunction(name: "sdf_vertex")) == nil {
            try? lib.loadSource(resource: "SDFText")
        }

        // Load shader functions
        let fragmentFunctionName: String
        switch mode {
        case .sdf: fragmentFunctionName = "sdf_fragment"
        case .msdf: fragmentFunctionName = "msdf_fragment"
        case .mtsdf: fragmentFunctionName = "mtsdf_fragment"
        }

        guard let vertexFunction = try? lib.makeFunction(name: "sdf_vertex"),
              let fragmentFunction = try? lib.makeFunction(name: fragmentFunctionName)
        else {
            throw SDFRendererError.shaderCompilationFailed("Could not find SDF shader functions (vertex: sdf_vertex, fragment: \(fragmentFunctionName))")
        }

        // Create render pipeline state
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        // Premultiplied Alpha Blending (Standard)
        // Result = Src.rgb * 1 + Dst.rgb * (1 - Src.a)
        // (Since Src.rgb is already multiplied by Src.a in the shader)
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        // Setup vertex descriptor
        let vertexDescriptor = MTLVertexDescriptor()
        // Position attribute (float2)
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        // TexCoords attribute (float2)
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 2
        vertexDescriptor.attributes[1].bufferIndex = 0
        // Layout
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.size * 4 // 2 float2s
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        pipelineDescriptor.vertexDescriptor = vertexDescriptor

        do {
            pipeline = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            throw SDFRendererError.shaderCompilationFailed("Pipeline creation failed: \(error)")
        }
    }

    // MARK: - Helpers

    private nonisolated func convertAlignment(_ alignment: TextAlignment) -> TextLayoutEngine.Alignment {
        switch alignment {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }

    // MARK: - Rendering

    struct SDFUniforms {
        var color: SIMD4<Float>
        var edgeDistance: Float
        var edgeSoftness: Float
        var padding1: SIMD2<Float> = .zero
        var outlineColor: SIMD4<Float>
        var outlineWidth: Float
        var fadeStart: Float
        var fadeEnd: Float
        var padding2: Float = 0
    }

    /// Render text to Metal texture using SDF technique
    /// - Parameters:
    ///   - text: String to render
    ///   - position: Position in pixels (top-left origin)
    ///   - color: RGBA color [0, 1]
    ///   - fontSize: Target font size in pixels (overrides scale if > 0)
    ///   - weight: Font weight (0.0 = thin, 0.5 = regular, 1.0 = bold)
    ///   - softness: Edge softness (0.0 = sharp, 1.0 = blurred)
    ///   - outlineColor: Outline color (RGBA)
    ///   - outlineWidth: Outline width in pixels (0 = no outline)
    ///   - tracking: Letter spacing in ems (e.g. 0.1 = loose, -0.05 = tight)
    ///   - scale: Legacy scale factor (used if fontSize is 0)
    ///   - alphaType: Alpha type for output texture (default: premultiplied for correct blending)
    ///   - mvpMatrix: Optional Model-View-Projection matrix for 3D transforms
    ///   - fadeStart: Distance from camera where fade begins (alpha = 1.0)
    ///   - fadeEnd: Distance from camera where fade ends (alpha = 0.0)
    /// - Returns: Metal texture with rendered text (RGBA8Unorm with alpha)
    public nonisolated func render(
        text: String,
        position: CGPoint,
        color: SIMD4<Float>,
        fontSize: Float = 0,
        weight: Float = 0.5,
        softness: Float = 0.0,
        outlineColor: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1),
        outlineWidth: Float = 0.0,
        tracking: Float = 0.0,
        scale: Float = 1.0,
        alphaType _: AlphaType = .premultiplied,
        mvpMatrix: matrix_float4x4? = nil,
        fadeStart: Float = 0.0,
        fadeEnd: Float = 0.0
    ) async throws -> MTLTexture {
        // Calculate output texture size
        let width = 1920
        let height = 1080

        // Create command buffer first
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw SDFRendererError.commandBufferCreationFailed
        }

        // Create output texture
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.pixelFormat = pixelFormat
        textureDescriptor.width = width
        textureDescriptor.height = height
        textureDescriptor.usage = [.shaderRead, .renderTarget]
        textureDescriptor.storageMode = .shared

        guard let outputTexture = device.makeTexture(descriptor: textureDescriptor) else {
            throw SDFRendererError.textureCreationFailed
        }

        // Use Layout Engine
        // Note: Primitive render uses .baseline vertical alignment to match legacy behavior
        let layout = layoutEngine.layout(
            text: text,
            position: SIMD2(Float(position.x), Float(position.y)),
            fontSize: fontSize,
            lineHeightMultiplier: 1.2,
            alignment: .left,
            verticalAlignment: .baseline,
            tracking: tracking,
            scale: scale
        )

        // Early exit if no renderable glyphs
        if layout.glyphs.isEmpty {
            return outputTexture
        }

        // Build glyph vertex data
        struct Vertex {
            var position: SIMD2<Float>
            var texCoords: SIMD2<Float>
        }

        var vertices: [Vertex] = []
        vertices.reserveCapacity(layout.glyphs.count * 6)

        for glyph in layout.glyphs {
            let x0 = glyph.position.x
            let y0 = glyph.position.y
            let x1 = x0 + glyph.size.x
            let y1 = y0 + glyph.size.y

            // Standard U coordinates (No flip)
            let u0 = glyph.texCoords.x
            let v0 = glyph.texCoords.y
            let u1 = glyph.texCoords.z
            let v1 = glyph.texCoords.w

            vertices.append(contentsOf: [
                Vertex(position: SIMD2(x0, y0), texCoords: SIMD2(u0, v0)),
                Vertex(position: SIMD2(x1, y0), texCoords: SIMD2(u1, v0)),
                Vertex(position: SIMD2(x0, y1), texCoords: SIMD2(u0, v1)),
                Vertex(position: SIMD2(x1, y0), texCoords: SIMD2(u1, v0)),
                Vertex(position: SIMD2(x1, y1), texCoords: SIMD2(u1, v1)),
                Vertex(position: SIMD2(x0, y1), texCoords: SIMD2(u0, v1))
            ])
        }

        // Create vertex buffer
        guard let vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Vertex>.stride,
            options: .storageModeShared
        ) else {
            throw SDFRendererError.bufferCreationFailed
        }

        // Create MVP Matrix
        var finalMVP: matrix_float4x4
        
        if let providedMVP = mvpMatrix {
            finalMVP = providedMVP
        } else {
            // Create orthographic projection matrix (NDC: -1 to 1)
            let left: Float = 0
            let right = Float(width)
            let bottom = Float(height)
            let top: Float = 0
            let near: Float = -1
            let far: Float = 1

            finalMVP = matrix_float4x4(
                SIMD4(2.0 / (right - left), 0, 0, 0),
                SIMD4(0, 2.0 / (top - bottom), 0, 0),
                SIMD4(0, 0, -2.0 / (far - near), 0),
                SIMD4(-(right + left) / (right - left),
                      -(top + bottom) / (top - bottom),
                      -(far + near) / (far - near),
                      1)
            )
        }

        // Create MVP buffer
        guard let mvpBuffer = device.makeBuffer(
            bytes: &finalMVP,
            length: MemoryLayout<matrix_float4x4>.stride,
            options: .storageModeShared
        ) else {
            throw SDFRendererError.bufferCreationFailed
        }

        // Create uniforms buffer
        var uniforms = SDFUniforms(
            color: color,
            edgeDistance: weight,
            edgeSoftness: 1.0 + softness,
            outlineColor: outlineColor,
            outlineWidth: outlineWidth,
            fadeStart: fadeStart,
            fadeEnd: fadeEnd
        )

        guard let uniformsBuffer = device.makeBuffer(
            bytes: &uniforms,
            length: MemoryLayout<SDFUniforms>.stride,
            options: .storageModeShared
        ) else {
            throw SDFRendererError.bufferCreationFailed
        }

        // Setup render pass
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = outputTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        // Create encoder using existing command buffer
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            throw SDFRendererError.encoderCreationFailed
        }

        // Set pipeline and buffers
        renderEncoder.setRenderPipelineState(pipeline)
        renderEncoder.setCullMode(.none) // Disable culling to ensure visibility regardless of winding
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(mvpBuffer, offset: 0, index: 1)
        renderEncoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)

        // Set SDF atlas texture (access cached texture reference)
        let atlasTexture = fontAtlas.texture
        renderEncoder.setFragmentTexture(atlasTexture, index: 0)

        // Use cached sampler
        renderEncoder.setFragmentSamplerState(samplerState, index: 0)

        // Draw all glyphs
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)

        renderEncoder.endEncoding()

        // Wait for GPU to complete rendering (add handler BEFORE commit)
        return await withCheckedContinuation { continuation in
            commandBuffer.addCompletedHandler { _ in
                continuation.resume(returning: outputTexture)
            }
            commandBuffer.commit()
        }
    }

    // MARK: - Layout & Measurement

    public enum TextAlignment: Sendable {
        case left
        case center
        case right
    }

    /// Measure text dimensions
    public nonisolated func measure(text: String, fontSize: Float = 0, tracking: Float = 0.0, scale: Float = 1.0) -> CGSize {
        // Calculate effective scale
        let effectiveScale: Float
        if fontSize > 0 {
            effectiveScale = fontSize / Float(fontAtlas.fontMetrics.generatedFontSize)
        } else {
            effectiveScale = scale
        }

        var width: Float = 0
        // Use font metrics for robust height calculation
        // Height = Ascent + Descent + Leading (optional)
        // We use ascent + descent to match the visual height of the line
        let height = Float(fontAtlas.fontMetrics.ascent + fontAtlas.fontMetrics.descent) * effectiveScale

        var xOffset: Float = 0

        // Calculate tracking in pixels
        let trackingPixels = tracking * Float(fontAtlas.fontMetrics.generatedFontSize) * effectiveScale

        for char in text {
            guard let metrics = glyphMetrics[char] else { continue }

            // Advance cursor using font metrics + tracking
            xOffset += (Float(metrics.advance) * effectiveScale) + trackingPixels
        }

        width = xOffset
        return CGSize(width: CGFloat(width), height: CGFloat(height))
    }

    /// Render text using SwissGrid layout
    public nonisolated func render(
        text: String,
        grid: SwissGrid,
        position: GridPosition,
        alignment: TextAlignment = .left,
        color: SIMD4<Float>,
        fontSize: Float = 0,
        weight: Float = 0.5,
        softness: Float = 0.0,
        outlineColor: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1),
        outlineWidth: Float = 0.0,
        tracking: Float = 0.0,
        scale: Float = 1.0,
        alphaType: AlphaType = .premultiplied
    ) async throws -> MTLTexture {
        // 1. Calculate anchor point from grid
        let anchorPoint = grid.point(for: position)

        // 2. Measure text for alignment
        let size = measure(text: text, fontSize: fontSize, tracking: tracking, scale: scale)

        // 3. Adjust X based on alignment
        var finalX = Float(anchorPoint.x)

        switch alignment {
        case .left:
            break // Anchor is left edge
        case .center:
            finalX -= Float(size.width) / 2.0
        case .right:
            finalX -= Float(size.width)
        }

        // 4. Render at calculated position
        return try await render(
            text: text,
            position: CGPoint(x: CGFloat(finalX), y: anchorPoint.y),
            color: color,
            fontSize: fontSize,
            weight: weight,
            softness: softness,
            outlineColor: outlineColor,
            outlineWidth: outlineWidth,
            tracking: tracking,
            scale: scale,
            alphaType: alphaType
        )
    }

    /// Render text using LayoutConstraint
    public nonisolated func render(
        text: String,
        grid: SwissGrid,
        constraint: LayoutConstraint,
        alignment: TextAlignment = .left,
        color: SIMD4<Float>,
        fontSize: Float = 0,
        weight: Float = 0.5,
        softness: Float = 0.0,
        outlineColor: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1),
        outlineWidth: Float = 0.0,
        tracking: Float = 0.0,
        scale: Float = 1.0,
        alphaType: AlphaType = .premultiplied
    ) async throws -> MTLTexture {
        // 1. Resolve constraint to point
        let anchorPoint = grid.resolve(constraint)

        // 2. Measure text for alignment
        let size = measure(text: text, fontSize: fontSize, tracking: tracking, scale: scale)

        // 3. Adjust X based on alignment
        var finalX = Float(anchorPoint.x)

        switch alignment {
        case .left:
            break // Anchor is left edge
        case .center:
            finalX -= Float(size.width) / 2.0
        case .right:
            finalX -= Float(size.width)
        }

        // 4. Render at calculated position
        return try await render(
            text: text,
            position: CGPoint(x: CGFloat(finalX), y: anchorPoint.y),
            color: color,
            fontSize: fontSize,
            weight: weight,
            softness: softness,
            outlineColor: outlineColor,
            outlineWidth: outlineWidth,
            tracking: tracking,
            scale: scale,
            alphaType: alphaType
        )
    }

    // MARK: - Batch Rendering

    public enum LabelLayoutMode: Sendable {
        case straight
        case circular(radius: Float, startAngle: Float)
    }

    public struct LabelRequest: Sendable {
        public let text: String
        public let position: CGPoint
        public let color: SIMD4<Float>
        public let fontSize: Float
        public let alignment: TextAlignment
        public let weight: Float
        public let softness: Float
        public let outlineColor: SIMD4<Float>
        public let outlineWidth: Float
        public let lineHeight: Float
        public let tracking: Float
        public let maxWidth: Float?
        public let layoutMode: LabelLayoutMode

        public init(
            text: String,
            position: CGPoint,
            color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1),
            fontSize: Float = 24,
            weight: Float = 0.5,
            softness: Float = 1.0,
            alignment: TextAlignment = .center,
            outlineColor: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1),
            outlineWidth: Float = 0.0,
            lineHeight: Float = 1.2,
            tracking: Float = 0.0,
            maxWidth: Float? = nil,
            layoutMode: LabelLayoutMode = .straight
        ) {
            self.text = text
            self.position = position
            self.color = color
            self.fontSize = fontSize
            self.weight = weight
            self.softness = softness
            self.alignment = alignment
            self.outlineColor = outlineColor
            self.outlineWidth = outlineWidth
            self.lineHeight = lineHeight
            self.tracking = tracking
            self.maxWidth = maxWidth
            self.layoutMode = layoutMode
        }
    }

    /// Render multiple labels into a single texture (efficient batching)
    public nonisolated func render(
        labels: [LabelRequest],
        width: Int = 1920,
        height: Int = 1080,
        clearColor: MTLClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    ) async throws -> MTLTexture {
        // Create command buffer first
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw SDFRendererError.commandBufferCreationFailed
        }

        // Create output texture
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.pixelFormat = pixelFormat
        textureDescriptor.width = width
        textureDescriptor.height = height
        textureDescriptor.usage = [.shaderRead, .renderTarget]
        textureDescriptor.storageMode = .shared

        guard let outputTexture = device.makeTexture(descriptor: textureDescriptor) else {
            throw SDFRendererError.textureCreationFailed
        }

        // Build vertex data for all labels
        struct Vertex {
            var position: SIMD2<Float>
            var texCoords: SIMD2<Float>
        }

        var allVertices: [Vertex] = []
        var drawCalls: [(vertexStart: Int, vertexCount: Int, color: SIMD4<Float>, weight: Float, softness: Float, outlineColor: SIMD4<Float>, outlineWidth: Float)] = []

        for label in labels {
            let startVertex = allVertices.count

            // Use Layout Engine
            let layout: TextLayoutEngine.LayoutResult

            switch label.layoutMode {
            case .straight:
                layout = layoutEngine.layout(
                    text: label.text,
                    position: SIMD2(Float(label.position.x), Float(label.position.y)),
                    fontSize: label.fontSize,
                    lineHeightMultiplier: label.lineHeight,
                    alignment: convertAlignment(label.alignment),
                    tracking: label.tracking,
                    scale: 1.0,
                    maxWidth: label.maxWidth
                )
                print("SDFTextRenderer: Layout bounds for '\(label.text.prefix(20))...': \(layout.bounds)")
            case let .circular(radius, startAngle):
                layout = layoutEngine.layoutCircular(
                    text: label.text,
                    center: SIMD2(Float(label.position.x), Float(label.position.y)),
                    radius: radius,
                    startAngle: startAngle,
                    fontSize: label.fontSize,
                    tracking: label.tracking,
                    scale: 1.0
                )
            }

            for glyph in layout.glyphs {
                // Handle rotation if present
                let x0 = glyph.position.x
                let y0 = glyph.position.y
                let w = glyph.size.x
                let h = glyph.size.y

                // Standard U coordinates (No flip)
                let u0 = glyph.texCoords.x
                let v0 = glyph.texCoords.y
                let u1 = glyph.texCoords.z
                let v1 = glyph.texCoords.w

                // If rotation is zero, use simple quad
                if glyph.rotation == 0 {
                    let x1 = x0 + w
                    let y1 = y0 + h

                    allVertices.append(contentsOf: [
                        Vertex(position: SIMD2(x0, y0), texCoords: SIMD2(u0, v0)),
                        Vertex(position: SIMD2(x1, y0), texCoords: SIMD2(u1, v0)),
                        Vertex(position: SIMD2(x0, y1), texCoords: SIMD2(u0, v1)),
                        Vertex(position: SIMD2(x1, y0), texCoords: SIMD2(u1, v0)),
                        Vertex(position: SIMD2(x1, y1), texCoords: SIMD2(u1, v1)),
                        Vertex(position: SIMD2(x0, y1), texCoords: SIMD2(u0, v1))
                    ])
                } else {
                    // Rotate around glyph center
                    // Wait, layoutCircular returns top-left position relative to rotation?
                    // No, we decided layoutCircular returns top-left position assuming no rotation,
                    // but we need to rotate around the baseline center?
                    // Let's revisit the math in layoutCircular.
                    // x = center.x + radius * sin(angle)
                    // y = center.y - radius * cos(angle)
                    // This (x,y) is the baseline center of the glyph.
                    // x0 = x - origin.x
                    // y0 = y - origin.y
                    // So (x0, y0) is the top-left corner if the glyph was upright at (x,y).
                    // We want to rotate the glyph around (x,y) by `rotation`.

                    // Pivot point
                    let metrics = glyphMetrics[glyph.character]!
                    let scale = label.fontSize / Float(fontAtlas.fontMetrics.generatedFontSize)
                    let originX = Float(metrics.origin.x) * scale
                    let originY = Float(metrics.origin.y) * scale

                    let pivotX = x0 + originX
                    let pivotY = y0 + originY

                    let c = cos(glyph.rotation)
                    let s = sin(glyph.rotation)

                    func rotate(_ p: SIMD2<Float>) -> SIMD2<Float> {
                        let dx = p.x - pivotX
                        let dy = p.y - pivotY
                        return SIMD2(
                            pivotX + dx * c - dy * s,
                            pivotY + dx * s + dy * c
                        )
                    }

                    let p0 = rotate(SIMD2(x0, y0))
                    let p1 = rotate(SIMD2(x0 + w, y0))
                    let p2 = rotate(SIMD2(x0, y0 + h))
                    let p3 = rotate(SIMD2(x0 + w, y0 + h))

                    allVertices.append(contentsOf: [
                        Vertex(position: p0, texCoords: SIMD2(u0, v0)),
                        Vertex(position: p1, texCoords: SIMD2(u1, v0)),
                        Vertex(position: p2, texCoords: SIMD2(u0, v1)),
                        Vertex(position: p1, texCoords: SIMD2(u1, v0)),
                        Vertex(position: p3, texCoords: SIMD2(u1, v1)),
                        Vertex(position: p2, texCoords: SIMD2(u0, v1))
                    ])
                }
            }

            let vertexCount = allVertices.count - startVertex
            if vertexCount > 0 {
                drawCalls.append((startVertex, vertexCount, label.color, label.weight, label.softness, label.outlineColor, label.outlineWidth))
            }
        }

        if allVertices.isEmpty {
            return outputTexture
        }

        // Create vertex buffer
        guard let vertexBuffer = device.makeBuffer(
            bytes: allVertices,
            length: allVertices.count * MemoryLayout<Vertex>.stride,
            options: .storageModeShared
        ) else {
            throw SDFRendererError.bufferCreationFailed
        }

        // MVP Matrix
        let left: Float = 0
        let right = Float(width)
        let bottom = Float(height)
        let top: Float = 0
        let near: Float = -1
        let far: Float = 1

        var mvpMatrix = matrix_float4x4(
            SIMD4(2.0 / (right - left), 0, 0, 0),
            SIMD4(0, 2.0 / (top - bottom), 0, 0),
            SIMD4(0, 0, -2.0 / (far - near), 0),
            SIMD4(-(right + left) / (right - left),
                  -(top + bottom) / (top - bottom),
                  -(far + near) / (far - near),
                  1)
        )

        guard let mvpBuffer = device.makeBuffer(bytes: &mvpMatrix, length: MemoryLayout<matrix_float4x4>.stride, options: .storageModeShared) else {
            throw SDFRendererError.bufferCreationFailed
        }

        // Setup render pass
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = outputTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = clearColor
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        // Create encoder using existing command buffer
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            throw SDFRendererError.encoderCreationFailed
        }

        // Set pipeline and static buffers
        renderEncoder.setRenderPipelineState(pipeline)
        renderEncoder.setCullMode(.none) // Disable culling to ensure visibility regardless of winding
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(mvpBuffer, offset: 0, index: 1)

        // Set atlas texture
        renderEncoder.setFragmentTexture(fontAtlas.texture, index: 0)

        // Use cached sampler
        renderEncoder.setFragmentSamplerState(samplerState, index: 0)

        // Draw calls
        for call in drawCalls {
            var uniforms = SDFUniforms(
                color: call.color,
                edgeDistance: call.weight,
                edgeSoftness: 1.0 + call.softness,
                outlineColor: call.outlineColor,
                outlineWidth: call.outlineWidth,
                fadeStart: 0.0,
                fadeEnd: 0.0
            )

            renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<SDFUniforms>.stride, index: 0)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: call.vertexStart, vertexCount: call.vertexCount)
        }

        renderEncoder.endEncoding()

        return await withCheckedContinuation { continuation in
            commandBuffer.addCompletedHandler { _ in
                continuation.resume(returning: outputTexture)
            }
            commandBuffer.commit()
        }
    }

    /// Render multiple labels using an existing render encoder (for compositing)
    public nonisolated func render(
        labels: [LabelRequest],
        encoder: MTLRenderCommandEncoder,
        screenSize: SIMD2<Float>,
        mvpMatrix: matrix_float4x4? = nil,
        fadeStart: Float = 0.0,
        fadeEnd: Float = 0.0
    ) throws {
        print("SDFTextRenderer: Rendering \(labels.count) labels")
        
        // Set Viewport
        let viewport = MTLViewport(originX: 0, originY: 0, width: Double(screenSize.x), height: Double(screenSize.y), znear: 0, zfar: 1)
        encoder.setViewport(viewport)
        
        encoder.setRenderPipelineState(pipeline)
        encoder.setCullMode(.none) // Disable culling
        encoder.setFragmentTexture(fontAtlas.texture, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)

        // Define Vertex struct matching the shader input
        struct Vertex {
            var position: SIMD2<Float>
            var texCoords: SIMD2<Float>
        }

        // MVP Matrix setup
        var finalMVP: matrix_float4x4
        
        if let providedMVP = mvpMatrix {
            finalMVP = providedMVP
        } else {
            let width = screenSize.x
            let height = screenSize.y
            let left: Float = 0
            let right = width
            let bottom = height
            let top: Float = 0
            let near: Float = -1
            let far: Float = 1

            finalMVP = matrix_float4x4(
                SIMD4(2.0 / (right - left), 0, 0, 0),
                SIMD4(0, 2.0 / (top - bottom), 0, 0),
                SIMD4(0, 0, -2.0 / (far - near), 0),
                SIMD4(-(right + left) / (right - left),
                      -(top + bottom) / (top - bottom),
                      -(far + near) / (far - near),
                      1)
            )
        }

        encoder.setVertexBytes(&finalMVP, length: MemoryLayout<matrix_float4x4>.stride, index: 1)

        for label in labels {
            // Use Layout Engine
            let layout: TextLayoutEngine.LayoutResult

            switch label.layoutMode {
            case .straight:
                layout = layoutEngine.layout(
                    text: label.text,
                    position: SIMD2(Float(label.position.x), Float(label.position.y)),
                    fontSize: label.fontSize,
                    lineHeightMultiplier: label.lineHeight,
                    alignment: convertAlignment(label.alignment),
                    tracking: label.tracking,
                    scale: 1.0,
                    maxWidth: label.maxWidth
                )
            case let .circular(radius, startAngle):
                layout = layoutEngine.layoutCircular(
                    text: label.text,
                    center: SIMD2(Float(label.position.x), Float(label.position.y)),
                    radius: radius,
                    startAngle: startAngle,
                    fontSize: label.fontSize,
                    tracking: label.tracking,
                    scale: 1.0
                )
            }

            var vertices: [Vertex] = []
            vertices.reserveCapacity(layout.glyphs.count * 6)

            for glyph in layout.glyphs {
                let x0 = glyph.position.x
                let y0 = glyph.position.y
                let w = glyph.size.x
                let h = glyph.size.y

                let u0 = glyph.texCoords.x
                let v0 = glyph.texCoords.y
                let u1 = glyph.texCoords.z
                let v1 = glyph.texCoords.w

                if glyph.rotation == 0 {
                    let x1 = x0 + w
                    let y1 = y0 + h

                    vertices.append(contentsOf: [
                        Vertex(position: SIMD2(x0, y0), texCoords: SIMD2(u0, v0)),
                        Vertex(position: SIMD2(x1, y0), texCoords: SIMD2(u1, v0)),
                        Vertex(position: SIMD2(x0, y1), texCoords: SIMD2(u0, v1)),
                        Vertex(position: SIMD2(x1, y0), texCoords: SIMD2(u1, v0)),
                        Vertex(position: SIMD2(x1, y1), texCoords: SIMD2(u1, v1)),
                        Vertex(position: SIMD2(x0, y1), texCoords: SIMD2(u0, v1))
                    ])
                } else {
                    // Rotation logic (duplicated for now, should be helper)
                    let metrics = glyphMetrics[glyph.character]!
                    let scale = label.fontSize / Float(fontAtlas.fontMetrics.generatedFontSize)
                    let originX = Float(metrics.origin.x) * scale
                    let originY = Float(metrics.origin.y) * scale

                    let pivotX = x0 + originX
                    let pivotY = y0 + originY

                    let c = cos(glyph.rotation)
                    let s = sin(glyph.rotation)

                    func rotate(_ p: SIMD2<Float>) -> SIMD2<Float> {
                        let dx = p.x - pivotX
                        let dy = p.y - pivotY
                        return SIMD2(
                            pivotX + dx * c - dy * s,
                            pivotY + dx * s + dy * c
                        )
                    }

                    let p0 = rotate(SIMD2(x0, y0))
                    let p1 = rotate(SIMD2(x0 + w, y0))
                    let p2 = rotate(SIMD2(x0, y0 + h))
                    let p3 = rotate(SIMD2(x0 + w, y0 + h))

                    vertices.append(contentsOf: [
                        Vertex(position: p0, texCoords: SIMD2(u0, v0)),
                        Vertex(position: p1, texCoords: SIMD2(u1, v0)),
                        Vertex(position: p2, texCoords: SIMD2(u0, v1)),
                        Vertex(position: p1, texCoords: SIMD2(u1, v0)),
                        Vertex(position: p3, texCoords: SIMD2(u1, v1)),
                        Vertex(position: p2, texCoords: SIMD2(u0, v1))
                    ])
                }
            }

            if !vertices.isEmpty {
                let size = vertices.count * MemoryLayout<Vertex>.stride
                if size < 4096 {
                    encoder.setVertexBytes(vertices, length: size, index: 0)
                } else {
                    guard let buffer = encoder.device.makeBuffer(bytes: vertices, length: size, options: .storageModeShared) else {
                        print("SDFTextRenderer: Failed to create vertex buffer")
                        continue
                    }
                    encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                }

                var uniforms = SDFUniforms(
                    color: label.color,
                    edgeDistance: label.weight,
                    edgeSoftness: 1.0 + label.softness,
                    outlineColor: label.outlineColor,
                    outlineWidth: label.outlineWidth,
                    fadeStart: fadeStart,
                    fadeEnd: fadeEnd
                )
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SDFUniforms>.stride, index: 0)

                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
            }
        }
    }
}

// MARK: - Errors

/// Errors that can occur during SDF rendering
public enum SDFRendererError: Error, LocalizedError {
    case notImplemented(String)
    case commandQueueCreationFailed
    case shaderCompilationFailed(String)
    case textureCreationFailed
    case bufferCreationFailed
    case commandBufferCreationFailed
    case samplerCreationFailed
    case pipelineCreationFailed(String)
    case encoderCreationFailed

    public var errorDescription: String? {
        switch self {
        case let .notImplemented(feature):
            return "Not implemented: \(feature)"
        case .commandQueueCreationFailed:
            return "Failed to create command queue"
        case let .shaderCompilationFailed(reason):
            return "Shader compilation failed: \(reason)"
        case .textureCreationFailed:
            return "Failed to create output texture"
        case .bufferCreationFailed:
            return "Failed to create Metal buffer"
        case .commandBufferCreationFailed:
            return "Failed to create command buffer or encoder"
        case .samplerCreationFailed:
            return "Failed to create sampler state"
        case let .pipelineCreationFailed(reason):
            return "Failed to create pipeline state: \(reason)"
        case .encoderCreationFailed:
            return "Failed to create render encoder"
        }
    }
}
