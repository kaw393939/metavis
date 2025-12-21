import Foundation
import CoreText
import CoreGraphics

// TextAlignment is now defined in RenderManifest.swift

public struct LayoutLine {
    public let text: String
    public let width: CGFloat
}

public class TextLayout {
    private let fontRegistry: FontRegistry
    
    public init(fontRegistry: FontRegistry) {
        self.fontRegistry = fontRegistry
    }
    
    public func measure(text: String, fontID: FontID, fontSize: CGFloat) -> CGSize {
        guard let font = fontRegistry.getFont(fontID) else { return .zero }
        
        let baseFontSize = CTFontGetSize(font)
        let scale = fontSize / baseFontSize
        
        var width: CGFloat = 0
        let characters = Array(text.utf16)
        if characters.isEmpty { return .zero }
        
        // Get Glyphs
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        var chars = characters
        CTFontGetGlyphsForCharacters(font, &chars, &glyphs, characters.count)
        
        // Get Advances
        var advances = [CGSize](repeating: .zero, count: characters.count)
        CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, characters.count)
        
        for advance in advances {
            width += advance.width
        }
        
        // Height
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let leading = CTFontGetLeading(font)
        let height = (ascent + descent + leading)
        
        return CGSize(width: width * scale, height: height * scale)
    }
    
    public func layout(text: String, fontID: FontID, fontSize: CGFloat, style: TextStyle, containerWidth: CGFloat, alignment: TextAlignment, origin: CGPoint) -> [TextDrawCommand] {
        guard let font = fontRegistry.getFont(fontID) else { return [] }
        
        let baseFontSize = CTFontGetSize(font)
        let scale = fontSize / baseFontSize
        let lineHeight = (CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)) * scale
        
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        var lines: [LayoutLine] = []
        var currentLineWords: [String] = []
        var currentLineWidth: CGFloat = 0
        
        let spaceWidth = measure(text: " ", fontID: fontID, fontSize: fontSize).width
        
        for word in words {
            let wordWidth = measure(text: word, fontID: fontID, fontSize: fontSize).width
            
            // Check if adding this word exceeds container width
            // Only wrap if we already have words on the line (don't wrap a single long word that doesn't fit)
            let newLineLength = currentLineWidth + wordWidth + (currentLineWords.isEmpty ? 0 : spaceWidth)
            
            if newLineLength > containerWidth && !currentLineWords.isEmpty {
                // Commit current line
                let lineText = currentLineWords.joined(separator: " ")
                lines.append(LayoutLine(text: lineText, width: currentLineWidth))
                
                // Start new line
                currentLineWords = [word]
                currentLineWidth = wordWidth
            } else {
                if !currentLineWords.isEmpty {
                    currentLineWidth += spaceWidth
                }
                currentLineWords.append(word)
                currentLineWidth += wordWidth
            }
        }
        
        // Commit last line
        if !currentLineWords.isEmpty {
            let lineText = currentLineWords.joined(separator: " ")
            lines.append(LayoutLine(text: lineText, width: currentLineWidth))
        }
        
        // Generate Commands
        var commands: [TextDrawCommand] = []
        var y = origin.y
        
        for line in lines {
            var x = origin.x
            
            switch alignment {
            case .left:
                x = origin.x
            case .center:
                x = origin.x + (containerWidth - line.width) / 2
            case .right:
                x = origin.x + (containerWidth - line.width)
            }
            
            let cmd = TextDrawCommand(
                text: line.text,
                position: CGPoint(x: x, y: y),
                fontSize: fontSize,
                style: style,
                fontID: fontID
            )
            commands.append(cmd)
            
            y += lineHeight
        }
        
        return commands
    }
}
