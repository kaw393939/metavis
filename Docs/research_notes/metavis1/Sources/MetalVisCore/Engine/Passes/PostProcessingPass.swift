import Metal
import simd

public class PostProcessingPass: RenderPass {
    public var label: String = "Uber Post-Processing"
    public var inputs: [String] = ["main_buffer"]
    public var outputs: [String] = ["display_buffer"]
    
    private let renderer: PostProcessingRenderer
    public var config: PostProcessingConfig
    
    public init(device: MTLDevice, config: PostProcessingConfig = PostProcessingConfig(preset: .balanced)) {
        // We force try here because if we can't create the renderer, the engine is broken
        self.renderer = try! PostProcessingRenderer(device: device)
        self.config = config
    }
    
    public func execute(context: RenderContext,
                        inputTextures: [String: MTLTexture],
                        outputTextures: [String: MTLTexture]) throws {
        
        guard let inputTexture = inputTextures[inputs[0]],
              let outputTexture = outputTextures[outputs[0]] else {
            return
        }
        
        // Update config with context time if needed (though renderer handles time internally via context usually)
        // But PostProcessingRenderer.processHDR creates its own context.
        // We should probably update PostProcessingRenderer to accept an external context or time,
        // but for now let's trust it uses CFAbsoluteTime or we can modify it later.
        // Wait, PostProcessingRenderer.processHDR uses CFAbsoluteTimeGetCurrent().
        // Ideally it should use context.time for deterministic rendering.
        // I'll note this as a future improvement.
        
        // Execute the Uber Shader Pipeline
        // processHDR returns a NEW texture.
        // But RenderPass expects us to write to 'outputTexture'.
        // We can blit the result of processHDR to outputTexture, 
        // OR we can modify processHDR to accept an output texture.
        
        // Let's check processHDR signature again.
        // public func processHDR(inputTexture: MTLTexture, config: PostProcessingConfig) throws -> MTLTexture
        
        // Pass outputTexture directly to renderer to avoid format mismatch issues during blit
        _ = try renderer.processHDR(
            inputTexture: inputTexture, 
            config: config, 
            commandBuffer: context.commandBuffer,
            outputTexture: outputTexture
        )
        
        // No need to blit anymore as renderer writes directly to outputTexture
    }
}
