import Foundation
import simd

/// State of a single node in the graph
public struct NodeState: Sendable {
    public var opacity: Float
    public var scale: Float
    public var highlightIntensity: Float
    public var color: SIMD3<Float>?

    public init(opacity: Float = 1.0, scale: Float = 1.0, highlightIntensity: Float = 0.0, color: SIMD3<Float>? = nil) {
        self.opacity = opacity
        self.scale = scale
        self.highlightIntensity = highlightIntensity
        self.color = color
    }
}

/// State of a single edge in the graph
public struct EdgeState: Sendable {
    public var opacity: Float
    public var thickness: Float
    public var flowProgress: Float // 0.0-1.0 for trace animation
    public var highlightIntensity: Float

    public init(opacity: Float = 1.0, thickness: Float = 1.0, flowProgress: Float = 0.0, highlightIntensity: Float = 0.0) {
        self.opacity = opacity
        self.thickness = thickness
        self.flowProgress = flowProgress
        self.highlightIntensity = highlightIntensity
    }
}

/// Complete graph animation state
public struct GraphState: Sendable {
    public var nodes: [String: NodeState]
    public var edges: [String: EdgeState]

    public init(nodes: [String: NodeState] = [:], edges: [String: EdgeState] = [:]) {
        self.nodes = nodes
        self.edges = edges
    }

    /// Get node state (returns default if not found)
    public func nodeState(_ id: String) -> NodeState {
        nodes[id] ?? NodeState()
    }

    /// Get edge state (returns default if not found)
    public func edgeState(_ id: String) -> EdgeState {
        edges[id] ?? EdgeState()
    }

    /// Set node state
    public mutating func setNode(_ id: String, state: NodeState) {
        nodes[id] = state
    }

    /// Set edge state
    public mutating func setEdge(_ id: String, state: EdgeState) {
        edges[id] = state
    }
}

// MARK: - Interpolatable Conformance

extension NodeState: Interpolatable {
    public static var zero: NodeState {
        NodeState(opacity: 0.0, scale: 0.0, highlightIntensity: 0.0)
    }

    public func interpolate(to target: NodeState, at t: Double) -> NodeState {
        let ft = Float(t)
        return NodeState(
            opacity: opacity + (target.opacity - opacity) * ft,
            scale: scale + (target.scale - scale) * ft,
            highlightIntensity: highlightIntensity + (target.highlightIntensity - highlightIntensity) * ft,
            color: {
                guard let selfColor = self.color, let targetColor = target.color else {
                    return self.color ?? target.color
                }
                return selfColor + (targetColor - selfColor) * ft
            }()
        )
    }
}

extension EdgeState: Interpolatable {
    public static var zero: EdgeState {
        EdgeState(opacity: 0.0, thickness: 0.0, flowProgress: 0.0, highlightIntensity: 0.0)
    }

    public func interpolate(to target: EdgeState, at t: Double) -> EdgeState {
        let ft = Float(t)
        return EdgeState(
            opacity: opacity + (target.opacity - opacity) * ft,
            thickness: thickness + (target.thickness - thickness) * ft,
            flowProgress: flowProgress + (target.flowProgress - flowProgress) * ft,
            highlightIntensity: highlightIntensity + (target.highlightIntensity - highlightIntensity) * ft
        )
    }
}

extension GraphState: Interpolatable {
    public static var zero: GraphState {
        GraphState()
    }

    public func interpolate(to target: GraphState, at t: Double) -> GraphState {
        var result = GraphState()

        // Interpolate all nodes (from both states)
        let allNodeIds = Set(nodes.keys).union(Set(target.nodes.keys))
        for id in allNodeIds {
            let fromState = nodes[id] ?? .zero
            let toState = target.nodes[id] ?? .zero
            result.nodes[id] = fromState.interpolate(to: toState, at: t)
        }

        // Interpolate all edges
        let allEdgeIds = Set(edges.keys).union(Set(target.edges.keys))
        for id in allEdgeIds {
            let fromState = edges[id] ?? .zero
            let toState = target.edges[id] ?? .zero
            result.edges[id] = fromState.interpolate(to: toState, at: t)
        }

        return result
    }
}

// MARK: - GraphAnimationTrack

/// Animation track for graph state changes
public struct GraphAnimationTrack: AnimationTrack, Sendable {
    public let keyframes: [Keyframe<GraphState>]

    public var duration: Double {
        keyframes.last?.time ?? 0.0
    }

    public init(keyframes: [Keyframe<GraphState>]) {
        self.keyframes = keyframes.sorted { $0.time < $1.time }
    }

    public func evaluate(at time: Double) -> GraphState {
        guard !keyframes.isEmpty else {
            return .zero
        }

        guard keyframes.count > 1 else {
            return keyframes[0].value
        }

        if time <= keyframes[0].time {
            return keyframes[0].value
        }

        if time >= keyframes[keyframes.count - 1].time {
            return keyframes[keyframes.count - 1].value
        }

        for i in 0 ..< (keyframes.count - 1) {
            let current = keyframes[i]
            let next = keyframes[i + 1]

            if time >= current.time && time <= next.time {
                let segmentDuration = next.time - current.time
                let t = (time - current.time) / segmentDuration
                let easedT = next.easing.evaluate(t)

                return current.value.interpolate(to: next.value, at: easedT)
            }
        }

        return keyframes.last!.value
    }
}

// MARK: - Action Helpers

public extension GraphAnimationTrack {
    /// Create reveal animation for nodes
    static func reveal(
        nodeIds: [String],
        startTime: Double,
        duration _: Double,
        staggerDelay: Double = 0.2,
        easing: Easing = .easeOut
    ) -> GraphAnimationTrack {
        var keyframes: [Keyframe<GraphState>] = []

        // Start with all nodes hidden
        var startState = GraphState()
        for id in nodeIds {
            startState.setNode(id, state: NodeState(opacity: 0.0, scale: 0.5))
        }
        keyframes.append(Keyframe(time: startTime, value: startState, easing: easing))

        // Reveal each node with stagger
        for index in nodeIds.indices {
            let revealTime = startTime + Double(index) * staggerDelay
            var state = startState

            // Set all previous nodes to fully visible
            for prevIndex in 0 ... index {
                state.setNode(nodeIds[prevIndex], state: NodeState(opacity: 1.0, scale: 1.0))
            }

            keyframes.append(Keyframe(time: revealTime, value: state, easing: easing))
        }

        return GraphAnimationTrack(keyframes: keyframes)
    }

    /// Create highlight animation
    static func highlight(
        nodeIds: [String],
        startTime: Double,
        duration: Double,
        intensity: Float = 0.8,
        easing: Easing = .easeInOut
    ) -> GraphAnimationTrack {
        var startState = GraphState()
        var endState = GraphState()

        for id in nodeIds {
            startState.setNode(id, state: NodeState(highlightIntensity: 0.0))
            endState.setNode(id, state: NodeState(highlightIntensity: intensity))
        }

        return GraphAnimationTrack(keyframes: [
            Keyframe(time: startTime, value: startState, easing: easing),
            Keyframe(time: startTime + duration, value: endState, easing: easing)
        ])
    }

    /// Create trace animation along edges
    static func trace(
        edgeIds: [String],
        startTime: Double,
        duration: Double,
        easing: Easing = .linear
    ) -> GraphAnimationTrack {
        var keyframes: [Keyframe<GraphState>] = []
        let timePerEdge = duration / Double(edgeIds.count)

        for (index, edgeId) in edgeIds.enumerated() {
            let time = startTime + Double(index) * timePerEdge
            var state = GraphState()

            // Highlight current edge
            state.setEdge(edgeId, state: EdgeState(
                opacity: 1.0,
                thickness: 1.5,
                flowProgress: Float(index) / Float(edgeIds.count),
                highlightIntensity: 1.0
            ))

            keyframes.append(Keyframe(time: time, value: state, easing: easing))
        }

        return GraphAnimationTrack(keyframes: keyframes)
    }
}
