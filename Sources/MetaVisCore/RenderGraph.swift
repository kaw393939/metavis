import Foundation

/// A single operation in the render graph.
public struct RenderNode: Identifiable, Sendable, Codable {
    public struct OutputSpec: Sendable, Codable {
        public enum PixelFormat: String, Sendable, Codable {
            /// Scene-linear working format.
            case rgba16Float
            /// Common 8-bit display/output format.
            case bgra8Unorm
            /// Common 8-bit RGBA format.
            case rgba8Unorm
            /// Common 8-bit single-channel mask format.
            case r8Unorm
            /// Depth buffer format (used for depthAttachment clears / depth sampling).
            case depth32Float
        }

        public enum Resolution: String, Sendable, Codable {
            case full
            case half
            case quarter
            case fixed
        }

        public var resolution: Resolution
        public var pixelFormat: PixelFormat
        public var fixedWidth: Int?
        public var fixedHeight: Int?

        public init(
            resolution: Resolution = .full,
            pixelFormat: PixelFormat = .rgba16Float,
            fixedWidth: Int? = nil,
            fixedHeight: Int? = nil
        ) {
            self.resolution = resolution
            self.pixelFormat = pixelFormat
            self.fixedWidth = fixedWidth
            self.fixedHeight = fixedHeight
        }
    }

    public let id: UUID
    public let name: String
    public let shader: String           // Metal Kernel Name
    public let inputs: [String: UUID]   // Port Name : Input Node ID
    public let parameters: [String: NodeValue]
    /// Optional output contract for this node.
    /// If nil, the engine treats this as full-resolution output.
    public let output: OutputSpec?
    public let timing: TimeRange?       // If nil, valid for all t
    
    public init(
        id: UUID = UUID(),
        name: String,
        shader: String,
        inputs: [String: UUID] = [:],
        parameters: [String: NodeValue] = [:],
        output: OutputSpec? = nil,
        timing: TimeRange? = nil
    ) {
        self.id = id
        self.name = name
        self.shader = shader
        self.inputs = inputs
        self.parameters = parameters
        self.output = output
        self.timing = timing
    }
}

extension RenderNode {
    /// Resolve this node's output size from a base render size.
    ///
    /// This is intentionally pure + deterministic so it can be unit-tested.
    public func resolvedOutputSize(baseWidth: Int, baseHeight: Int) -> (width: Int, height: Int) {
        guard let output else { return (max(1, baseWidth), max(1, baseHeight)) }

        switch output.resolution {
        case .full:
            return (max(1, baseWidth), max(1, baseHeight))
        case .half:
            return (max(1, baseWidth / 2), max(1, baseHeight / 2))
        case .quarter:
            return (max(1, baseWidth / 4), max(1, baseHeight / 4))
        case .fixed:
            let w = output.fixedWidth ?? baseWidth
            let h = output.fixedHeight ?? baseHeight
            return (max(1, w), max(1, h))
        }
    }

    public func resolvedOutputPixelFormat() -> OutputSpec.PixelFormat {
        output?.pixelFormat ?? .rgba16Float
    }
}

/// The Directed Acyclic Graph describing a frame render.
public struct RenderGraph: Sendable, Codable {
    public let id: UUID
    public let nodes: [RenderNode]
    public let rootNodeID: UUID // The node to output
    
    public init(id: UUID = UUID(), nodes: [RenderNode], rootNodeID: UUID) {
        self.id = id
        self.nodes = nodes
        self.rootNodeID = rootNodeID
    }
}
