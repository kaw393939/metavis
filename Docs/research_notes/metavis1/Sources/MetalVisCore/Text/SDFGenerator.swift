import CoreGraphics
import Foundation
import simd

/// Signed Distance Field Generator
/// Implements True Euclidean Distance Transform (EDT) and MSDF generation.
public struct SDFGenerator {
    public init() {}

    // MARK: - MSDF Generation (Vector)

    /// Generate Multi-channel Signed Distance Field from Vector Path
    /// - Parameters:
    ///   - path: The glyph path
    ///   - width: Output width
    ///   - height: Output height
    ///   - range: The signed distance range (in pixels). Default 4.0.
    ///   - scale: Scale factor applied to the path to fit in width/height
    ///   - translation: Translation applied to the path
    public func generateMSDF(
        from path: CGPath,
        width: Int,
        height: Int,
        range: Double = 4.0,
        scale: Double = 1.0,
        translation: CGPoint = .zero
    ) -> [UInt8] {
        // 1. Parse Path into Shape
        var shape = Shape()
        var currentContour = Contour()
        var startPoint = CGPoint.zero
        var currentPoint = CGPoint.zero

        path.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            let points = element.points

            switch element.type {
            case .moveToPoint:
                if !currentContour.segments.isEmpty {
                    shape.contours.append(currentContour)
                    currentContour = Contour()
                }
                startPoint = points[0]
                currentPoint = points[0]

            case .addLineToPoint:
                let p1 = points[0]
                if p1 != currentPoint {
                    currentContour.segments.append(Segment.makeLine(p0: currentPoint, p1: p1))
                    currentPoint = p1
                }

            case .addQuadCurveToPoint:
                let p1 = points[0]
                let p2 = points[1]
                if p2 != currentPoint {
                    currentContour.segments.append(Segment.makeQuad(p0: currentPoint, p1: p1, p2: p2))
                    currentPoint = p2
                }

            case .addCurveToPoint:
                let p1 = points[0]
                let p2 = points[1]
                let p3 = points[2]
                if p3 != currentPoint {
                    currentContour.segments.append(Segment.makeCubic(p0: currentPoint, p1: p1, p2: p2, p3: p3))
                    currentPoint = p3
                }

            case .closeSubpath:
                if currentPoint != startPoint {
                    currentContour.segments.append(Segment.makeLine(p0: currentPoint, p1: startPoint))
                }
                if !currentContour.segments.isEmpty {
                    shape.contours.append(currentContour)
                    currentContour = Contour()
                }
                currentPoint = startPoint

            @unknown default:
                break
            }
        }

        if !currentContour.segments.isEmpty {
            shape.contours.append(currentContour)
        }

        // 2. Edge Coloring
        shape.colorEdges()

        // 3. Generate MSDF
        var result = [UInt8](repeating: 0, count: width * height * 4)

        // Capture shape for concurrent access (Shape is Sendable)
        let capturedShape = shape

        result.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            let baseAddressInt = UInt(bitPattern: baseAddress)

            DispatchQueue.concurrentPerform(iterations: height) { y in
                guard let ptr = UnsafeMutablePointer<UInt8>(bitPattern: baseAddressInt) else { return }

                for x in 0 ..< width {
                    // Pixel center in image coordinates
                    let px = Double(x) + 0.5
                    let py = Double(y) + 0.5

                    // Transform to path coordinates
                    let pathP = CGPoint(
                        x: (px - translation.x) / scale,
                        y: (py - translation.y) / scale
                    )

                    // Calculate Signed Distance for each channel
                    let msdf = capturedShape.msdf(at: pathP)

                    // Normalize and encode
                    let sdR = msdf.r * scale
                    let sdG = msdf.g * scale
                    let sdB = msdf.b * scale
                    let sdA = msdf.a * scale // True Distance

                    let valR = UInt8(max(0, min(255, (sdR / range) * 255.0 + 127.5)))
                    let valG = UInt8(max(0, min(255, (sdG / range) * 255.0 + 127.5)))
                    let valB = UInt8(max(0, min(255, (sdB / range) * 255.0 + 127.5)))
                    let valA = UInt8(max(0, min(255, (sdA / range) * 255.0 + 127.5)))

                    let idx = (y * width + x) * 4
                    ptr[idx] = valR
                    ptr[idx + 1] = valG
                    ptr[idx + 2] = valB
                    ptr[idx + 3] = valA // Store True Distance in Alpha
                }
            }
        }

        return result
    }

    // MARK: - Standard SDF Generation (Bitmap)

    /// Generate signed distance field from binary bitmap
    public func generateSDF(
        from bitmap: [UInt8],
        width: Int,
        height: Int,
        searchRadius: Int = 10
    ) -> [UInt8] {
        guard bitmap.count == width * height else {
            fatalError("Bitmap size mismatch: expected \(width * height), got \(bitmap.count)")
        }

        // 1. Identify Boundary Pixels
        var boundaryPixels: [SIMD2<Int>] = []
        boundaryPixels.reserveCapacity(width * height / 10)

        for y in 0 ..< height {
            for x in 0 ..< width {
                let i = y * width + x
                let isInside = bitmap[i] > 127

                if isInside {
                    var isBoundary = false
                    if x == 0 || x == width - 1 || y == 0 || y == height - 1 {
                        isBoundary = true
                    } else {
                        if bitmap[i - 1] <= 127 || bitmap[i + 1] <= 127 ||
                            bitmap[i - width] <= 127 || bitmap[i + width] <= 127 {
                            isBoundary = true
                        }
                    }

                    if isBoundary {
                        boundaryPixels.append(SIMD2(x, y))
                    }
                }
            }
        }

        if boundaryPixels.isEmpty {
            let val: UInt8 = (bitmap.first ?? 0) > 127 ? 255 : 0
            var result = [UInt8](repeating: 0, count: width * height * 4)
            for i in 0 ..< (width * height) {
                result[i * 4] = val
                result[i * 4 + 1] = val
                result[i * 4 + 2] = val
                result[i * 4 + 3] = 255
            }
            return result
        }

        var result = [UInt8](repeating: 0, count: width * height * 4)
        let maxDistSq = Float(searchRadius * searchRadius)
        let spread = Float(searchRadius)

        let boundaryFloats = boundaryPixels.map { SIMD2<Float>(Float($0.x), Float($0.y)) }

        result.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            let baseAddressInt = UInt(bitPattern: baseAddress)

            DispatchQueue.concurrentPerform(iterations: height) { y in
                guard let ptr = UnsafeMutablePointer<UInt8>(bitPattern: baseAddressInt) else { return }

                for x in 0 ..< width {
                    let i = y * width + x
                    let isInside = bitmap[i] > 127
                    let p = SIMD2<Float>(Float(x), Float(y))

                    var minDistSq = maxDistSq

                    for b in boundaryFloats {
                        let dx = p.x - b.x
                        let dy = p.y - b.y
                        let dSq = dx * dx + dy * dy
                        if dSq < minDistSq {
                            minDistSq = dSq
                        }
                    }

                    let dist = sqrt(minDistSq)
                    let signedDist = isInside ? dist : -dist
                    let clampedDist = max(-spread, min(spread, signedDist))
                    let normalized = (clampedDist / spread) * 0.5 + 0.5

                    let val = UInt8(max(0, min(255, normalized * 255.0)))

                    let dstIndex = i * 4
                    ptr[dstIndex] = val
                    ptr[dstIndex + 1] = val
                    ptr[dstIndex + 2] = val
                    ptr[dstIndex + 3] = 255
                }
            }
        }

        return result
    }
}

// MARK: - Internal MSDF Types & Logic

private struct Shape: Sendable {
    var contours: [Contour] = []

    mutating func colorEdges() {
        for i in 0 ..< contours.count {
            contours[i].colorEdges()
        }
    }

    func contains(_ p: CGPoint) -> Bool {
        var winding = 0
        for contour in contours {
            for segment in contour.segments {
                winding += segment.winding(p)
            }
        }
        return winding != 0
    }

    func msdf(at p: CGPoint) -> (r: Double, g: Double, b: Double, a: Double) {
        var rMin = Double.infinity
        var gMin = Double.infinity
        var bMin = Double.infinity

        var globalMin = Double.infinity

        for contour in contours {
            for segment in contour.segments {
                let sd = segment.signedDistance(to: p) // Absolute distance
                let absDist = sd

                if segment.color.hasRed {
                    if absDist < rMin { rMin = absDist }
                }
                if segment.color.hasGreen {
                    if absDist < gMin { gMin = absDist }
                }
                if segment.color.hasBlue {
                    if absDist < bMin { bMin = absDist }
                }

                if absDist < globalMin { globalMin = absDist }
            }
        }

        if rMin == Double.infinity { rMin = globalMin }
        if gMin == Double.infinity { gMin = globalMin }
        if bMin == Double.infinity { bMin = globalMin }

        // Apply sign based on winding number
        let isInside = contains(p)
        if !isInside {
            rMin = -rMin
            gMin = -gMin
            bMin = -bMin
            globalMin = -globalMin
        }

        return (rMin, gMin, bMin, globalMin)
    }
}

private struct Contour: Sendable {
    var segments: [Segment] = []

    mutating func colorEdges() {
        guard !segments.isEmpty else { return }

        var cornerIndices: [Int] = []
        for i in 0 ..< segments.count {
            let prev = segments[(i - 1 + segments.count) % segments.count]
            let curr = segments[i]

            let v1 = prev.direction(at: 1.0)
            let v2 = curr.direction(at: 0.0)

            let dot = v1.x * v2.x + v1.y * v2.y

            if dot < 0.9 {
                cornerIndices.append(i)
            }
        }

        if cornerIndices.isEmpty {
            for i in 0 ..< segments.count {
                segments[i].color = .white
            }
            return
        }

        let colors: [EdgeColor] = [.red, .green, .blue]
        var colorIndex = 0

        for i in 0 ..< segments.count {
            if cornerIndices.contains(i) {
                colorIndex = (colorIndex + 1) % 3
            }
            segments[i].color = colors[colorIndex]
        }
    }
}

private enum Segment: Sendable {
    case line(p0: CGPoint, p1: CGPoint, color: EdgeColor)
    case quad(p0: CGPoint, p1: CGPoint, p2: CGPoint, color: EdgeColor)
    case cubic(p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint, color: EdgeColor)

    var color: EdgeColor {
        get {
            switch self {
            case let .line(_, _, c): return c
            case let .quad(_, _, _, c): return c
            case let .cubic(_, _, _, _, c): return c
            }
        }
        set {
            switch self {
            case let .line(p0, p1, _): self = .line(p0: p0, p1: p1, color: newValue)
            case let .quad(p0, p1, p2, _): self = .quad(p0: p0, p1: p1, p2: p2, color: newValue)
            case let .cubic(p0, p1, p2, p3, _): self = .cubic(p0: p0, p1: p1, p2: p2, p3: p3, color: newValue)
            }
        }
    }

    static func makeLine(p0: CGPoint, p1: CGPoint, color: EdgeColor = .white) -> Segment {
        return .line(p0: p0, p1: p1, color: color)
    }

    static func makeQuad(p0: CGPoint, p1: CGPoint, p2: CGPoint, color: EdgeColor = .white) -> Segment {
        return .quad(p0: p0, p1: p1, p2: p2, color: color)
    }

    static func makeCubic(p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint, color: EdgeColor = .white) -> Segment {
        return .cubic(p0: p0, p1: p1, p2: p2, p3: p3, color: color)
    }

    func direction(at t: Double) -> CGPoint {
        switch self {
        case let .line(p0, p1, _):
            return normalize(p1 - p0)
        case let .quad(p0, p1, p2, _):
            let t1 = 1 - t
            let term1 = (p1 - p0) * (2 * t1)
            let term2 = (p2 - p1) * (2 * t)
            return normalize(term1 + term2)
        case let .cubic(p0, p1, p2, p3, _):
            let t1 = 1 - t
            let term1 = (p1 - p0) * (3 * t1 * t1)
            let term2 = (p2 - p1) * (6 * t1 * t)
            let term3 = (p3 - p2) * (3 * t * t)
            return normalize(term1 + term2 + term3)
        }
    }

    func signedDistance(to p: CGPoint) -> Double {
        let (dist, _) = distanceSquared(to: p)
        return sqrt(dist)
    }

    func winding(_ p: CGPoint) -> Int {
        switch self {
        case let .line(p0, p1, _):
            if (p0.y <= p.y && p1.y > p.y) || (p1.y <= p.y && p0.y > p.y) {
                let t = (p.y - p0.y) / (p1.y - p0.y)
                let x = p0.x + (p1.x - p0.x) * t
                if x > p.x {
                    return p1.y > p0.y ? 1 : -1
                }
            }
            return 0

        case let .quad(p0, p1, p2, _):
            let a = p0.y - 2 * p1.y + p2.y
            let b = 2 * p1.y - 2 * p0.y
            let c = p0.y - p.y

            var roots: [Double] = []
            if abs(a) < 1e-9 {
                if abs(b) > 1e-9 { roots.append(-c / b) }
            } else {
                let disc = b * b - 4 * a * c
                if disc >= 0 {
                    let sqrtDisc = sqrt(disc)
                    roots.append((-b - sqrtDisc) / (2 * a))
                    roots.append((-b + sqrtDisc) / (2 * a))
                }
            }

            var w = 0
            for t in roots {
                if t >= 0 && t < 1 {
                    let x = (1 - t) * (1 - t) * p0.x + 2 * (1 - t) * t * p1.x + t * t * p2.x
                    if x > p.x {
                        let dy = 2 * (1 - t) * (p1.y - p0.y) + 2 * t * (p2.y - p1.y)
                        w += (dy > 0 ? 1 : -1)
                    }
                }
            }
            return w

        case let .cubic(p0, _, _, _, _):
            var w = 0
            var prevP = p0
            for i in 1 ... 10 {
                let t = Double(i) / 10.0
                let currP = point(at: t)
                if (prevP.y <= p.y && currP.y > p.y) || (currP.y <= p.y && prevP.y > p.y) {
                    let tLine = (p.y - prevP.y) / (currP.y - prevP.y)
                    let x = prevP.x + (currP.x - prevP.x) * tLine
                    if x > p.x {
                        w += (currP.y > prevP.y ? 1 : -1)
                    }
                }
                prevP = currP
            }
            return w
        }
    }

    func point(at t: Double) -> CGPoint {
        switch self {
        case let .line(p0, p1, _):
            return p0 + (p1 - p0) * t
        case let .quad(p0, p1, p2, _):
            let t1 = 1 - t
            let term1 = p0 * (t1 * t1)
            let term2 = p1 * (2 * t1 * t)
            let term3 = p2 * (t * t)
            return term1 + term2 + term3
        case let .cubic(p0, p1, p2, p3, _):
            let t1 = 1 - t
            let term1 = p0 * (t1 * t1 * t1)
            let term2 = p1 * (3 * t1 * t1 * t)
            let term3 = p2 * (3 * t1 * t * t)
            let term4 = p3 * (t * t * t)
            return term1 + term2 + term3 + term4
        }
    }

    func distanceSquared(to p: CGPoint) -> (Double, Double) {
        switch self {
        case let .line(p0, p1, _):
            let v = p1 - p0
            let w = p - p0
            let c1 = w.x * v.x + w.y * v.y
            if c1 <= 0 { return (distanceSq(p, p0), 0) }
            let c2 = v.x * v.x + v.y * v.y
            if c2 <= c1 { return (distanceSq(p, p1), 1) }
            let b = c1 / c2
            let pb = p0 + v * b
            return (distanceSq(p, pb), b)

        case .quad:
            var minD = Double.infinity
            var minT = 0.0
            for i in 0 ... 10 {
                let t = Double(i) / 10.0
                let pt = point(at: t)
                let d = distanceSq(p, pt)
                if d < minD {
                    minD = d
                    minT = t
                }
            }
            return (minD, minT)

        case .cubic:
            var minD = Double.infinity
            var minT = 0.0
            for i in 0 ... 10 {
                let t = Double(i) / 10.0
                let pt = point(at: t)
                let d = distanceSq(p, pt)
                if d < minD {
                    minD = d
                    minT = t
                }
            }
            return (minD, minT)
        }
    }
}

private struct EdgeColor: OptionSet, Sendable {
    let rawValue: Int
    static let red = EdgeColor(rawValue: 1 << 0)
    static let green = EdgeColor(rawValue: 1 << 1)
    static let blue = EdgeColor(rawValue: 1 << 2)
    static let white: EdgeColor = [.red, .green, .blue]
    static let black: EdgeColor = []

    var hasRed: Bool { contains(.red) }
    var hasGreen: Bool { contains(.green) }
    var hasBlue: Bool { contains(.blue) }
}

// MARK: - Math Helpers

private func distanceSq(_ p1: CGPoint, _ p2: CGPoint) -> Double {
    let dx = p1.x - p2.x
    let dy = p1.y - p2.y
    return dx * dx + dy * dy
}

private func normalize(_ p: CGPoint) -> CGPoint {
    let len = sqrt(p.x * p.x + p.y * p.y)
    return len > 0 ? CGPoint(x: p.x / len, y: p.y / len) : .zero
}

private func + (left: CGPoint, right: CGPoint) -> CGPoint {
    return CGPoint(x: left.x + right.x, y: left.y + right.y)
}

private func - (left: CGPoint, right: CGPoint) -> CGPoint {
    return CGPoint(x: left.x - right.x, y: left.y - right.y)
}

private func * (left: CGPoint, right: Double) -> CGPoint {
    return CGPoint(x: left.x * right, y: left.y * right)
}
