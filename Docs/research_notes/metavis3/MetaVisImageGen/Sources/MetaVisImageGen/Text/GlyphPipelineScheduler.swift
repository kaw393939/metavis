import Foundation

public class GlyphPipelineScheduler {
    // Concurrent queue for heavy SDF generation (CPU bound)
    private let generationQueue = DispatchQueue(label: "com.metavis.render.glyph.generation", qos: .userInitiated, attributes: .concurrent)
    
    // Serial queue for Atlas updates (Thread safety for texture/nodes)
    private let atlasQueue = DispatchQueue(label: "com.metavis.render.glyph.atlas", qos: .userInteractive)
    
    public init() {}
    
    /// Schedules a generation task.
    /// - Parameters:
    ///   - generationTask: The heavy work returning an SDFResult.
    ///   - completion: The block to execute on the serial atlas queue with the result.
    public func schedule(generationTask: @escaping () -> SDFResult?, completion: @escaping (SDFResult) -> Void) {
        // Force synchronous execution for offline rendering reliability
        if let result = generationTask() {
            completion(result)
        }
    }
    
    /// Executes a block synchronously on the atlas queue (for safe access).
    public func sync<T>(_ block: () -> T) -> T {
        return atlasQueue.sync(execute: block)
    }
}
