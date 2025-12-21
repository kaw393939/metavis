import Foundation

/// Narration segment with text and associated actions
public struct NarrationSegment: Codable, Sendable {
    public let text: String
    public let actions: [CameraAction]
    public let startTime: Double?
    public let duration: Double?

    public init(text: String, actions: [CameraAction] = [], startTime: Double? = nil, duration: Double? = nil) {
        self.text = text
        self.actions = actions
        self.startTime = startTime
        self.duration = duration
    }
}

/// Narration analyzer for duration calculation
public struct NarrationAnalyzer {
    public let wordsPerMinute: Double
    public let pauseMultiplier: Double

    public init(wordsPerMinute: Double = 150.0, pauseMultiplier: Double = 1.2) {
        self.wordsPerMinute = wordsPerMinute
        self.pauseMultiplier = pauseMultiplier
    }

    /// Estimate duration from word count
    public func estimateDuration(_ text: String) -> Double {
        let words = text.split(separator: " ").count
        let baseDuration = Double(words) / wordsPerMinute * 60.0
        return baseDuration * pauseMultiplier
    }

    /// Estimate duration for multiple segments
    public func estimateTotalDuration(_ segments: [NarrationSegment]) -> Double {
        segments.reduce(0.0) { total, segment in
            if let duration = segment.duration {
                return total + duration
            }
            return total + estimateDuration(segment.text)
        }
    }

    /// Calculate segment boundaries with auto-duration
    public func calculateSegmentTimes(_ segments: [NarrationSegment]) -> [(segment: NarrationSegment, startTime: Double, duration: Double)] {
        var result: [(NarrationSegment, Double, Double)] = []
        var currentTime = 0.0

        for segment in segments {
            let startTime = segment.startTime ?? currentTime
            let duration = segment.duration ?? estimateDuration(segment.text)

            result.append((segment, startTime, duration))
            currentTime = startTime + duration
        }

        return result
    }
}

/// Complete animation configuration
public struct AnimationConfig: Codable, Sendable {
    public let narration: [NarrationSegment]
    public let graph: GraphData
    public let style: RenderStyle?

    public init(narration: [NarrationSegment], graph: GraphData, style: RenderStyle? = nil) {
        self.narration = narration
        self.graph = graph
        self.style = style
    }
}

/// Graph data for animation
public struct GraphData: Codable, Sendable {
    public let nodes: [NodeData]
    public let edges: [EdgeData]

    public init(nodes: [NodeData], edges: [EdgeData]) {
        self.nodes = nodes
        self.edges = edges
    }
}

/// Node data
public struct NodeData: Codable, Sendable {
    public let id: String
    public let label: String
    public let position: [Float]? // Optional fixed position

    public init(id: String, label: String, position: [Float]? = nil) {
        self.id = id
        self.label = label
        self.position = position
    }
}

/// Edge data
public struct EdgeData: Codable, Sendable {
    public let id: String
    public let source: String
    public let target: String
    public let directed: Bool?

    public init(id: String, source: String, target: String, directed: Bool? = nil) {
        self.id = id
        self.source = source
        self.target = target
        self.directed = directed
    }
}

/// Render style configuration
public struct RenderStyle: Codable, Sendable {
    public let backgroundColor: [Float]?
    public let nodeColor: [Float]?
    public let edgeColor: [Float]?
    public let highlightColor: [Float]?

    public init(backgroundColor: [Float]? = nil, nodeColor: [Float]? = nil, edgeColor: [Float]? = nil, highlightColor: [Float]? = nil) {
        self.backgroundColor = backgroundColor
        self.nodeColor = nodeColor
        self.edgeColor = edgeColor
        self.highlightColor = highlightColor
    }
}
