import CoreGraphics
import CoreText
import Metal
import simd

/// Renders text as vector geometry (tessellated meshes) for infinite resolution.
/// Used for "Hero" text and high-zoom scenarios.
public final class VectorTextRenderer: @unchecked Sendable {
    private let device: MTLDevice
    private let pipeline: MTLRenderPipelineState
    private let depthStencilState: MTLDepthStencilState

    // Cache: FontName_Weight_GlyphID -> Mesh
    private struct CacheKey: Hashable {
        let fontName: String
        let weight: Float
        let glyphID: CGGlyph
    }

    private var meshCache: [CacheKey: GlyphMesh] = [:]
    private let lock = NSLock()

    public init(device: MTLDevice, pixelFormat: MTLPixelFormat = .rgba16Float) throws {
        self.device = device

        // Load the Vector Mesh shader
        let library: MTLLibrary
        if let defaultLib = device.makeDefaultLibrary() {
            library = defaultLib
        } else {
            // Fallback
            let source = try String(contentsOfFile: "Sources/MetalVisCore/Shaders/Vector.metal", encoding: .utf8)
            library = try device.makeLibrary(source: source, options: nil)
        }

        guard let vertexFunction = library.makeFunction(name: "vector_mesh_vertex"),
              let fragmentFunction = library.makeFunction(name: "vector_mesh_fragment")
        else {
            throw VectorRendererError.shaderCompilationFailed("Could not find vector mesh shader functions")
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha

        // Enable Depth Testing
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float

        // Vertex Descriptor (Matches MeshVertexIn)
        // Stride 32: Pos(12) + Normal(12) + UV(8)
        let vertexDescriptor = MTLVertexDescriptor()

        // Position (float3)
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0

        // Normal (float3)
        vertexDescriptor.attributes[1].format = .float3
        vertexDescriptor.attributes[1].offset = 12
        vertexDescriptor.attributes[1].bufferIndex = 0

        // UV (float2)
        vertexDescriptor.attributes[2].format = .float2
        vertexDescriptor.attributes[2].offset = 24
        vertexDescriptor.attributes[2].bufferIndex = 0

        vertexDescriptor.layouts[0].stride = 32
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        pipelineDescriptor.vertexDescriptor = vertexDescriptor

        pipeline = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)

        // Create Depth Stencil State
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .lessEqual
        depthDescriptor.isDepthWriteEnabled = true
        guard let dss = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            throw VectorRendererError.shaderCompilationFailed("Could not create depth stencil state")
        }
        depthStencilState = dss
    }

    public func clearCache() {
        lock.lock()
        meshCache.removeAll()
        lock.unlock()
    }

    // MARK: - Rendering

    public enum TextAlignment {
        case left
        case center
        case right
    }

    public func render(
        text: String,
        fontName: String,
        fontSize: Float,
        color: SIMD3<Float>,
        roughness: Float = 0.5,
        metallic: Float = 0.0,
        extrusionDepth: Float = 0.0,
        position: CGPoint,
        rotation: Float = 0.0,
        scale: SIMD3<Float> = SIMD3<Float>(1, 1, 1),
        alignment: TextAlignment = .left,
        into encoder: MTLRenderCommandEncoder,
        screenSize: SIMD2<Float>
    ) {
        // 1. Create CTFont
        let ctFont = CTFontCreateWithName(fontName as CFString, CGFloat(fontSize), nil)

        // 2. Layout (Get Glyphs & Positions)
        let attrString = NSAttributedString(string: text, attributes: [.font: ctFont])
        let line = CTLineCreateWithAttributedString(attrString)
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]

        // Calculate total width for alignment
        let lineWidth = Float(CTLineGetTypographicBounds(line, nil, nil, nil))
        // print("VectorTextRenderer: Text '\(text)' Width: \(lineWidth)")

        var xOffset: Float = 0
        switch alignment {
        case .left: xOffset = 0
        case .center: xOffset = -lineWidth / 2
        case .right: xOffset = -lineWidth
        }

        // 3. Render Each Glyph
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthStencilState)

        // Setup Matrices
        let width = screenSize.x
        let height = screenSize.y
        // Adjust near/far planes to accommodate extrusion
        let projectionMatrix = makeOrthographicMatrix(left: 0, right: width, bottom: height, top: 0, near: -2000, far: 2000)
        let viewMatrix = matrix_identity_float4x4

        // Pre-calculate rotation matrix
        let rotationMatrix = matrix_rotation_z(radians: rotation * .pi / 180.0)

        for run in runs {
            let glyphCount = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
            var positions = [CGPoint](repeating: .zero, count: glyphCount)
            CTRunGetGlyphs(run, CFRangeMake(0, 0), &glyphs)
            CTRunGetPositions(run, CFRangeMake(0, 0), &positions)

            for i in 0 ..< glyphCount {
                let glyph = glyphs[i]
                let pos = positions[i]

                // print("VectorTextRenderer: Glyph \(glyph) at \(pos)")

                // Get or Create Mesh
                if let mesh = getMesh(for: glyph, font: ctFont, fontName: fontName) {
                    // Calculate Transform for this glyph
                    // Apply offset relative to the text block origin
                    let glyphX = xOffset + Float(pos.x)
                    let glyphY = Float(pos.y)

                    // Apply rotation to the glyph position relative to the text block origin (0,0)
                    // Then translate to the final position
                    let rotatedPos = rotationMatrix * SIMD4<Float>(glyphX, glyphY, 0, 1)

                    let finalX = Float(position.x) + rotatedPos.x
                    let finalY = Float(position.y) + rotatedPos.y

                    // CTFontCreatePathForGlyph returns paths already scaled to the font size
                    // So we just need to flip Y for Metal coordinate system
                    let baseScale: Float = 1.0

                    var modelMatrix = matrix_identity_float4x4
                    modelMatrix = matrix_multiply(modelMatrix, matrix_translation(finalX, finalY, 0))
                    modelMatrix = matrix_multiply(modelMatrix, rotationMatrix) // Rotate the glyph itself
                    modelMatrix = matrix_multiply(modelMatrix, matrix_scale(baseScale * scale.x, -baseScale * scale.y, extrusionDepth > 0 ? extrusionDepth * scale.z : 1.0))

                    // Uniforms
                    var uniforms = MeshUniforms(
                        projectionMatrix: projectionMatrix,
                        viewMatrix: viewMatrix,
                        modelMatrix: modelMatrix,
                        color: color,
                        roughness: roughness,
                        metallic: metallic
                    )

                    encoder.setVertexBytes(&uniforms, length: MemoryLayout<MeshUniforms>.stride, index: 1)
                    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MeshUniforms>.stride, index: 1)

                    if let buffer = mesh.vertexBuffer {
                        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: mesh.vertexCount)
                    }
                }
            }
        }
    }

    // MARK: - Mesh Generation

    private func getMesh(for glyph: CGGlyph, font: CTFont, fontName: String) -> GlyphMesh? {
        let key = CacheKey(fontName: fontName, weight: 0, glyphID: glyph)

        lock.lock()
        if let mesh = meshCache[key] {
            lock.unlock()
            return mesh
        }
        lock.unlock()

        // Generate
        guard let path = CTFontCreatePathForGlyph(font, glyph, nil) else { return nil }
        let flattened = PathFlattener.flatten(path: path)
        let triangles = Triangulator.triangulate(polygons: flattened)

        guard !triangles.isEmpty else { return nil }

        var vertices: [VectorVertex] = []

        // 1. Front Face (Z = 0)
        let frontNormal = SIMD3<Float>(0, 0, 1)
        for tri in triangles {
            for p in [tri.p0, tri.p1, tri.p2] {
                vertices.append(VectorVertex(
                    position: SIMD3(Float(p.x), Float(p.y), 0.0),
                    normal: frontNormal,
                    texCoord: SIMD2(Float(p.x), Float(p.y))
                ))
            }
        }

        // 2. Back Face (Z = -1)
        // We reverse the winding order for the back face so it points backwards
        let backNormal = SIMD3<Float>(0, 0, -1)
        for tri in triangles {
            // Reverse order: p2, p1, p0
            for p in [tri.p2, tri.p1, tri.p0] {
                vertices.append(VectorVertex(
                    position: SIMD3(Float(p.x), Float(p.y), -1.0),
                    normal: backNormal,
                    texCoord: SIMD2(Float(p.x), Float(p.y))
                ))
            }
        }

        // 3. Side Walls (Extrusion)
        // Iterate over all polygons (outer + holes)
        for poly in flattened {
            for i in 0 ..< poly.count {
                let p1 = poly[i]
                let p2 = poly[(i + 1) % poly.count]

                // Skip zero-length edges
                if hypot(p2.x - p1.x, p2.y - p1.y) < 0.001 { continue }

                // Calculate Normal
                // Edge vector: p2 - p1
                // Extrusion vector: (0, 0, -1)
                // Normal = cross(edge, extrusion)
                let edge = SIMD3<Float>(Float(p2.x - p1.x), Float(p2.y - p1.y), 0)
                let extrusion = SIMD3<Float>(0, 0, -1)
                let normal = normalize(cross(edge, extrusion))

                // Quad Vertices
                // v0: p1, z=0
                // v1: p2, z=0
                // v2: p2, z=-1
                // v3: p1, z=-1

                let v0 = SIMD3<Float>(Float(p1.x), Float(p1.y), 0.0)
                let v1 = SIMD3<Float>(Float(p2.x), Float(p2.y), 0.0)
                let v2 = SIMD3<Float>(Float(p2.x), Float(p2.y), -1.0)
                let v3 = SIMD3<Float>(Float(p1.x), Float(p1.y), -1.0)

                // Triangle 1: v0, v1, v2
                vertices.append(VectorVertex(position: v0, normal: normal, texCoord: .zero))
                vertices.append(VectorVertex(position: v1, normal: normal, texCoord: .zero))
                vertices.append(VectorVertex(position: v2, normal: normal, texCoord: .zero))

                // Triangle 2: v0, v2, v3
                vertices.append(VectorVertex(position: v0, normal: normal, texCoord: .zero))
                vertices.append(VectorVertex(position: v2, normal: normal, texCoord: .zero))
                vertices.append(VectorVertex(position: v3, normal: normal, texCoord: .zero))
            }
        }

        let mesh = GlyphMesh(vertexBuffer: device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<VectorVertex>.stride, options: .storageModeShared), vertexCount: vertices.count, vertices: vertices)

        lock.lock()
        meshCache[key] = mesh
        lock.unlock()

        return mesh
    }

    // MARK: - Helpers

    private func makeOrthographicMatrix(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> matrix_float4x4 {
        let ral = right + left
        let rsl = right - left
        let tab = top + bottom
        let tsb = top - bottom
        let fan = far + near
        let fsn = far - near

        return matrix_float4x4(
            SIMD4(2.0 / rsl, 0, 0, 0),
            SIMD4(0, 2.0 / tsb, 0, 0),
            SIMD4(0, 0, -2.0 / fsn, 0),
            SIMD4(-ral / rsl, -tab / tsb, -fan / fsn, 1)
        )
    }

    private func matrix_translation(_ x: Float, _ y: Float, _ z: Float) -> matrix_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(x, y, z, 1)
        return m
    }

    private func matrix_scale(_ x: Float, _ y: Float, _ z: Float) -> matrix_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.0.x = x
        m.columns.1.y = y
        m.columns.2.z = z
        return m
    }

    private func matrix_rotation_z(radians: Float) -> matrix_float4x4 {
        let c = cos(radians)
        let s = sin(radians)

        var m = matrix_identity_float4x4
        m.columns.0.x = c
        m.columns.0.y = s
        m.columns.1.x = -s
        m.columns.1.y = c
        return m
    }
}

// MARK: - Supporting Types

struct GlyphMesh {
    let vertexBuffer: MTLBuffer?
    let vertexCount: Int
    let vertices: [VectorVertex]
}

struct VectorVertex {
    var px, py, pz: Float
    var nx, ny, nz: Float
    var u, v: Float

    init(position: SIMD3<Float>, normal: SIMD3<Float>, texCoord: SIMD2<Float>) {
        px = position.x
        py = position.y
        pz = position.z
        nx = normal.x
        ny = normal.y
        nz = normal.z
        u = texCoord.x
        v = texCoord.y
    }
}

struct MeshUniforms {
    var projectionMatrix: matrix_float4x4
    var viewMatrix: matrix_float4x4
    var modelMatrix: matrix_float4x4
    var color: SIMD3<Float>
    var roughness: Float
    var metallic: Float
}

// MARK: - Path Flattening & Triangulation

enum PathFlattener {
    static func flatten(path: CGPath) -> [[CGPoint]] {
        var polygons: [[CGPoint]] = []
        var currentPoly: [CGPoint] = []

        path.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                if !currentPoly.isEmpty { polygons.append(currentPoly) }
                currentPoly = [points[0]]
            case .addLineToPoint:
                currentPoly.append(points[0])
            case .addQuadCurveToPoint:
                let start = currentPoly.last ?? .zero
                let control = points[0]
                let end = points[1]
                currentPoly.append(contentsOf: subdivideQuad(start, control, end))
            case .addCurveToPoint:
                let start = currentPoly.last ?? .zero
                let c1 = points[0]
                let c2 = points[1]
                let end = points[2]
                currentPoly.append(contentsOf: subdivideCubic(start, c1, c2, end))
            case .closeSubpath:
                if !currentPoly.isEmpty {
                    if currentPoly.first != currentPoly.last {
                        currentPoly.append(currentPoly[0])
                    }
                    polygons.append(currentPoly)
                    currentPoly = []
                }
            @unknown default: break
            }
        }
        if !currentPoly.isEmpty { polygons.append(currentPoly) }
        return polygons
    }

    static func subdivideQuad(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, tolerance: CGFloat = 0.5) -> [CGPoint] {
        let midBase = CGPoint(x: (p0.x + p2.x) / 2, y: (p0.y + p2.y) / 2)
        let dist = hypot(p1.x - midBase.x, p1.y - midBase.y)

        if dist < tolerance {
            return [p2]
        }

        let p01 = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
        let p12 = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
        let p012 = CGPoint(x: (p01.x + p12.x) / 2, y: (p01.y + p12.y) / 2)

        return subdivideQuad(p0, p01, p012, tolerance: tolerance) + subdivideQuad(p012, p12, p2, tolerance: tolerance)
    }

    static func subdivideCubic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, tolerance: CGFloat = 0.5) -> [CGPoint] {
        let mid = CGPoint(x: (p0.x + p3.x) / 2, y: (p0.y + p3.y) / 2)
        let d1 = hypot(p1.x - mid.x, p1.y - mid.y)
        let d2 = hypot(p2.x - mid.x, p2.y - mid.y)

        if (d1 + d2) < tolerance {
            return [p3]
        }

        let p01 = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
        let p12 = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
        let p23 = CGPoint(x: (p2.x + p3.x) / 2, y: (p2.y + p3.y) / 2)

        let p012 = CGPoint(x: (p01.x + p12.x) / 2, y: (p01.y + p12.y) / 2)
        let p123 = CGPoint(x: (p12.x + p23.x) / 2, y: (p12.y + p23.y) / 2)

        let p0123 = CGPoint(x: (p012.x + p123.x) / 2, y: (p012.y + p123.y) / 2)

        return subdivideCubic(p0, p01, p012, p0123, tolerance: tolerance) + subdivideCubic(p0123, p123, p23, p3, tolerance: tolerance)
    }
}

struct Triangle {
    let p0, p1, p2: CGPoint
}

enum Triangulator {
    static func triangulate(polygons: [[CGPoint]]) -> [Triangle] {
        var contours = polygons.map { poly -> (poly: [CGPoint], area: CGFloat) in
            var area: CGFloat = 0
            for i in 0 ..< poly.count {
                let p1 = poly[i]
                let p2 = poly[(i + 1) % poly.count]
                area += (p2.x - p1.x) * (p2.y + p1.y)
            }
            return (poly, area)
        }

        contours.sort { abs($0.area) > abs($1.area) }

        guard !contours.isEmpty else { return [] }

        var outer = contours[0].poly

        // Bridge Holes
        for i in 1 ..< contours.count {
            let hole = contours[i].poly
            var minD = CGFloat.greatestFiniteMagnitude
            var bestH = 0
            var bestO = 0

            for h in 0 ..< hole.count {
                for o in 0 ..< outer.count {
                    let d = hypot(hole[h].x - outer[o].x, hole[h].y - outer[o].y)
                    if d < minD {
                        minD = d
                        bestH = h
                        bestO = o
                    }
                }
            }

            var newOuter: [CGPoint] = []
            newOuter.append(contentsOf: outer[0 ... bestO])

            let rotatedHole = Array(hole[bestH ..< hole.count]) + Array(hole[0 ..< bestH])
            newOuter.append(contentsOf: rotatedHole)
            newOuter.append(rotatedHole[0])
            newOuter.append(outer[bestO])

            if bestO < outer.count - 1 {
                newOuter.append(contentsOf: outer[(bestO + 1) ..< outer.count])
            }

            outer = newOuter
        }

        return earClip(polygon: outer)
    }

    static func earClip(polygon: [CGPoint]) -> [Triangle] {
        var points = polygon
        if points.first == points.last { points.removeLast() }

        // Filter duplicates
        if points.count > 1 {
            var uniquePoints: [CGPoint] = [points[0]]
            for i in 1 ..< points.count {
                let p = points[i]
                let last = uniquePoints.last!
                if hypot(p.x - last.x, p.y - last.y) > 0.01 {
                    uniquePoints.append(p)
                }
            }
            // Check wrap around
            if let first = uniquePoints.first, let last = uniquePoints.last {
                if hypot(first.x - last.x, first.y - last.y) < 0.01 {
                    uniquePoints.removeLast()
                }
            }
            points = uniquePoints
        }

        // Ensure CW winding
        var area: CGFloat = 0
        for i in 0 ..< points.count {
            let p1 = points[i]
            let p2 = points[(i + 1) % points.count]
            area += (p2.x - p1.x) * (p2.y + p1.y)
        }

        // If Area < 0, it's CCW (for this formula). We want CW.
        if area < 0 {
            points.reverse()
        }

        var triangles: [Triangle] = []
        var iterations = 0
        let maxIterations = points.count * points.count

        while points.count >= 3, iterations < maxIterations {
            iterations += 1
            var earFound = false

            for i in 0 ..< points.count {
                let prev = points[(i - 1 + points.count) % points.count]
                let curr = points[i]
                let next = points[(i + 1) % points.count]

                if isEar(prev, curr, next, polygon: points) {
                    triangles.append(Triangle(p0: prev, p1: curr, p2: next))
                    points.remove(at: i)
                    earFound = true
                    break
                }
            }

            if !earFound { break }
        }

        return triangles
    }

    static func isEar(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, polygon: [CGPoint]) -> Bool {
        if !isConvex(p1, p2, p3) { return false }

        for p in polygon {
            if p == p1 || p == p2 || p == p3 { continue }
            if isPointInTriangle(p, p1, p2, p3) { return false }
        }
        return true
    }

    static func isConvex(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> Bool {
        return ((p2.x - p1.x) * (p3.y - p1.y) - (p2.y - p1.y) * (p3.x - p1.x)) < 0
    }

    static func isPointInTriangle(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Bool {
        let v0 = CGPoint(x: c.x - a.x, y: c.y - a.y)
        let v1 = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let v2 = CGPoint(x: p.x - a.x, y: p.y - a.y)

        let dot00 = v0.x * v0.x + v0.y * v0.y
        let dot01 = v0.x * v1.x + v0.y * v1.y
        let dot02 = v0.x * v2.x + v0.y * v2.y
        let dot11 = v1.x * v1.x + v1.y * v1.y
        let dot12 = v1.x * v2.x + v1.y * v2.y

        let invDenom = 1 / (dot00 * dot11 - dot01 * dot01)
        let u = (dot11 * dot02 - dot01 * dot12) * invDenom
        let v = (dot00 * dot12 - dot01 * dot02) * invDenom

        return (u >= 0) && (v >= 0) && (u + v < 1)
    }
}
