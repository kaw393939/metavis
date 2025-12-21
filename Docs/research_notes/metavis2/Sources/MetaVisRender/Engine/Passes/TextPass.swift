import Metal
import MetalKit
import simd

public struct TextStyle {
    public var color: SIMD4<Float>
    public var outlineColor: SIMD4<Float>
    public var outlineWidth: Float
    public var shadowColor: SIMD4<Float>
    public var shadowOffset: SIMD2<Float>
    public var shadowBlur: Float
    
    public init(color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1),
                outlineColor: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 0),
                outlineWidth: Float = 0.0,
                shadowColor: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 0),
                shadowOffset: SIMD2<Float> = SIMD2<Float>(0, 0),
                shadowBlur: Float = 0.0) {
        self.color = color
        self.outlineColor = outlineColor
        self.outlineWidth = outlineWidth
        self.shadowColor = shadowColor
        self.shadowOffset = shadowOffset
        self.shadowBlur = shadowBlur
    }
}

public struct TextDrawCommand {
    public let text: String
    public let position: SIMD3<Float>
    public let fontSize: CGFloat
    public let style: TextStyle
    public let fontID: FontID
    
    // Resolution-aware positioning
    public let anchor: TextAnchor
    public let alignment: TextAlignment
    public let positionMode: PositionMode
    
    public let rotation: SIMD3<Float>
    public let scale: SIMD3<Float>
    
    public init(
        text: String,
        position: SIMD3<Float>,
        fontSize: CGFloat,
        style: TextStyle,
        fontID: FontID,
        anchor: TextAnchor = .topLeft,
        alignment: TextAlignment = .left,
        positionMode: PositionMode = .absolute,
        rotation: SIMD3<Float> = .zero,
        scale: SIMD3<Float> = .one
    ) {
        self.text = text
        self.position = position
        self.fontSize = fontSize
        self.style = style
        self.fontID = fontID
        self.anchor = anchor
        self.alignment = alignment
        self.positionMode = positionMode
        self.rotation = rotation
        self.scale = scale
    }
    
    // Backwards compatibility init
    public init(text: String, position: CGPoint, fontSize: CGFloat, style: TextStyle, fontID: FontID) {
        self.init(
            text: text,
            position: SIMD3<Float>(Float(position.x), Float(position.y), 0),
            fontSize: fontSize,
            style: style,
            fontID: fontID,
            anchor: .topLeft,
            alignment: .left,
            positionMode: .absolute
        )
    }
    
    // Backwards compatibility init
    public init(text: String, position: CGPoint, fontSize: CGFloat, color: SIMD4<Float>, fontID: FontID) {
        self.init(
            text: text,
            position: SIMD3<Float>(Float(position.x), Float(position.y), 0),
            fontSize: fontSize,
            style: TextStyle(color: color),
            fontID: fontID,
            anchor: .topLeft,
            alignment: .left,
            positionMode: .absolute
        )
    }
}

struct TextVertex {
    var position: SIMD3<Float>
    var uv: SIMD2<Float>
}

struct TextUniforms {
    var projectionMatrix: matrix_float4x4
    var color: SIMD4<Float>
    var outlineColor: SIMD4<Float>
    var shadowColor: SIMD4<Float>
    var screenSize: SIMD2<Float>
    var shadowOffset: SIMD2<Float>
    var smoothing: Float
    var hasMask: Float
    var outlineWidth: Float
    var shadowBlur: Float
    var hasDepth: Float  // 0.0 = no depth test, 1.0 = depth test enabled
    var depthBias: Float // Small bias to prevent z-fighting
}

public class TextPass: RenderPass {
    public var label: String = "Text Pass"
    
    // Inputs
    public var maskTexture: MTLTexture?
    public var depthTexture: MTLTexture?
    
    private let glyphManager: GlyphManager
    private var pipelineState: MTLRenderPipelineState?
    private var commands: [TextDrawCommand] = []
    
    public init(glyphManager: GlyphManager) {
        self.glyphManager = glyphManager
    }
    
    public func setup(device: MTLDevice, library: MTLLibrary) throws {
        let vertexFunction = library.makeFunction(name: "sdf_text_vertex")
        let fragmentFunction = library.makeFunction(name: "sdf_text_fragment")
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "SDF Text Pipeline"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        
        // Alpha blending
        descriptor.colorAttachments[0].pixelFormat = .rgba16Float  // 16-bit float for HDR precision
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        
        // Vertex Descriptor
        let vertexDescriptor = MTLVertexDescriptor()
        // Position
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        // UV
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        vertexDescriptor.layouts[0].stride = MemoryLayout<TextVertex>.stride
        
        descriptor.vertexDescriptor = vertexDescriptor
        
        self.pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    public func add(command: TextDrawCommand) {
        commands.append(command)
    }
    
    public func execute(commandBuffer: MTLCommandBuffer, context: RenderContext) throws {
        guard let pipelineState = pipelineState,
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: context.renderPassDescriptor) else {
            return
        }
        
        encoder.label = label
        encoder.setRenderPipelineState(pipelineState)
        
        // Set Viewport
        let viewport = MTLViewport(originX: 0, originY: 0, width: Double(context.resolution.x), height: Double(context.resolution.y), znear: 0, zfar: 1)
        encoder.setViewport(viewport)
        
        // Bind Atlas
        if let atlas = glyphManager.getTexture() {
            encoder.setFragmentTexture(atlas, index: 0)
            print("DEBUG: TextPass bound Atlas texture: \(atlas.width)x\(atlas.height)")
        } else {
            print("CRITICAL ERROR: TextPass has NO Atlas Texture! This will result in solid blocks.")
        }
        
        // Bind Mask
        var hasMaskVal: Float = 0.0
        if let mask = maskTexture {
            encoder.setFragmentTexture(mask, index: 1)
            hasMaskVal = 1.0
        }
        
        // Bind Depth Texture for Occlusion
        var hasDepthVal: Float = 0.0
        if let depth = depthTexture {
            encoder.setFragmentTexture(depth, index: 2)
            hasDepthVal = 1.0
        }
        
        // Process commands
        // In a real engine, we'd batch these into a single buffer.
        // For simplicity, we'll draw one by one or batch per string.
        
        if commands.isEmpty {
            print("TextPass: No commands to draw")
        }
        
        let viewportSize = context.resolution
        
        // Use Camera from Scene if available, otherwise fallback to Ortho
        var projection: matrix_float4x4
        // Force Orthographic for now as TextPass logic (resolvePosition) is designed for Screen Space (pixels)
        // Using Perspective with pixel coordinates puts text way off screen.
        if context.scene.virtualCamera.fov > 0 {
            // Perspective
            let aspect = Float(viewportSize.x) / Float(viewportSize.y)
            let proj = context.scene.virtualCamera.projectionMatrix(aspectRatio: aspect)
            let view = context.scene.virtualCamera.viewMatrix
            
            // Combine
            // Metal is column-major. P * V * M * v
            projection = matrix_multiply(proj, view)
            
            // Debug print once per frame (or just once)
            if Float.random(in: 0...1) < 0.001 {
                print("Camera Pos: \(context.scene.virtualCamera.position)")
                print("Camera Target: \(context.scene.virtualCamera.target)")
                print("Projection: \(projection)")
            }
            
        } else {
            // Ortho (Legacy/2D)
            // Fix: Increase Z range to allow for depth layering even in Ortho mode
            projection = makeOrthographicMatrix(left: 0, right: Float(viewportSize.x),
                                                    bottom: Float(viewportSize.y), top: 0, // Top-left origin
                                                    near: -1000, far: 1000)
        }
        
        for command in commands {
            draw(command: command, encoder: encoder, projection: projection, viewportSize: SIMD2<Float>(Float(viewportSize.x), Float(viewportSize.y)), hasMask: hasMaskVal, hasDepth: hasDepthVal)
        }
        
        encoder.endEncoding()
        commands.removeAll() // Clear for next frame? Or keep? Usually clear.
    }
    
    private func draw(command: TextDrawCommand, encoder: MTLRenderCommandEncoder, projection: matrix_float4x4, viewportSize: SIMD2<Float>, hasMask: Float, hasDepth: Float) {
        // Generate Mesh
        var vertices: [TextVertex] = []
        
        // We need to scale the glyphs from the atlas size to the target font size.
        // The atlas glyphs are generated at a specific size (e.g. 64px).
        let referenceFontSize: CGFloat = 64.0
        let scale = Float(command.fontSize / referenceFontSize)
        
        let textureWidth = Float(glyphManager.getTexture()?.width ?? 2048)
        let textureHeight = Float(glyphManager.getTexture()?.height ?? 2048)
        
        // Split text into lines
        let lines = command.text.components(separatedBy: "\n")
        let lineHeight = Float(command.fontSize) * 1.4 // 1.4x line spacing
        
        // Measure text for anchor/alignment calculations
        let textBounds = measureText(command: command)
        
        // Resolve position based on anchor, alignment, and positionMode
        let resolvedPosition = resolvePosition(
            command: command,
            viewportSize: viewportSize,
            textBounds: textBounds
        )
        
        // Calculate individual line widths for alignment
        var lineWidths: [Float] = []
        for line in lines {
            var lineWidth: Float = 0
            for char in line {
                let font = glyphManager.getFont(id: command.fontID)
                guard let font = font else { continue }
                var uni = Array(String(char).utf16)
                var glyphIndex: CGGlyph = 0
                CTFontGetGlyphsForCharacters(font, &uni, &glyphIndex, 1)
                let id = GlyphID(fontID: command.fontID, index: glyphIndex)
                if let location = glyphManager.getGlyph(id: id) {
                    lineWidth += Float(location.metrics.advance) * scale
                }
            }
            lineWidths.append(lineWidth)
        }
        
        for (lineIndex, line) in lines.enumerated() {
            // Calculate line offset with alignment
            var cursor = resolvedPosition
            cursor.y += Float(lineIndex) * lineHeight
            
            // Apply alignment offset for this line
            let lineAlignOffset = alignmentOffset(
                for: command.alignment,
                lineWidth: lineWidths[lineIndex],
                maxWidth: textBounds.x
            )
            cursor.x += lineAlignOffset
            
            // Shift cursor to baseline (approximate ascender as fontSize)
            // This is needed because resolvePosition returns the top-left of the layout box,
            // but the vertex generation logic expects cursor to be at the baseline.
            cursor.y += Float(command.fontSize)
            
            for char in line {
                // Get Glyph ID
                let font = glyphManager.getFont(id: command.fontID)
                
                guard let font = font else { continue }
                var uni = Array(String(char).utf16)
                var glyphIndex: CGGlyph = 0
                CTFontGetGlyphsForCharacters(font, &uni, &glyphIndex, 1)
                
                let id = GlyphID(fontID: command.fontID, index: glyphIndex)
                
                // Get Atlas Location
                guard let location = glyphManager.getGlyph(id: id) else {
                    print("TextPass: Missing glyph for char '\(char)'")
                    continue
                }
                
                // Metrics from location
                let metrics = location.metrics
                
                // Padding used during generation
                let paddingVal: Float = 8.0
                
                let quadW = Float(location.region.width) * textureWidth * scale
                let quadH = Float(location.region.height) * textureHeight * scale
                
                let bearingX = Float(metrics.bounds.origin.x) * scale
                let bearingY = Float(metrics.bounds.origin.y) * scale
                let boundsH = Float(metrics.bounds.height) * scale
                let scaledPadding = paddingVal * scale
                
                let x = Float(cursor.x) + bearingX - scaledPadding
                let y = Float(cursor.y) - (bearingY + boundsH) - scaledPadding
                let z = Float(cursor.z)
                
                let l = x
                let r = x + quadW
                let t = y
                let b = y + quadH
                
                // UVs
                let ul = Float(location.region.minX)
                let ur = Float(location.region.maxX)
                let vt = Float(location.region.minY)
                let vb = Float(location.region.maxY)
                
                // Apply Rotation and Scale
                let rad = command.rotation * .pi / 180.0
                let q = simd_quatf(angle: rad.x, axis: SIMD3(1,0,0)) * 
                        simd_quatf(angle: rad.y, axis: SIMD3(0,1,0)) * 
                        simd_quatf(angle: rad.z, axis: SIMD3(0,0,1))
                
                func transform(_ p: SIMD3<Float>) -> SIMD3<Float> {
                    var local = p - command.position
                    local *= command.scale
                    local = q.act(local)
                    return local + command.position
                }
                
                vertices.append(TextVertex(position: transform(SIMD3(l, t, z)), uv: SIMD2(ul, vt))) // TL
                vertices.append(TextVertex(position: transform(SIMD3(r, b, z)), uv: SIMD2(ur, vb))) // BR
                vertices.append(TextVertex(position: transform(SIMD3(l, b, z)), uv: SIMD2(ul, vb))) // BL
                
                vertices.append(TextVertex(position: transform(SIMD3(l, t, z)), uv: SIMD2(ul, vt))) // TL
                vertices.append(TextVertex(position: transform(SIMD3(r, t, z)), uv: SIMD2(ur, vt))) // TR
                vertices.append(TextVertex(position: transform(SIMD3(r, b, z)), uv: SIMD2(ur, vb))) // BR
                
                cursor.x += Float(metrics.advance) * scale
            }
        }
        
        guard !vertices.isEmpty else { return }
        
        // Upload vertices
        // In real engine, use a dynamic buffer ring.
        let vertexSize = vertices.count * MemoryLayout<TextVertex>.stride
        guard let vertexBuffer = encoder.device.makeBuffer(bytes: vertices, length: vertexSize, options: []) else { return }
        
        // Calculate UV Offset for Shadow
        // 1 pixel in screen space = (1 / (textureDim * scale)) in UV space
        let uvScaleX = 1.0 / (textureWidth * scale)
        let uvScaleY = 1.0 / (textureHeight * scale)
        
        // We want to sample at P - Offset. So we shift UV by -Offset * Scale.
        let shadowUVOffset = SIMD2<Float>(
            -command.style.shadowOffset.x * uvScaleX,
            -command.style.shadowOffset.y * uvScaleY
        )
        
        // Uniforms
        var uniforms = TextUniforms(
            projectionMatrix: projection,
            color: command.style.color,
            outlineColor: command.style.outlineColor,
            shadowColor: command.style.shadowColor,
            screenSize: viewportSize,
            shadowOffset: shadowUVOffset,
            smoothing: 0.1, // Fixed smoothing for now
            hasMask: hasMask,
            outlineWidth: command.style.outlineWidth,
            shadowBlur: command.style.shadowBlur,
            hasDepth: hasDepth,
            depthBias: 0.001 // Small bias to prevent z-fighting
        )
        
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<TextUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<TextUniforms>.stride, index: 1)
        
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }
    
    private func makeOrthographicMatrix(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> matrix_float4x4 {
        let ral = right + left
        let rsl = right - left
        let tab = top + bottom
        let tsb = top - bottom
        let fan = far + near
        let fsn = far - near
        
        return matrix_float4x4(columns: (
            SIMD4<Float>(2.0 / rsl, 0.0, 0.0, 0.0),
            SIMD4<Float>(0.0, 2.0 / tsb, 0.0, 0.0),
            SIMD4<Float>(0.0, 0.0, -2.0 / fsn, 0.0),
            SIMD4<Float>(-ral / rsl, -tab / tsb, -fan / fsn, 1.0)
        ))
    }
    
    private func degreesToRadians(_ degrees: Float) -> Float {
        return degrees * .pi / 180.0
    }
    
    private func makePerspectiveMatrix(fovyRadians: Float, aspect: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
        let ys = 1 / tanf(fovyRadians * 0.5)
        let xs = ys / aspect
        let zs = farZ / (nearZ - farZ)
        
        // Negate both xs and ys to correct for text coordinate system
        // (text is generated with Y-down screen coordinates, camera uses Y-up)
        return matrix_float4x4(columns: (
            SIMD4<Float>(-xs, 0, 0, 0),
            SIMD4<Float>(0, -ys, 0, 0),
            SIMD4<Float>(0, 0, zs, -1),
            SIMD4<Float>(0, 0, zs * nearZ, 0)
        ))
    }
    
    private func makeLookAtMatrix(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> matrix_float4x4 {
        let z = normalize(eye - target)
        let x = normalize(cross(up, z))
        let y = cross(z, x)
        
        // Negate x to correct horizontal mirroring
        return matrix_float4x4(columns: (
            SIMD4<Float>(-x.x, y.x, z.x, 0),
            SIMD4<Float>(-x.y, y.y, z.y, 0),
            SIMD4<Float>(-x.z, y.z, z.z, 0),
            SIMD4<Float>(dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
        ))
    }
    
    private func matrix_multiply(_ left: matrix_float4x4, _ right: matrix_float4x4) -> matrix_float4x4 {
        return simd_mul(left, right)
    }
    
    // MARK: - Resolution-Aware Positioning
    
    /// Resolves the final pixel position from anchor, alignment, and positionMode
    /// - Parameters:
    ///   - command: The text draw command with positioning data
    ///   - viewportSize: Current render target resolution
    ///   - textBounds: The width/height of the rendered text (pre-calculated)
    /// - Returns: The top-left corner position in pixel coordinates
    private func resolvePosition(
        command: TextDrawCommand,
        viewportSize: SIMD2<Float>,
        textBounds: SIMD2<Float>
    ) -> SIMD3<Float> {
        var pos = command.position
        
        // Step 1: Convert normalized to absolute if needed
        if command.positionMode == .normalized {
            pos.x = pos.x * viewportSize.x
            pos.y = pos.y * viewportSize.y
            // Z stays as-is (depth value)
        }
        
        // Step 2: Apply anchor offset
        // The position specifies where the anchor point of the text should be.
        // We need to offset so the top-left corner is at the right place.
        let anchorOffset = anchorOffset(for: command.anchor, textBounds: textBounds)
        pos.x -= anchorOffset.x
        pos.y -= anchorOffset.y
        
        return pos
    }
    
    /// Calculates the offset from top-left corner to the anchor point
    private func anchorOffset(for anchor: TextAnchor, textBounds: SIMD2<Float>) -> SIMD2<Float> {
        let w = textBounds.x
        let h = textBounds.y
        
        switch anchor {
        case .topLeft:      return SIMD2(0, 0)
        case .topCenter:    return SIMD2(w / 2, 0)
        case .topRight:     return SIMD2(w, 0)
        case .centerLeft:   return SIMD2(0, h / 2)
        case .center:       return SIMD2(w / 2, h / 2)
        case .centerRight:  return SIMD2(w, h / 2)
        case .bottomLeft:   return SIMD2(0, h)
        case .bottomCenter: return SIMD2(w / 2, h)
        case .bottomRight:  return SIMD2(w, h)
        }
    }
    
    /// Measures the bounding box of a text command
    private func measureText(command: TextDrawCommand) -> SIMD2<Float> {
        let referenceFontSize: CGFloat = 64.0
        let scale = Float(command.fontSize / referenceFontSize)
        
        let lines = command.text.components(separatedBy: "\n")
        let lineHeight = Float(command.fontSize) * 1.4
        
        var maxWidth: Float = 0
        
        for line in lines {
            var lineWidth: Float = 0
            
            for char in line {
                let font = glyphManager.getFont(id: command.fontID)
                guard let font = font else { continue }
                
                var uni = Array(String(char).utf16)
                var glyphIndex: CGGlyph = 0
                CTFontGetGlyphsForCharacters(font, &uni, &glyphIndex, 1)
                
                let id = GlyphID(fontID: command.fontID, index: glyphIndex)
                
                if let location = glyphManager.getGlyph(id: id) {
                    lineWidth += Float(location.metrics.advance) * scale
                }
            }
            
            maxWidth = max(maxWidth, lineWidth)
        }
        
        let totalHeight = Float(lines.count) * lineHeight
        
        return SIMD2(maxWidth, totalHeight)
    }
    
    /// Calculates the X offset for a line based on alignment
    private func alignmentOffset(for alignment: TextAlignment, lineWidth: Float, maxWidth: Float) -> Float {
        switch alignment {
        case .left:   return 0
        case .center: return (maxWidth - lineWidth) / 2
        case .right:  return maxWidth - lineWidth
        }
    }
}
