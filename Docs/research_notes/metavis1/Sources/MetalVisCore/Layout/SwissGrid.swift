import CoreGraphics
import Foundation
import Metal

/// Swiss International/Bauhaus Grid System
/// Provides broadcast-quality layout structure for documentary production
///
/// Features:
/// - 12-column grid system
/// - 8pt baseline grid for vertical rhythm
/// - Safe margin zones (action-safe, title-safe)
/// - Type scale aligned to baseline
/// - Preset layouts for common scenarios
public struct SwissGrid: Sendable {
    // MARK: - Properties

    public let width: Int
    public let height: Int
    public let columns: Int
    public let baselineUnit: Float
    public let gutter: Float
    public let safeMargin: Float

    // MARK: - Initialization

    public init(
        width: Int,
        height: Int,
        columns: Int = 12,
        baselineUnit: Float = 8.0,
        gutter: Float = 20.0,
        safeMargin: Float? = nil
    ) {
        self.width = width
        self.height = height
        self.columns = columns
        self.baselineUnit = baselineUnit
        self.gutter = gutter
        // Default to 5% safe margin if not specified
        self.safeMargin = safeMargin ?? Float(width) * 0.05
    }

    // MARK: - Column Calculations

    /// Calculate X position for a column
    /// - Parameter column: Column index (0-based, can be negative for off-screen)
    /// - Returns: X coordinate in pixels
    public func columnX(_ column: Int) -> Float {
        let availableWidth = Float(width) - (safeMargin * 2)
        let totalGutters = Float(columns - 1) * gutter
        let columnWidth = (availableWidth - totalGutters) / Float(columns)

        return safeMargin + Float(column) * (columnWidth + gutter)
    }

    /// Get column width
    public var columnWidth: Float {
        let availableWidth = Float(width) - (safeMargin * 2)
        let totalGutters = Float(columns - 1) * gutter
        return (availableWidth - totalGutters) / Float(columns)
    }

    // MARK: - Baseline Calculations

    /// Calculate Y position for a baseline
    /// - Parameter baseline: Baseline index (0-based)
    /// - Returns: Y coordinate in pixels
    public func baselineY(_ baseline: Int) -> Float {
        return safeMargin + Float(baseline) * baselineUnit
    }

    /// Total number of baselines that fit in the grid
    public var totalBaselines: Int {
        let availableHeight = Float(height) - (safeMargin * 2)
        return Int(availableHeight / baselineUnit)
    }

    // MARK: - Position Conversion

    /// Convert grid position to CGPoint
    public func point(for position: GridPosition) -> CGPoint {
        return CGPoint(
            x: CGFloat(columnX(position.column)),
            y: CGFloat(baselineY(position.baseline))
        )
    }

    /// Create Metal region for a grid area
    public func region(columns: ClosedRange<Int>, baselines: ClosedRange<Int>) -> MTLRegion {
        let x = columnX(columns.lowerBound)
        let y = baselineY(baselines.lowerBound)
        let width = columnX(columns.upperBound + 1) - x
        let height = baselineY(baselines.upperBound + 1) - y

        return MTLRegionMake2D(Int(x), Int(y), Int(width), Int(height))
    }

    // MARK: - Common Positions (Presets)

    /// Position for lower third graphic (common in news/documentaries)
    public func lowerThirdPosition() -> GridPosition {
        let baseline = totalBaselines - 15 // 15 baselines from bottom
        return GridPosition(column: 1, baseline: baseline)
    }

    /// Position for title card (upper area, left aligned)
    public func titleCardPosition() -> GridPosition {
        return GridPosition(column: 2, baseline: 10)
    }

    /// Centered position
    public func centerPosition() -> GridPosition {
        let centerColumn = columns / 2
        let centerBaseline = totalBaselines / 2
        return GridPosition(column: centerColumn, baseline: centerBaseline)
    }

    /// Subtitle position (bottom center)
    public func subtitlePosition() -> GridPosition {
        let centerColumn = columns / 2
        let baseline = totalBaselines - 8 // 8 baselines from bottom
        return GridPosition(column: centerColumn, baseline: baseline)
    }

    // MARK: - Type Scale

    /// Typographic scale aligned to baseline grid
    public enum TypeScale: Float {
        case caption = 16 // 2 baseline units
        case body = 24 // 3 baseline units
        case subhead = 32 // 4 baseline units
        case title = 48 // 6 baseline units
        case display = 80 // 10 baseline units

        /// Number of baseline units this size occupies
        public var baselineUnits: Int {
            return Int(rawValue / 8.0)
        }
    }

    // MARK: - Standard Presets

    /// Standard 1080p grid (16:9)
    public static let standard1080p = SwissGrid(
        width: 1920,
        height: 1080,
        columns: 12,
        baselineUnit: 8.0,
        gutter: 20.0,
        safeMargin: 96.0 // 5%
    )

    /// Standard 4K grid (16:9) - scaled baseline for higher resolution
    public static let standard4K = SwissGrid(
        width: 3840,
        height: 2160,
        columns: 12,
        baselineUnit: 16.0, // Doubled for 4K
        gutter: 40.0, // Doubled for 4K
        safeMargin: 192.0 // 5%
    )

    /// Documentary preset with wider margins for cinematic feel
    public static let documentary1080p = SwissGrid(
        width: 1920,
        height: 1080,
        columns: 12,
        baselineUnit: 8.0,
        gutter: 20.0,
        safeMargin: 144.0 // 7.5% for more breathing room
    )

    /// Broadcast preset with title-safe area (6%)
    public static let broadcast1080p = SwissGrid(
        width: 1920,
        height: 1080,
        columns: 12,
        baselineUnit: 8.0,
        gutter: 20.0,
        safeMargin: 115.2 // 6% title-safe
    )

    /// Wide aspect ratio (21:9 cinema)
    public static let cinema2K = SwissGrid(
        width: 2560,
        height: 1080,
        columns: 16, // More columns for wider format
        baselineUnit: 8.0,
        gutter: 20.0,
        safeMargin: 128.0 // 5%
    )
}

// MARK: - Grid Position

/// Represents a position in the grid coordinate system
public struct GridPosition: Equatable, Sendable {
    public let column: Int
    public let baseline: Int

    public init(column: Int, baseline: Int) {
        self.column = column
        self.baseline = baseline
    }

    /// Offset this position by columns and baselines
    public func offset(columns: Int = 0, baselines: Int = 0) -> GridPosition {
        return GridPosition(
            column: column + columns,
            baseline: baseline + baselines
        )
    }
}

// MARK: - Grid Span

/// Represents a span of columns and baselines
public struct GridSpan: Equatable, Sendable {
    public let columns: Int
    public let baselines: Int

    public init(columns: Int, baselines: Int) {
        self.columns = columns
        self.baselines = baselines
    }

    /// Common spans for text elements
    public static let shortText = GridSpan(columns: 4, baselines: 3)
    public static let mediumText = GridSpan(columns: 6, baselines: 4)
    public static let longText = GridSpan(columns: 8, baselines: 6)
    public static let fullWidth = GridSpan(columns: 12, baselines: 3)
}
