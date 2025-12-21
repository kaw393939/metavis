import Metal

/// A composable stage in the rendering pipeline.
/// Implementations should adhere to TBDR best practices:
/// - Use `loadAction = .clear` or `.dontCare` whenever possible.
/// - Use `storeAction = .dontCare` for intermediate buffers not needed later.
/// - Use `context.texturePool` to acquire transient render targets.
public protocol RenderPass {
    /// Debug label for the pass.
    var label: String { get }
    
    /// Called once during pipeline initialization to compile state objects.
    func setup(device: MTLDevice, library: MTLLibrary) throws
    
    /// Called when the render resolution changes.
    /// Use this to resize internal buffers or release them to the pool.
    func resize(resolution: SIMD2<Int>)
    
    /// Encodes the pass commands into the buffer.
    func execute(commandBuffer: MTLCommandBuffer, context: RenderContext) throws
}

// Default implementation for resize
public extension RenderPass {
    func resize(resolution: SIMD2<Int>) {}
}
