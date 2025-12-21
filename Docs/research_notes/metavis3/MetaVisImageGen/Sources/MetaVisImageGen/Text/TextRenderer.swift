import Metal
import MetalKit
import simd
import CoreText

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
    public let rotation: SIMD3<Float>
    public let scale: SIMD3<Float>
    
    public init(
        text: String,
        position: SIMD3<Float>,
        fontSize: CGFloat,
        style: TextStyle,
        fontID: FontID,
        rotation: SIMD3<Float> = .zero,
        scale: SIMD3<Float> = .one
    ) {
        self.text = text
        self.position = position
        self.fontSize = fontSize
        self.style = style
        self.fontID = fontID
        self.rotation = rotation
        self.scale = scale
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
    var hasDepth: Float
    var depthBias: Float
}

public class TextRenderer {
    private let device: MTLDevice
    private let glyphManager: GlyphManager
    private var pipelineState: MTLRenderPipelineState?
    
    public init(device: MTLDevice, glyphManager: GlyphManager, library: MTLLibrary? = nil) throws {
        self.device = device
        self.glyphManager = glyphManager
        try setup(library: library)
    }
    
    private func setup(library: MTLLibrary?) throws {
        // Use provided library or fallback to default
        var lib = library
        
        if lib == nil {
            /*
            if let bundlePath = Bundle.module.resourcePath {
                 lib = try? device.makeDefaultLibrary(bundle: Bundle.module)
            }
            */
        }
        if lib == nil {
            lib = device.makeDefaultLibrary()
        }
        
        guard let library = lib else {
            print("TextRenderer: Failed to load default library")
            return
        }
        
        guard let vertexFunction = library.makeFunction(name: "sdf_text_vertex"),
              let fragmentFunction = library.makeFunction(name: "sdf_text_fragment") else {
            print("TextRenderer: Failed to find shader functions")
            return
        }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "SDF Text Pipeline"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        
        // Alpha blending
        descriptor.colorAttachments[0].pixelFormat = .rgba16Float // ACEScg Linear
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        
        // Vertex Descriptor
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<TextVertex>.stride
        
        descriptor.vertexDescriptor = vertexDescriptor
        
        self.pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    public func render(command: TextDrawCommand, to texture: MTLTexture, projection: matrix_float4x4) {
        guard let pipelineState = pipelineState else { return }
        
        let commandBuffer = device.makeCommandQueue()?.makeCommandBuffer()
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .load // Keep existing content
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        guard let encoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        
        encoder.setRenderPipelineState(pipelineState)
        
        if let atlas = glyphManager.getTexture() {
            encoder.setFragmentTexture(atlas, index: 0)
        }
        
        draw(command: command, encoder: encoder, projection: projection, viewportSize: SIMD2<Float>(Float(texture.width), Float(texture.height)))
        
        encoder.endEncoding()
        commandBuffer?.commit()
        commandBuffer?.waitUntilCompleted()
    }
    
    private func draw(command: TextDrawCommand, encoder: MTLRenderCommandEncoder, projection: matrix_float4x4, viewportSize: SIMD2<Float>) {
        var vertices: [TextVertex] = []
        
        let referenceFontSize: CGFloat = 64.0
        let scale = Float(command.fontSize / referenceFontSize)
        let textureWidth = Float(glyphManager.getTexture()?.width ?? 2048)
        let textureHeight = Float(glyphManager.getTexture()?.height ?? 2048)
        
        var cursor = command.position
        
        // Simple single line support for now
        for char in command.text {
            guard let font = glyphManager.getFont(id: command.fontID) else { continue }
            var uni = Array(String(char).utf16)
            var glyphIndex: CGGlyph = 0
            CTFontGetGlyphsForCharacters(font, &uni, &glyphIndex, 1)
            
            let id = GlyphID(fontID: command.fontID, index: glyphIndex)
            guard let location = glyphManager.getGlyph(id: id) else { continue }
            
            let metrics = location.metrics
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
            
            let ul = Float(location.region.minX)
            let ur = Float(location.region.maxX)
            let vt = Float(location.region.minY)
            let vb = Float(location.region.maxY)
            
            // Apply Rotation (Simple Euler)
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
            
            vertices.append(TextVertex(position: transform(SIMD3(l, t, z)), uv: SIMD2(ul, vt)))
            vertices.append(TextVertex(position: transform(SIMD3(r, b, z)), uv: SIMD2(ur, vb)))
            vertices.append(TextVertex(position: transform(SIMD3(l, b, z)), uv: SIMD2(ul, vb)))
            
            vertices.append(TextVertex(position: transform(SIMD3(l, t, z)), uv: SIMD2(ul, vt)))
            vertices.append(TextVertex(position: transform(SIMD3(r, t, z)), uv: SIMD2(ur, vt)))
            vertices.append(TextVertex(position: transform(SIMD3(r, b, z)), uv: SIMD2(ur, vb)))
            
            cursor.x += Float(metrics.advance) * scale
        }
        
        guard !vertices.isEmpty else {
            print("TextRenderer: No vertices generated for text '\(command.text)'")
            return
        }
        
        // print("TextRenderer: Generated \(vertices.count) vertices for '\(command.text)'")
        
        let vertexSize = vertices.count * MemoryLayout<TextVertex>.stride
        guard let vertexBuffer = encoder.device.makeBuffer(bytes: vertices, length: vertexSize, options: []) else { return }
        
        var uniforms = TextUniforms(
            projectionMatrix: projection,
            color: command.style.color,
            outlineColor: command.style.outlineColor,
            shadowColor: command.style.shadowColor,
            screenSize: viewportSize,
            shadowOffset: command.style.shadowOffset,
            smoothing: 0.0, // Calculated in shader
            hasMask: 0.0,
            outlineWidth: command.style.outlineWidth,
            shadowBlur: command.style.shadowBlur,
            hasDepth: 0.0,
            depthBias: 0.0
        )
        
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<TextUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<TextUniforms>.stride, index: 1)
        
        // Bind texture AFTER generating glyphs (in case it was resized/created)
        if let atlas = glyphManager.getTexture() {
            encoder.setFragmentTexture(atlas, index: 0)
        }
        
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }
}

// Helper for Ortho Matrix
public func makeOrthographicMatrix(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> matrix_float4x4 {
    let ral = right + left
    let rsl = right - left
    let tab = top + bottom
    let tsb = top - bottom
    let fan = far + near
    let fsn = far - near
    
    return matrix_float4x4(columns: (
        SIMD4<Float>(2.0 / rsl, 0.0, 0.0, 0.0),
        SIMD4<Float>(0.0, 2.0 / tsb, 0.0, 0.0),
        SIMD4<Float>(0.0, 0.0, 1.0 / fsn, 0.0),
        SIMD4<Float>(-ral / rsl, -tab / tsb, -near / fsn, 1.0)
    ))
}
