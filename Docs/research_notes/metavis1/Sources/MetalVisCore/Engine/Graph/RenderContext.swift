import Foundation
import Metal
import simd

/// A shared state object passed to every Render Pass in the graph.
/// Contains all the context needed to render a specific frame (or subframe).
/// See: SPEC_03_RENDER_GRAPH.md
public class RenderContext {
    
    // MARK: - Metal Resources
    
    /// The Metal device used for creating resources.
    public let device: MTLDevice
    
    /// The command buffer for encoding GPU commands.
    public let commandBuffer: MTLCommandBuffer
    
    // MARK: - Frame Properties
    
    /// The resolution of the render target (width, height).
    public let resolution: SIMD2<Int>
    
    /// The current frame time in seconds.
    public let time: TimeInterval
    
    /// The current subframe index (0...N) for temporal accumulation.
    public let subframe: Int
    
    /// The total number of subframes being rendered.
    public let totalSubframes: Int
    
    // MARK: - Scene Data
    
    /// The scene description (Camera, Lights, Actors).
    public let scene: Scene
    
    // MARK: - Initialization
    
    public init(device: MTLDevice,
                commandBuffer: MTLCommandBuffer,
                resolution: SIMD2<Int>,
                time: TimeInterval,
                subframe: Int = 0,
                totalSubframes: Int = 1,
                scene: Scene) {
        self.device = device
        self.commandBuffer = commandBuffer
        self.resolution = resolution
        self.time = time
        self.subframe = subframe
        self.totalSubframes = totalSubframes
        self.scene = scene
    }
    
    // MARK: - Helpers
    
    /// Returns the aspect ratio of the render target.
    public var aspectRatio: Float {
        return Float(resolution.x) / Float(resolution.y)
    }
    
    /// Convenience accessor for the scene's camera.
    /// This is the authoritative source for all camera parameters.
    public var camera: PhysicalCamera {
        return scene.camera
    }
}
