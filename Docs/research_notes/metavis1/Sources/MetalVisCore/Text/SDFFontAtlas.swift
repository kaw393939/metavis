import CoreGraphics
import CoreText
import Foundation
import Metal

/// Signed Distance Field Font Atlas
/// Stores pre-generated SDF representation of font glyphs in a Metal texture
/// Based on: Metal by Example, Chapter 12 (pages 107-116)
///
/// Memory: 1 byte per pixel (R8Unorm) vs 4 bytes (RGBA)
/// Quality: Infinite scalability without blur
public final class SDFFontAtlas: @unchecked Sendable {
    // MARK: - Properties

    /// Metal texture containing SDF data (R8Unorm format)
    public let texture: MTLTexture

    /// Glyph metrics for texture coordinate mapping
    public let glyphMetrics: [Character: GlyphMetrics]

    /// Global font metrics for layout
    public let fontMetrics: FontMetrics

    // MARK: - Initialization

    /// Create a font atlas with signed distance field representation
    /// - Parameters:
    ///   - font: The font to generate atlas from
    ///   - size: Atlas texture dimensions (typically 2048x2048 or 4096x4096)
    ///   - device: Metal device for texture creation
    public init(font: CTFont, size: CGSize, device: MTLDevice) throws {
        let atlasWidth = Int(size.width)
        let atlasHeight = Int(size.height)

        // Character set to include (ASCII printable + common symbols)
        let characters = (32 ... 126).compactMap { Character(UnicodeScalar($0)) }
        // HACK: Reduced character set for faster iteration during Film Grain testing
        // let characters = [Character(" ")]

        // Calculate glyph grid layout
        let glyphsPerRow = 16 // 16x16 grid for 256 characters max
        let cellWidth = atlasWidth / glyphsPerRow
        let cellHeight = atlasHeight / glyphsPerRow

        // Create high-res bitmap for rendering
        // Reduced from 8 to 2 for performance during testing
        let scale = 2
        let renderWidth = cellWidth * scale
        let renderHeight = cellHeight * scale

        // Use a font size that fills the cell (leaving some padding)
        // renderWidth is the size of the high-res cell.
        // We want the glyph to fit comfortably.
        let fontSize = CGFloat(renderWidth) * 0.75
        let scaledFont = CTFontCreateCopyWithAttributes(font, fontSize, nil, nil)

        // Store global font metrics
        fontMetrics = FontMetrics(
            ascent: CTFontGetAscent(scaledFont) / CGFloat(scale),
            descent: CTFontGetDescent(scaledFont) / CGFloat(scale),
            leading: CTFontGetLeading(scaledFont) / CGFloat(scale),
            capHeight: CTFontGetCapHeight(scaledFont) / CGFloat(scale),
            xHeight: CTFontGetXHeight(scaledFont) / CGFloat(scale),
            unitsPerEm: CGFloat(CTFontGetUnitsPerEm(scaledFont)),
            generatedFontSize: fontSize / CGFloat(scale)
        )

        // Allocate atlas bitmap (RGBA)
        var atlasBitmap = [UInt8](repeating: 0, count: atlasWidth * atlasHeight * 4)
        var metrics: [Character: GlyphMetrics] = [:]

        // Create bitmap context for glyph rendering
        // Context creation moved inside loop for safety

        let sdfGenerator = SDFGenerator()

        print("🔤 Generating SDF Atlas (\(atlasWidth)x\(atlasHeight), Scale: \(scale)x)...")

        // Render each glyph
        for (index, character) in characters.enumerated() {
            if index % 10 == 0 {
                print("   Processing glyph \(index)/\(characters.count): '\(character)'")
            }

            let row = index / glyphsPerRow
            let col = index % glyphsPerRow

            // Get glyph from character
            var glyph = CGGlyph()
            var unichar = [UniChar](String(character).utf16)
            guard CTFontGetGlyphsForCharacters(scaledFont, &unichar, &glyph, 1) else {
                continue
            }

            // Get glyph metrics
            var boundingBox = CGRect.zero
            CTFontGetBoundingRectsForGlyphs(scaledFont, .horizontal, &glyph, &boundingBox, 1)
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(scaledFont, .horizontal, &glyph, &advance, 1)

            // Get glyph path
            let path = CTFontCreatePathForGlyph(scaledFont, glyph, nil)

            // Position glyph with padding
            // We use a fixed baseline position to ensure alignment across all glyphs.
            // Do NOT center the glyph based on its bounding box, as that destroys baseline information.

            let padding = CGFloat(renderWidth) * 0.1
            let ascent = CTFontGetAscent(scaledFont)

            // Target origin for the baseline in the texture cell (Top-Left is 0,0)
            // We place the baseline down by (ascent + padding) so the top of the glyph fits.
            let originX = padding
            let originY = ascent + padding

            if let path = path {
                // Transform path to fit in the cell
                // Glyph coordinates are Y-up. Texture coordinates are Y-down.
                // We map (0,0) [Baseline] to (originX, originY).
                // x' = x + originX
                // y' = -y + originY

                var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: originX, ty: originY)

                var finalPath = path
                if let p = path.copy(using: &transform) {
                    finalPath = p
                }

                // Generate MSDF (Returns RGBA)
                let sdfData = sdfGenerator.generateMSDF(
                    from: finalPath,
                    width: renderWidth,
                    height: renderHeight,
                    range: 4.0,
                    scale: 1.0
                )

                // Downsample SDF to atlas resolution
                for y in 0 ..< cellHeight {
                    for x in 0 ..< cellWidth {
                        // Sample from high-res SDF
                        let srcX = (x * scale) + scale / 2
                        let srcY = (y * scale) + scale / 2
                        let srcIndex = (srcY * renderWidth + srcX) * 4

                        if srcIndex < sdfData.count {
                            let dstX = col * cellWidth + x
                            let dstY = row * cellHeight + y
                            let dstIndex = (dstY * atlasWidth + dstX) * 4

                            if dstIndex < atlasBitmap.count {
                                atlasBitmap[dstIndex] = sdfData[srcIndex] // R
                                atlasBitmap[dstIndex + 1] = sdfData[srcIndex + 1] // G
                                atlasBitmap[dstIndex + 2] = sdfData[srcIndex + 2] // B
                                atlasBitmap[dstIndex + 3] = sdfData[srcIndex + 3] // A
                            }
                        }
                    }
                }
            }

            // Store glyph metrics
            let texCoords = CGRect(
                x: CGFloat(col * cellWidth) / CGFloat(atlasWidth),
                y: CGFloat(row * cellHeight) / CGFloat(atlasHeight),
                width: CGFloat(cellWidth) / CGFloat(atlasWidth),
                height: CGFloat(cellHeight) / CGFloat(atlasHeight)
            )

            metrics[character] = GlyphMetrics(
                textureCoords: texCoords,
                advance: advance.width / CGFloat(scale),
                bearing: CGPoint(x: boundingBox.origin.x / CGFloat(scale), y: boundingBox.origin.y / CGFloat(scale)),
                origin: CGPoint(x: originX / CGFloat(scale), y: originY / CGFloat(scale))
            )
        }

        // Create Metal texture
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.pixelFormat = .rgba8Unorm
        textureDescriptor.width = atlasWidth
        textureDescriptor.height = atlasHeight
        textureDescriptor.usage = [.shaderRead]
        textureDescriptor.storageMode = .shared

        guard let metalTexture = device.makeTexture(descriptor: textureDescriptor) else {
            throw SDFError.textureCreationFailed
        }

        // Upload bitmap to texture
        metalTexture.replace(
            region: MTLRegion(
                origin: MTLOrigin(x: 0, y: 0, z: 0),
                size: MTLSize(width: atlasWidth, height: atlasHeight, depth: 1)
            ),
            mipmapLevel: 0,
            withBytes: atlasBitmap,
            bytesPerRow: atlasWidth * 4
        )

        texture = metalTexture
        glyphMetrics = metrics
    }

    // MARK: - Types

    /// Global metrics for the font used in the atlas
    public struct FontMetrics: Sendable {
        public let ascent: CGFloat
        public let descent: CGFloat
        public let leading: CGFloat
        public let capHeight: CGFloat
        public let xHeight: CGFloat
        public let unitsPerEm: CGFloat
        public let generatedFontSize: CGFloat
    }

    /// Metrics for a single glyph in the atlas
    public struct GlyphMetrics: Sendable {
        /// Normalized texture coordinates [0, 1] for glyph bounds
        public let textureCoords: CGRect

        /// Horizontal advance for cursor positioning (in atlas pixels)
        public let advance: CGFloat

        /// Bearing offset for alignment (in atlas pixels)
        public let bearing: CGPoint

        /// Origin of the glyph baseline within the atlas cell (in atlas pixels)
        public let origin: CGPoint

        public init(textureCoords: CGRect, advance: CGFloat, bearing: CGPoint, origin: CGPoint = .zero) {
            self.textureCoords = textureCoords
            self.advance = advance
            self.bearing = bearing
            self.origin = origin
        }
    }
}

/// Errors that can occur during SDF atlas generation
public enum SDFError: Error, LocalizedError {
    case notImplemented(String)
    case invalidFont
    case textureCreationFailed
    case bitmapContextCreationFailed

    public var errorDescription: String? {
        switch self {
        case let .notImplemented(feature):
            return "Not implemented: \(feature)"
        case .invalidFont:
            return "Invalid font for atlas generation"
        case .textureCreationFailed:
            return "Failed to create Metal texture"
        case .bitmapContextCreationFailed:
            return "Failed to create bitmap context"
        }
    }
}
