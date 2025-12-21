import Foundation
import Metal

/// A single node in the Render Graph.
/// Represents a discrete rendering operation (e.g., "Bloom", "Geometry", "Composite").
/// See: SPEC_03_RENDER_GRAPH.md
public protocol RenderPass: AnyObject {
    
    /// A human-readable label for debugging and profiling.
    var label: String { get }
    
    /// The names of the textures this pass requires as input.
    /// These must match the `outputs` of preceding passes.
    var inputs: [String] { get set }
    
    /// The names of the textures this pass produces.
    var outputs: [String] { get set }
    
    /// Executes the render pass.
    /// - Parameters:
    ///   - context: The shared render context (Device, Scene, Time).
    ///   - inputTextures: A dictionary of input textures keyed by name.
    ///   - outputTextures: A dictionary of output textures keyed by name.
    /// - Throws: Errors if resources are missing or encoding fails.
    func execute(context: RenderContext,
                 inputTextures: [String: MTLTexture],
                 outputTextures: [String: MTLTexture]) throws
}
