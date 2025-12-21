import Foundation
import simd

/// Optional per-frame metadata used by the render-graph compiler.
///
/// This intentionally lives in MetaVisCore so higher-level modules (e.g. perception)
/// can provide data without creating a dependency from simulation -> perception.
public struct RenderFrameContext: Sendable, Equatable {
    /// Normalized face rectangles in 0..1 space with top-left origin.
    /// Value is `[x, y, w, h]` per face.
    public var faceRectsByClipID: [UUID: [SIMD4<Float>]]

    public init(faceRectsByClipID: [UUID: [SIMD4<Float>]] = [:]) {
        self.faceRectsByClipID = faceRectsByClipID
    }
}
