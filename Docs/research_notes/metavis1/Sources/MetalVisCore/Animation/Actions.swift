import Foundation
import simd

// MARK: - Action Protocol

/// Base protocol for camera/graph actions
public protocol AnimationAction: Codable, Sendable {
    /// Action type identifier
    var type: String { get }

    /// Duration of the action in seconds
    var duration: Double { get }

    /// Easing function for this action
    var easing: Easing { get }
}

// MARK: - Focus Action

/// Focus camera on a specific node
public struct FocusAction: AnimationAction {
    public var type = "focus"
    public let nodeId: String
    public let duration: Double
    public let easing: Easing
    public let distance: Float

    public init(nodeId: String, distance: Float = 5.0, duration: Double = 2.0, easing: Easing = .easeInOut) {
        self.nodeId = nodeId
        self.distance = distance
        self.duration = duration
        self.easing = easing
    }
}

// MARK: - Zoom Action

/// Zoom in/out by changing camera distance
public struct ZoomAction: AnimationAction {
    public var type = "zoom"
    public let factor: Float // < 1.0 = zoom in, > 1.0 = zoom out
    public let duration: Double
    public let easing: Easing

    public init(factor: Float, duration: Double = 1.5, easing: Easing = .easeInOut) {
        self.factor = factor
        self.duration = duration
        self.easing = easing
    }
}

// MARK: - Orbit Action

/// Orbit camera around current lookAt point
public struct OrbitAction: AnimationAction {
    public var type = "orbit"
    public let angle: Float // Degrees to rotate
    public let axis: SIMD3<Float> // Rotation axis (e.g., [0, 1, 0] for Y)
    public let duration: Double
    public let easing: Easing

    public init(angle: Float, axis: SIMD3<Float> = SIMD3<Float>(0, 1, 0), duration: Double = 3.0, easing: Easing = .linear) {
        self.angle = angle
        self.axis = axis
        self.duration = duration
        self.easing = easing
    }
}

// MARK: - Trace Action

/// Follow edges from source to target nodes
public struct TraceAction: AnimationAction {
    public var type = "trace"
    public let edgePath: [String] // Node IDs forming path
    public let highlightEdges: Bool
    public let duration: Double
    public let easing: Easing

    public init(edgePath: [String], highlightEdges: Bool = true, duration: Double = 4.0, easing: Easing = .easeInOut) {
        self.edgePath = edgePath
        self.highlightEdges = highlightEdges
        self.duration = duration
        self.easing = easing
    }
}

// MARK: - Reveal Action

/// Gradually reveal nodes (fade-in, scale-up)
public struct RevealAction: AnimationAction {
    public var type = "reveal"
    public let nodeIds: [String]
    public let staggerDelay: Double // Delay between each node
    public let revealStyle: String // "fade", "scale", "slide"
    public let duration: Double
    public let easing: Easing

    public init(nodeIds: [String], staggerDelay: Double = 0.2, revealStyle: String = "fadeIn", duration: Double = 3.0, easing: Easing = .easeOut) {
        self.nodeIds = nodeIds
        self.staggerDelay = staggerDelay
        self.revealStyle = revealStyle
        self.duration = duration
        self.easing = easing
    }
}

// MARK: - Highlight Action

/// Highlight specific nodes/edges with color/glow
public struct HighlightAction: AnimationAction {
    public var type = "highlight"
    public let nodeIds: [String]
    public let edgeIds: [String]?
    public let intensity: Float // 0.0 - 1.0
    public let propagate: Bool // Highlight connected nodes
    public let duration: Double
    public let easing: Easing

    public init(nodeIds: [String], edgeIds: [String]? = nil, intensity: Float = 0.8, propagate: Bool = false, duration: Double = 2.0, easing: Easing = .easeInOut) {
        self.nodeIds = nodeIds
        self.edgeIds = edgeIds
        self.intensity = intensity
        self.propagate = propagate
        self.duration = duration
        self.easing = easing
    }
}

// MARK: - Compare Action

/// Show two nodes side-by-side (split view effect)
public struct CompareAction: AnimationAction {
    public var type = "compare"
    public let nodeIds: [String] // Typically 2 nodes
    public let splitMode: String // "horizontal" or "vertical"
    public let duration: Double
    public let easing: Easing

    public init(nodeIds: [String], splitMode: String = "horizontal", duration: Double = 3.0, easing: Easing = .easeInOut) {
        self.nodeIds = nodeIds
        self.splitMode = splitMode
        self.duration = duration
        self.easing = easing
    }
}

// MARK: - Action Container

/// Container for polymorphic action decoding
public enum CameraAction: Codable, Sendable {
    case focus(FocusAction)
    case zoom(ZoomAction)
    case orbit(OrbitAction)
    case trace(TraceAction)
    case reveal(RevealAction)
    case highlight(HighlightAction)
    case compare(CompareAction)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        let singleContainer = try decoder.singleValueContainer()

        switch type {
        case "focus":
            self = try .focus(singleContainer.decode(FocusAction.self))
        case "zoom":
            self = try .zoom(singleContainer.decode(ZoomAction.self))
        case "orbit":
            self = try .orbit(singleContainer.decode(OrbitAction.self))
        case "trace":
            self = try .trace(singleContainer.decode(TraceAction.self))
        case "reveal":
            self = try .reveal(singleContainer.decode(RevealAction.self))
        case "highlight":
            self = try .highlight(singleContainer.decode(HighlightAction.self))
        case "compare":
            self = try .compare(singleContainer.decode(CompareAction.self))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown action type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .focus(action):
            try action.encode(to: encoder)
        case let .zoom(action):
            try action.encode(to: encoder)
        case let .orbit(action):
            try action.encode(to: encoder)
        case let .trace(action):
            try action.encode(to: encoder)
        case let .reveal(action):
            try action.encode(to: encoder)
        case let .highlight(action):
            try action.encode(to: encoder)
        case let .compare(action):
            try action.encode(to: encoder)
        }
    }

    public var duration: Double {
        switch self {
        case let .focus(a): return a.duration
        case let .zoom(a): return a.duration
        case let .orbit(a): return a.duration
        case let .trace(a): return a.duration
        case let .reveal(a): return a.duration
        case let .highlight(a): return a.duration
        case let .compare(a): return a.duration
        }
    }
}
