import Foundation
import CoreGraphics

public typealias FontID = Int
public typealias GlyphIndex = CGGlyph

public struct GlyphID: Hashable, Sendable {
    public let fontID: FontID
    public let index: GlyphIndex
    
    public init(fontID: FontID, index: GlyphIndex) {
        self.fontID = fontID
        self.index = index
    }
}

public struct GlyphMetrics: Sendable, Codable {
    public let advance: CGFloat
    public let bearing: CGPoint
    public let bounds: CGRect
    
    public init(advance: CGFloat, bearing: CGPoint, bounds: CGRect) {
        self.advance = advance
        self.bearing = bearing
        self.bounds = bounds
    }
    
    public static let zero = GlyphMetrics(advance: 0, bearing: .zero, bounds: .zero)
}

/// Represents the location of a glyph in the texture atlas
public struct GlyphAtlasLocation: Sendable, Codable {
    public let textureIndex: Int
    public let region: CGRect // UV coordinates
    public let padding: CGFloat // Padding in UV space if needed
    public let metrics: GlyphMetrics // Metrics for layout
    
    public init(textureIndex: Int, region: CGRect, padding: CGFloat = 0, metrics: GlyphMetrics = .zero) {
        self.textureIndex = textureIndex
        self.region = region
        self.padding = padding
        self.metrics = metrics
    }
}
