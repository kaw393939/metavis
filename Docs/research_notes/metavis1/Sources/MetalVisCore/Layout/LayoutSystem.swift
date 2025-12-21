import CoreGraphics
import Foundation

// MARK: - Anchors

/// Horizontal anchor point
public enum HorizontalAnchor: Sendable {
    /// Left edge of the safe area
    case left
    /// Horizontal center of the safe area
    case center
    /// Right edge of the safe area
    case right
    /// Specific column index (0-based)
    case column(Int)
    /// Percentage of width (0.0 - 1.0)
    case relative(Float)
}

/// Vertical anchor point
public enum VerticalAnchor: Sendable {
    /// Top edge of the safe area
    case top
    /// Vertical center of the safe area
    case center
    /// Bottom edge of the safe area
    case bottom
    /// Specific baseline index (0-based)
    case baseline(Int)
    /// Percentage of height (0.0 - 1.0)
    case relative(Float)
}

// MARK: - Layout Constraint

/// Semantic definition of a position within the grid
public struct LayoutConstraint: Sendable {
    public let x: HorizontalAnchor
    public let y: VerticalAnchor
    public let offset: SIMD2<Float>

    public init(x: HorizontalAnchor, y: VerticalAnchor, offset: SIMD2<Float> = .zero) {
        self.x = x
        self.y = y
        self.offset = offset
    }

    // MARK: - Common Presets

    /// Top-left corner (safe area)
    public static var topLeft: LayoutConstraint {
        return LayoutConstraint(x: .left, y: .top)
    }

    /// Center of the screen
    public static var center: LayoutConstraint {
        return LayoutConstraint(x: .center, y: .center)
    }

    /// Title card position (standard documentary style)
    public static var titleCard: LayoutConstraint {
        return LayoutConstraint(x: .column(1), y: .baseline(10))
    }

    /// Lower third position
    public static var lowerThird: LayoutConstraint {
        return LayoutConstraint(x: .column(1), y: .bottom, offset: SIMD2<Float>(0, -120))
    }
}

// MARK: - Grid Extension

public extension SwissGrid {
    /// Resolve a layout constraint to a pixel position
    func resolve(_ constraint: LayoutConstraint) -> CGPoint {
        let xPos = resolveX(constraint.x) + constraint.offset.x
        let yPos = resolveY(constraint.y) + constraint.offset.y
        return CGPoint(x: CGFloat(xPos), y: CGFloat(yPos))
    }

    private func resolveX(_ anchor: HorizontalAnchor) -> Float {
        let safeWidth = Float(width) - (safeMargin * 2)

        switch anchor {
        case .left:
            return safeMargin
        case .center:
            return Float(width) / 2.0
        case .right:
            return Float(width) - safeMargin
        case let .column(index):
            return columnX(index)
        case let .relative(percent):
            return safeMargin + (safeWidth * percent)
        }
    }

    private func resolveY(_ anchor: VerticalAnchor) -> Float {
        let safeHeight = Float(height) - (safeMargin * 2)

        switch anchor {
        case .top:
            return safeMargin
        case .center:
            return Float(height) / 2.0
        case .bottom:
            return Float(height) - safeMargin
        case let .baseline(index):
            return baselineY(index)
        case let .relative(percent):
            return safeMargin + (safeHeight * percent)
        }
    }
}
