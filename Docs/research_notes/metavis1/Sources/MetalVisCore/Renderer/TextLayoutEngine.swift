import CoreGraphics
import Foundation
import simd

/// Engine for calculating text layout independent of rendering.
/// Separates the "where" from the "how" of text rendering.
public struct TextLayoutEngine: Sendable {
    // MARK: - Types

    public struct LayoutResult: Sendable {
        /// All positioned glyphs ready for vertex generation
        public let glyphs: [PositionedGlyph]
        /// Total bounding box of the text block
        public let bounds: CGRect
        /// Total height of the text block
        public let totalHeight: Float
        /// Number of lines
        public let lineCount: Int
    }

    public struct PositionedGlyph: Sendable {
        public let character: Character
        /// Position of the glyph quad (top-left)
        public let position: SIMD2<Float>
        /// Size of the glyph quad
        public let size: SIMD2<Float>
        /// Texture coordinates (minX, minY, maxX, maxY)
        public let texCoords: SIMD4<Float>
        /// Rotation angle in radians (for curved text)
        public let rotation: Float

        public init(character: Character, position: SIMD2<Float>, size: SIMD2<Float>, texCoords: SIMD4<Float>, rotation: Float = 0.0) {
            self.character = character
            self.position = position
            self.size = size
            self.texCoords = texCoords
            self.rotation = rotation
        }
    }

    public enum Alignment: Sendable {
        case left
        case center
        case right
    }

    public enum VerticalAlignment: Sendable {
        case center
        case baseline // First line baseline at position.y
    }

    // MARK: - Properties

    private let fontAtlas: SDFFontAtlas
    private let atlasWidth: Float
    private let atlasHeight: Float

    // MARK: - Initialization

    public init(fontAtlas: SDFFontAtlas) {
        self.fontAtlas = fontAtlas
        atlasWidth = Float(fontAtlas.texture.width)
        atlasHeight = Float(fontAtlas.texture.height)
    }

    // MARK: - Layout

    /// Calculate layout for a block of text
    public func layout(
        text: String,
        position: SIMD2<Float>, // Center/Anchor position
        fontSize: Float,
        lineHeightMultiplier: Float = 1.2,
        alignment: Alignment = .center,
        verticalAlignment: VerticalAlignment = .center,
        tracking: Float = 0.0,
        scale: Float = 1.0,
        maxWidth: Float? = nil // Optional max width for word wrapping
    ) -> LayoutResult {
        // Calculate effective scale first
        let effectiveScale: Float
        if fontSize > 0 {
            effectiveScale = fontSize / Float(fontAtlas.fontMetrics.generatedFontSize)
        } else {
            effectiveScale = scale
        }
        
        // Tracking in pixels
        let trackingPixels = tracking * Float(fontAtlas.fontMetrics.generatedFontSize) * effectiveScale
        
        // Handle Word Wrapping if maxWidth is provided
        var processedText = text
        if let maxWidth = maxWidth, maxWidth > 0 {
            processedText = wordWrap(text: text, maxWidth: maxWidth, effectiveScale: effectiveScale, trackingPixels: trackingPixels)
            if processedText != text {
                print("TextLayoutEngine: Wrapped text. Original length: \(text.count), New lines: \(processedText.components(separatedBy: "\n").count)")
            } else {
                print("TextLayoutEngine: Text fit within maxWidth: \(maxWidth)")
            }
        }
        
        let lines = processedText.components(separatedBy: "\n")

        // Font metrics
        let fontHeight = Float(fontAtlas.fontMetrics.ascent + fontAtlas.fontMetrics.descent) * effectiveScale
        let actualLineHeight = fontHeight * lineHeightMultiplier
        let totalHeight = actualLineHeight * Float(lines.count)

        // Calculate starting Y position
        var yPos: Float

        switch verticalAlignment {
        case .center:
            // We want the visual center of the text block to be at position.y
            // Visual Top = FirstLineBaseline - Ascent
            // Visual Bottom = LastLineBaseline + Descent
            // Center = (Top + Bottom) / 2

            let ascent = Float(fontAtlas.fontMetrics.ascent) * effectiveScale
            let descent = Float(fontAtlas.fontMetrics.descent) * effectiveScale
            let blockHeight = Float(lines.count - 1) * actualLineHeight

            // yPos is the baseline of the first line
            // Derived from: Center = yPos + (blockHeight - Ascent + Descent) / 2
            yPos = position.y - (blockHeight - ascent + descent) / 2.0

        case .baseline:
            // position.y is the baseline of the first line
            yPos = position.y
        }

        var glyphs: [PositionedGlyph] = []
        var minX: Float = .greatestFiniteMagnitude
        var maxX: Float = -.greatestFiniteMagnitude
        var minY: Float = .greatestFiniteMagnitude
        var maxY: Float = -.greatestFiniteMagnitude

        for line in lines {
            // Measure line width for alignment
            let lineWidth = measureWidth(line, effectiveScale: effectiveScale, trackingPixels: trackingPixels)

            var xOffset = position.x

            switch alignment {
            case .left: break
            case .center: xOffset -= lineWidth / 2.0
            case .right: xOffset -= lineWidth
            }

            for char in line {
                guard let metrics = fontAtlas.glyphMetrics[char] else { continue }

                let glyphWidth = Float(metrics.textureCoords.width) * atlasWidth * effectiveScale
                let glyphHeight = Float(metrics.textureCoords.height) * atlasHeight * effectiveScale

                let x0 = xOffset - Float(metrics.origin.x) * effectiveScale
                let y0 = yPos - Float(metrics.origin.y) * effectiveScale
                
                // Grid fitting: Snap to pixel grid at small sizes to prevent "swimming" text
                let snappedX0: Float
                let snappedY0: Float
                if fontSize < 18 && fontSize > 0 {
                    snappedX0 = round(x0)
                    snappedY0 = round(y0)
                } else {
                    snappedX0 = x0
                    snappedY0 = y0
                }

                let u0 = Float(metrics.textureCoords.minX)
                let v0 = Float(metrics.textureCoords.minY)
                let u1 = Float(metrics.textureCoords.maxX)
                let v1 = Float(metrics.textureCoords.maxY)

                glyphs.append(PositionedGlyph(
                    character: char,
                    position: SIMD2(snappedX0, snappedY0),
                    size: SIMD2(glyphWidth, glyphHeight),
                    texCoords: SIMD4(u0, v0, u1, v1)
                ))

                // Update bounds
                if x0 < minX { minX = x0 }
                if x0 + glyphWidth > maxX { maxX = x0 + glyphWidth }
                if y0 < minY { minY = y0 }
                if y0 + glyphHeight > maxY { maxY = y0 + glyphHeight }

                xOffset += (Float(metrics.advance) * effectiveScale) + trackingPixels
            }

            yPos += actualLineHeight
        }

        let bounds: CGRect
        if glyphs.isEmpty {
            bounds = .zero
        } else {
            bounds = CGRect(
                x: CGFloat(minX),
                y: CGFloat(minY),
                width: CGFloat(maxX - minX),
                height: CGFloat(maxY - minY)
            )
        }
        
        print("TextLayoutEngine: Layout Bounds: \(bounds), Alignment: \(alignment), Position: \(position)")

        return LayoutResult(
            glyphs: glyphs,
            bounds: bounds,
            totalHeight: totalHeight,
            lineCount: lines.count
        )
    }

    /// Calculate circular layout for a block of text
    public func layoutCircular(
        text: String,
        center: SIMD2<Float>,
        radius: Float,
        startAngle: Float = 0.0, // Radians, 0 is top (12 o'clock)
        fontSize: Float,
        tracking: Float = 0.0,
        scale: Float = 1.0
    ) -> LayoutResult {
        // Calculate effective scale
        let effectiveScale: Float
        if fontSize > 0 {
            effectiveScale = fontSize / Float(fontAtlas.fontMetrics.generatedFontSize)
        } else {
            effectiveScale = scale
        }

        // Tracking in pixels
        let trackingPixels = tracking * Float(fontAtlas.fontMetrics.generatedFontSize) * effectiveScale

        // Measure total arc length to center it if needed
        // For now, we just start at startAngle and go clockwise

        var currentAngle = startAngle
        var glyphs: [PositionedGlyph] = []

        // Bounds tracking (approximate)
        var minX: Float = .greatestFiniteMagnitude
        var maxX: Float = -.greatestFiniteMagnitude
        var minY: Float = .greatestFiniteMagnitude
        var maxY: Float = -.greatestFiniteMagnitude

        for char in text {
            guard let metrics = fontAtlas.glyphMetrics[char] else { continue }

            let glyphWidth = Float(metrics.textureCoords.width) * atlasWidth * effectiveScale
            let glyphHeight = Float(metrics.textureCoords.height) * atlasHeight * effectiveScale
            let advance = (Float(metrics.advance) * effectiveScale) + trackingPixels

            // Calculate angle step for this character
            // ArcLength = Radius * Angle -> Angle = ArcLength / Radius
            // We use half advance to center the glyph on the current angle
            let charAngleWidth = advance / radius

            // Position is on the circle
            // x = cx + r * sin(angle)
            // y = cy - r * cos(angle) (0 is top)

            let x = center.x + radius * sin(currentAngle)
            let y = center.y - radius * cos(currentAngle)

            // Rotation: The glyph should be perpendicular to the radius
            // Tangent angle = currentAngle
            // Standard text is upright at 0 rotation.
            // At top (angle 0), we want text to be upright?
            // If rotation = 0, text is upright.
            // If rotation = currentAngle (0), text is upright.
            // At 3 o'clock (angle PI/2), rotation = PI/2. Text is vertical (downwards).
            // This seems correct for "text along path".
            let rotation = currentAngle

            // Adjust for glyph origin (centering the glyph on the radius line)
            // We want the baseline center to be at (x,y)
            // But PositionedGlyph expects top-left corner relative to rotation?
            // Actually, standard render assumes axis-aligned quads.
            // We need to store rotation in PositionedGlyph and handle it in the renderer.

            // For now, let's just calculate the center position and let the renderer handle the quad generation with rotation.
            // But PositionedGlyph stores top-left.
            // Let's store the center position in PositionedGlyph.position if we are rotating?
            // No, that breaks the contract.
            // Let's calculate the top-left position assuming no rotation, then rotate the quad in the renderer.
            // The renderer needs to know the pivot point.
            // Let's assume the pivot is the glyph center or baseline center.

            // Let's stick to the existing contract: position is top-left.
            // But for rotation, we need a pivot.
            // Let's assume pivot is (x + width/2, y + height/2).

            // Wait, for circular text, the pivot should be the baseline center.
            // Let's calculate the top-left position such that the baseline center is at (x,y).
            // Glyph origin in metrics is relative to top-left of the glyph box?
            // metrics.origin is (x, y) offset from pen position to top-left of glyph bitmap.
            // Pen position is (x,y) on the circle.

            let x0 = x - Float(metrics.origin.x) * effectiveScale
            let y0 = y - Float(metrics.origin.y) * effectiveScale

            let u0 = Float(metrics.textureCoords.minX)
            let v0 = Float(metrics.textureCoords.minY)
            let u1 = Float(metrics.textureCoords.maxX)
            let v1 = Float(metrics.textureCoords.maxY)

            glyphs.append(PositionedGlyph(
                character: char,
                position: SIMD2(x0, y0),
                size: SIMD2(glyphWidth, glyphHeight),
                texCoords: SIMD4(u0, v0, u1, v1),
                rotation: rotation
            ))

            // Update bounds (rough approximation)
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }

            currentAngle += charAngleWidth
        }

        let bounds = CGRect(
            x: CGFloat(minX),
            y: CGFloat(minY),
            width: CGFloat(maxX - minX),
            height: CGFloat(maxY - minY)
        )

        return LayoutResult(
            glyphs: glyphs,
            bounds: bounds,
            totalHeight: radius * 2, // Approx
            lineCount: 1
        )
    }

    private func measureWidth(_ text: String, effectiveScale: Float, trackingPixels: Float) -> Float {
        var width: Float = 0
        for char in text {
            guard let metrics = fontAtlas.glyphMetrics[char] else { continue }
            width += (Float(metrics.advance) * effectiveScale) + trackingPixels
        }
        // Debug print for long words or specific checks
        if text.count > 10 && width < 100 {
             print("TextLayoutEngine: Warning - Measured width for '\(text)' is suspiciously small: \(width)")
        }
        return width
    }
    
    private func wordWrap(text: String, maxWidth: Float, effectiveScale: Float, trackingPixels: Float) -> String {
        let words = text.components(separatedBy: .whitespaces)
        var lines: [String] = []
        var currentLine = ""
        
        for word in words {
            let testLine = currentLine.isEmpty ? word : currentLine + " " + word
            let width = measureWidth(testLine, effectiveScale: effectiveScale, trackingPixels: trackingPixels)
            
            if width > maxWidth {
                if !currentLine.isEmpty {
                    lines.append(currentLine)
                    currentLine = word
                } else {
                    // Word itself is too long, just add it (or split it? for now just add)
                    lines.append(word)
                    currentLine = ""
                }
            } else {
                currentLine = testLine
            }
        }
        
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        
        let result = lines.joined(separator: "\n")
        // Debug print the wrapped result
        if result != text {
             print("TextLayoutEngine: Wrapped result:\n\(result)")
             // Measure the widest line
             let maxLineWidth = lines.map { measureWidth($0, effectiveScale: effectiveScale, trackingPixels: trackingPixels) }.max() ?? 0
             print("TextLayoutEngine: Max line width: \(maxLineWidth) (Limit: \(maxWidth))")
        }
        
        return result
    }
}
