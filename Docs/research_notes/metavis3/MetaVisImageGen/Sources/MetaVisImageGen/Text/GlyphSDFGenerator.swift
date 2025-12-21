import CoreText
import CoreGraphics

public struct SDFConfiguration {
    public let fontSize: CGFloat // The font size to render at for generation
    public let scale: CGFloat // Downscale factor (e.g. render at 128, output 32 -> scale 0.25)
    public let padding: Int // Padding in the output SDF
    public let spread: CGFloat // The spread of the distance field in output pixels
    
    public init(fontSize: CGFloat = 64, scale: CGFloat = 1.0, padding: Int = 4, spread: CGFloat = 4.0) {
        self.fontSize = fontSize
        self.scale = scale
        self.padding = padding
        self.spread = spread
    }
}

public struct SDFResult {
    public let buffer: [UInt8]
    public let width: Int
    public let height: Int
    public let metrics: GlyphMetrics
}

public class GlyphSDFGenerator {
    public init() {}
    
    public func generate(font: CTFont, glyph: GlyphIndex, config: SDFConfiguration) -> SDFResult? {
        // 1. Get glyph metrics
        var glyph = glyph
        var boundingRect = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyph, &boundingRect, 1)
        
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        
        let metrics = GlyphMetrics(
            advance: advance.width,
            bearing: boundingRect.origin,
            bounds: boundingRect
        )
        
        // 2. Setup dimensions
        // config.padding is in output pixels. Convert to source pixels.
        let scale = Float(config.scale)
        let paddingSource = Int(ceil(Float(config.padding) / scale))
        
        let sourceWidth = Int(ceil(boundingRect.width)) + paddingSource * 2
        let sourceHeight = Int(ceil(boundingRect.height)) + paddingSource * 2
        
        // Ensure valid dimensions
        guard sourceWidth > 0 && sourceHeight > 0 else { return nil }
        
        // 3. Render High-Res Bitmap
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: sourceWidth,
            height: sourceHeight,
            bitsPerComponent: 8,
            bytesPerRow: sourceWidth,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        
        // Clear to black
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight))
        
        // Draw glyph in white
        context.setFillColor(gray: 1, alpha: 1)
        
        // Adjust position.
        // boundingRect.origin is usually (0, descent) or similar relative to baseline.
        // We want to center the glyph bounding box in our source rect + padding.
        // The source rect origin (0,0) corresponds to (boundingRect.minX - padding, boundingRect.minY - padding)
        // So we translate by (-minX + padding, -minY + padding)
        
        let originX = CGFloat(paddingSource) - boundingRect.origin.x
        let originY = CGFloat(paddingSource) - boundingRect.origin.y
        
        var position = CGPoint(x: originX, y: originY)
        CTFontDrawGlyphs(font, &glyph, &position, 1, context)
        
        guard let data = context.data else { return nil }
        let rawBuffer = UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: sourceWidth * sourceHeight)
        
        // 4. Convert to Boolean Grid
        // Threshold at 127
        let boolGrid = rawBuffer.map { $0 > 127 }
        
        // 5. Compute SDF
        // Spread in source pixels
        let spreadSource = Float(config.spread) / scale
        let sdfFloats = EDT.generateSDF(input: boolGrid, width: sourceWidth, height: sourceHeight, spread: spreadSource)
        
        // 6. Downsample to Target Resolution
        let targetWidth = Int(Float(sourceWidth) * scale)
        let targetHeight = Int(Float(sourceHeight) * scale)
        
        guard targetWidth > 0 && targetHeight > 0 else { return nil }
        
        var outputBuffer = [UInt8](repeating: 0, count: targetWidth * targetHeight)
        
        // Simple box filter or nearest neighbor?
        // For SDF, simple sampling is often okay if the source SDF is smooth.
        // Let's use bilinear interpolation for better quality.
        
        for y in 0..<targetHeight {
            for x in 0..<targetWidth {
                // Map target pixel (x,y) to source coordinates
                // Center of pixel logic: (x + 0.5) / scale = srcX + 0.5
                // srcX = (x + 0.5) / scale - 0.5
                
                let srcX = (Float(x) + 0.5) / scale - 0.5
                let srcY = (Float(y) + 0.5) / scale - 0.5
                
                let val = sampleBilinear(grid: sdfFloats, width: sourceWidth, height: sourceHeight, x: srcX, y: srcY)
                
                outputBuffer[y * targetWidth + x] = UInt8(max(0, min(255, val * 255.0)))
            }
        }
        
        return SDFResult(buffer: outputBuffer, width: targetWidth, height: targetHeight, metrics: metrics)
    }
    
    private func sampleBilinear(grid: [Float], width: Int, height: Int, x: Float, y: Float) -> Float {
        let x0 = Int(floor(x))
        let y0 = Int(floor(y))
        let x1 = x0 + 1
        let y1 = y0 + 1
        
        let wx = x - Float(x0)
        let wy = y - Float(y0)
        
        func get(_ ix: Int, _ iy: Int) -> Float {
            if ix < 0 || ix >= width || iy < 0 || iy >= height { return 0.0 } // Border is 0? Or 0.5? Or clamped?
            // For SDF, outside is usually 0 (far outside) or 0.5 (edge).
            // Since we padded, border should be 0 (outside).
            return grid[iy * width + ix]
        }
        
        let v00 = get(x0, y0)
        let v10 = get(x1, y0)
        let v01 = get(x0, y1)
        let v11 = get(x1, y1)
        
        let top = v00 * (1 - wx) + v10 * wx
        let bottom = v01 * (1 - wx) + v11 * wx
        
        return top * (1 - wy) + bottom * wy
    }
}
