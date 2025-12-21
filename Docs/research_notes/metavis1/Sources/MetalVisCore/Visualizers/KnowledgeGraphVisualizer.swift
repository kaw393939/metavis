import Foundation
import Logging
import Metal
import Shared
import simd

/// Simple knowledge graph visualizer with force-directed layout
public actor KnowledgeGraphVisualizer {
    private let logger: Logger
    private let device: MTLDevice
    private let layoutEngine: GraphLayoutEngine?

    public init(device: MTLDevice? = nil) {
        var logger = Logger(label: "com.metalvis.graph")
        logger.logLevel = .info
        self.logger = logger

        if let d = device {
            self.device = d
        } else if let d = MTLCreateSystemDefaultDevice() {
            self.device = d
        } else {
            fatalError("Metal is not supported on this device")
        }

        do {
            layoutEngine = try GraphLayoutEngine(device: self.device)
        } catch {
            logger.error("Failed to initialize GraphLayoutEngine: \(error)")
            layoutEngine = nil
        }
    }

    /// Generate visualization frames
    public func generateFrames(
        data: Shared.GraphData,
        width: Int,
        height: Int,
        duration: Double,
        frameRate: Int
    ) async -> [VisualizationFrame] {
        logger.info("Generating knowledge graph frames", metadata: [
            "nodes": "\(data.nodes.count)",
            "edges": "\(data.edges.count)",
            "duration": "\(duration)s"
        ])

        let totalFrames = Int(duration * Double(frameRate))
        var frames: [VisualizationFrame] = []

        // Compute layout
        let nodePositions = await computeForceDirectedLayout(
            nodes: data.nodes,
            edges: data.edges,
            width: Float(width),
            height: Float(height)
        )

        // Generate frames with animation
        for frameIndex in 0 ..< totalFrames {
            let progress = Double(frameIndex) / Double(totalFrames)

            let frame = VisualizationFrame(
                index: frameIndex,
                nodes: animateNodes(nodePositions, progress: progress),
                edges: animateEdges(data.edges, nodePositions: nodePositions, progress: progress)
            )

            frames.append(frame)
        }

        logger.info("Generated \(frames.count) frames")
        return frames
    }

    private func computeForceDirectedLayout(
        nodes: [Shared.GraphData.Node],
        edges: [Shared.GraphData.Edge],
        width: Float,
        height: Float
    ) async -> [String: SIMD2<Float>] {
        // Map String IDs to UInt32 indices
        var idToIndex: [String: UInt32] = [:]
        var indexToId: [UInt32: String] = [:]

        for (i, node) in nodes.enumerated() {
            let idx = UInt32(i)
            idToIndex[node.id] = idx
            indexToId[idx] = node.id
        }

        // Create LayoutNodes
        var layoutNodes: [LayoutNode] = nodes.map { node in
            let idx = idToIndex[node.id]!

            var pos = SIMD2<Float>.zero
            if let fixedPos = node.position, fixedPos.count >= 2 {
                pos = SIMD2<Float>(fixedPos[0], fixedPos[1])
            } else {
                // Random initial position centered
                let angle = Float.random(in: 0 ..< (2 * .pi))
                let radius = min(width, height) * 0.1
                pos = SIMD2<Float>(
                    width / 2 + cos(angle) * radius,
                    height / 2 + sin(angle) * radius
                )
            }

            return LayoutNode(
                position: pos,
                velocity: .zero,
                mass: 1.0,
                id: idx
            )
        }

        // Create Edges
        let layoutEdges: [SIMD2<UInt32>] = edges.compactMap { edge in
            guard let src = idToIndex[edge.source],
                  let dst = idToIndex[edge.target] else { return nil }
            return SIMD2<UInt32>(src, dst)
        }

        // Run Layout
        if let engine = layoutEngine {
            let k = sqrt((width * height) / Float(nodes.count))
            let params = LayoutParams(
                repulsionStrength: k * k * 0.5,
                attractionStrength: 0.02,
                damping: 0.9,
                timeStep: 0.5,
                bounds: SIMD4<Float>(0, 0, width, height),
                maxIterations: 200,
                convergenceThreshold: 0.1
            )

            do {
                let iterations = try await engine.layout(nodes: &layoutNodes, edges: layoutEdges, params: params)
                logger.info("GPU Layout converged in \(iterations) iterations")
            } catch {
                logger.error("GPU Layout failed: \(error). Falling back to CPU.")
                // Fallback logic could go here, but for now we just return initial positions
            }
        } else {
            logger.warning("GraphLayoutEngine not available. Skipping layout.")
        }

        // Map back to positions
        var positions: [String: SIMD2<Float>] = [:]
        for node in layoutNodes {
            if let id = indexToId[node.id] {
                positions[id] = node.position
            }
        }

        return positions
    }

    private func animateNodes(_ positions: [String: SIMD2<Float>], progress: Double) -> [NodeDrawable] {
        let fadeInDuration = 0.3
        let alpha = progress < fadeInDuration ? Float(progress / fadeInDuration) : 1.0

        return positions.map { id, pos in
            NodeDrawable(
                id: id,
                position: pos,
                size: 20.0,
                color: SIMD4<Float>(0.3, 0.6, 0.9, alpha)
            )
        }
    }

    private func animateEdges(
        _ edges: [Shared.GraphData.Edge],
        nodePositions: [String: SIMD2<Float>],
        progress: Double
    ) -> [EdgeDrawable] {
        let fadeInDuration = 0.3
        let alpha = progress < fadeInDuration ? Float(progress / fadeInDuration) : 1.0

        return edges.compactMap { edge in
            guard let sourcePos = nodePositions[edge.source],
                  let targetPos = nodePositions[edge.target]
            else {
                return nil
            }

            return EdgeDrawable(
                source: sourcePos,
                target: targetPos,
                thickness: 2.0,
                color: SIMD4<Float>(0.5, 0.5, 0.5, alpha * 0.6)
            )
        }
    }
}

/// Visualization frame data
public struct VisualizationFrame: Sendable {
    public let index: Int
    public let nodes: [NodeDrawable]
    public let edges: [EdgeDrawable]
    public let chartElements: [ChartDrawable]?

    public init(index: Int, nodes: [NodeDrawable], edges: [EdgeDrawable], chartElements: [ChartDrawable]? = nil) {
        self.index = index
        self.nodes = nodes
        self.edges = edges
        self.chartElements = chartElements
    }
}

public struct ChartDrawable: Sendable {
    public let type: ChartElementType
    public let rect: SIMD4<Float> // x, y, w, h (or radius for pie)
    public let color: SIMD4<Float>
    public let value: Float // Start Angle for Pie
    public let extra: Float // End Angle for Pie

    public init(type: ChartElementType, rect: SIMD4<Float>, color: SIMD4<Float>, value: Float = 0, extra: Float = 0) {
        self.type = type
        self.rect = rect
        self.color = color
        self.value = value
        self.extra = extra
    }
}

public enum ChartElementType: Sendable {
    case bar
    case pieSlice
}

public struct NodeDrawable: Sendable {
    public let id: String
    public let position: SIMD2<Float>
    public let size: Float
    public let color: SIMD4<Float>

    public init(id: String, position: SIMD2<Float>, size: Float, color: SIMD4<Float>) {
        self.id = id
        self.position = position
        self.size = size
        self.color = color
    }
}

public struct EdgeDrawable: Sendable {
    public let source: SIMD2<Float>
    public let target: SIMD2<Float>
    public let thickness: Float
    public let color: SIMD4<Float>

    public init(source: SIMD2<Float>, target: SIMD2<Float>, thickness: Float, color: SIMD4<Float>) {
        self.source = source
        self.target = target
        self.thickness = thickness
        self.color = color
    }
}
