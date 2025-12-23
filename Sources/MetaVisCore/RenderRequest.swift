import Foundation

/// The Canonical Input for the Simulation Engine.
/// This struct must contain EVERYTHING needed to render a frame.
/// Start stateless, end stateless.
public struct RenderRequest: Sendable {
    public enum DisplayTarget: Sendable, Equatable {
        case sdrRec709
        case hdrPQ1000
    }

    /// High-level render policy tier used to configure engine defaults at runtime.
    ///
    /// This is intentionally separate from `quality` (which describes target resolution/fidelity)
    /// so product/runtime can clamp or trade performance vs quality deterministically.
    public let renderPolicy: RenderPolicyTier

    public enum EdgeCompatibilityPolicy: Sendable, Equatable {
        /// Keep the graph as-authored; record a warning when a node consumes an input whose
        /// dimensions don't match the node's output dimensions.
        case requireExplicitAdapters

        /// When a node consumes an input whose dimensions don't match the node's output
        /// dimensions, automatically insert a bilinear resize step in the engine.
        case autoResizeBilinear

        /// When a node consumes an input whose dimensions don't match the node's output
        /// dimensions, automatically insert a bicubic resize step in the engine.
        case autoResizeBicubic
    }

    public let id: UUID
    public let graph: RenderGraph
    public let time: Time
    public let quality: QualityProfile

    /// Output display target. This selects the terminal ODT at the root of the graph.
    ///
    /// Default: `.sdrRec709` to preserve shipping behavior.
    public let displayTarget: DisplayTarget

    /// Optional hint about the render cadence (e.g. export FPS). Used for deterministic
    /// sampling heuristics when a source provides insufficient timing metadata.
    public let renderFPS: Double?

    /// Policy for handling mixed-resolution edges inside the render graph.
    public let edgePolicy: EdgeCompatibilityPolicy

    /// When true, the engine may skip CPU readback of the rendered output and return `imageBuffer=nil`.
    /// Intended for benchmarks/tests that only need GPU timings.
    public let skipReadback: Bool
    
    // In a real implementation, this would hold the Asset Registry or Handles.
    // For now, we mock it.
    public let assets: [String: String] // AssetID : Path
    
    public init(
        id: UUID = UUID(),
        graph: RenderGraph,
        time: Time,
        quality: QualityProfile,
        assets: [String: String] = [:],
        renderFPS: Double? = nil,
        renderPolicy: RenderPolicyTier = .creator,
        displayTarget: DisplayTarget? = nil,
        edgePolicy: EdgeCompatibilityPolicy? = nil,
        skipReadback: Bool = false
    ) {
        self.id = id
        self.graph = graph
        self.time = time
        self.quality = quality
        self.assets = assets
        self.renderFPS = renderFPS
        self.renderPolicy = renderPolicy
        self.displayTarget = displayTarget ?? .sdrRec709
        self.edgePolicy = edgePolicy ?? RenderPolicyCatalog.policy(for: renderPolicy).edgePolicy
        self.skipReadback = skipReadback
    }
}
