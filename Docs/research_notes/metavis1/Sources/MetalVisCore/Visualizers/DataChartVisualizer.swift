import Foundation
import Logging
import Metal
import Shared
import simd

public actor DataChartVisualizer {
    private let logger: Logger

    public init() {
        var logger = Logger(label: "com.metalvis.chart")
        logger.logLevel = .info
        self.logger = logger
    }

    public func generateFrames(
        data: Shared.ChartData,
        width: Int,
        height: Int,
        duration: Double,
        frameRate: Int
    ) async -> [VisualizationFrame] {
        logger.info("Generating chart frames", metadata: [
            "type": "\(data.type)",
            "series": "\(data.series.count)"
        ])

        let totalFrames = Int(duration * Double(frameRate))
        var frames: [VisualizationFrame] = []

        // Use first series for now
        guard let firstSeries = data.series.first else {
            logger.warning("No series data found")
            return []
        }
        let values = firstSeries.values

        // Generate static elements (bars/slices)
        // We will animate them (grow in)

        for frameIndex in 0 ..< totalFrames {
            let progress = Double(frameIndex) / Double(totalFrames)
            // Animation: 0 to 1 over first 1 second
            let animProgress = min(Float(progress * duration), 1.0)
            let easedProgress = 1.0 - pow(1.0 - animProgress, 3.0) // Cubic ease out

            var elements: [ChartDrawable] = []

            // Simple color palette
            let colors: [SIMD4<Float>] = [
                SIMD4<Float>(0.2, 0.6, 1.0, 1.0), // Blue
                SIMD4<Float>(1.0, 0.4, 0.2, 1.0), // Orange
                SIMD4<Float>(0.2, 0.8, 0.4, 1.0), // Green
                SIMD4<Float>(0.8, 0.2, 0.8, 1.0), // Purple
                SIMD4<Float>(1.0, 0.8, 0.2, 1.0) // Yellow
            ]

            if data.type == .bar {
                // Bar Chart Layout
                let margin: Float = 100.0
                let chartWidth = Float(width) - 2 * margin
                let chartHeight = Float(height) - 2 * margin
                let barWidth = chartWidth / Float(values.count) * 0.8
                let spacing = chartWidth / Float(values.count) * 0.2

                let maxValue = values.max() ?? 1.0

                for (i, value) in values.enumerated() {
                    let normalizedValue = Float(value) / Float(maxValue)
                    let barHeight = normalizedValue * chartHeight * easedProgress

                    let x = margin + Float(i) * (barWidth + spacing) + barWidth / 2.0
                    let y = Float(height) - margin - barHeight / 2.0 // Center Y

                    elements.append(ChartDrawable(
                        type: .bar,
                        rect: SIMD4<Float>(x, y, barWidth, barHeight),
                        color: colors[i % colors.count]
                    ))
                }
            } else {
                // Pie Chart Layout
                let centerX = Float(width) / 2.0
                let centerY = Float(height) / 2.0
                let radius = min(Float(width), Float(height)) * 0.35

                let totalValue = values.reduce(0, +)
                var currentAngle: Float = -Float.pi / 2.0 // Start at top

                for (i, value) in values.enumerated() {
                    let sliceAngle = (Float(value) / Float(totalValue)) * 2.0 * Float.pi
                    let endAngle = currentAngle + sliceAngle * easedProgress

                    elements.append(ChartDrawable(
                        type: .pieSlice,
                        rect: SIMD4<Float>(centerX, centerY, radius, 0),
                        color: colors[i % colors.count],
                        value: currentAngle,
                        extra: endAngle
                    ))

                    currentAngle += sliceAngle
                }
            }

            frames.append(VisualizationFrame(
                index: frameIndex,
                nodes: [],
                edges: [],
                chartElements: elements
            ))
        }

        return frames
    }
}
