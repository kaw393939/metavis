import Foundation
import Metal

/// Timed effect state for timeline-aware effect control
public struct TimedEffectState {
    public let timestamp: Double
    public let bloom: (enabled: Bool, intensity: Float, threshold: Float)?
    public let halation: (enabled: Bool, intensity: Float, threshold: Float)?
    public let vignette: (enabled: Bool, intensity: Float)?
    public let filmGrain: (enabled: Bool, intensity: Float)?
    public let chromaticAberration: (enabled: Bool, intensity: Float)?
    
    public init(timestamp: Double,
                bloom: (enabled: Bool, intensity: Float, threshold: Float)? = nil,
                halation: (enabled: Bool, intensity: Float, threshold: Float)? = nil,
                vignette: (enabled: Bool, intensity: Float)? = nil,
                filmGrain: (enabled: Bool, intensity: Float)? = nil,
                chromaticAberration: (enabled: Bool, intensity: Float)? = nil) {
        self.timestamp = timestamp
        self.bloom = bloom
        self.halation = halation
        self.vignette = vignette
        self.filmGrain = filmGrain
        self.chromaticAberration = chromaticAberration
    }
}

/// The executor for the Render Graph.
/// Orchestrates the execution of Render Passes and manages resource flow.
/// See: SPEC_03_RENDER_GRAPH.md
public class RenderPipeline {
    
    /// The ordered list of passes to execute.
    public var passes: [RenderPass] = []
    
    /// Timeline of effect states for dynamic effect control
    public var effectTimeline: [TimedEffectState] = []
    
    public init(device: MTLDevice) {
    }
    
    /// Adds a pass to the pipeline.
    public func addPass(_ pass: RenderPass) {
        passes.append(pass)
    }
    
    /// Apply effect states from timeline based on current time
    private func applyEffectStates(at time: Double) {
        // Find the most recent effect state at or before this time
        // Effect states are cumulative - later states override earlier ones
        var currentBloom: (enabled: Bool, intensity: Float, threshold: Float)?
        var currentHalation: (enabled: Bool, intensity: Float, threshold: Float)?
        var currentVignette: (enabled: Bool, intensity: Float)?
        var currentFilmGrain: (enabled: Bool, intensity: Float)?
        var currentChromaticAberration: (enabled: Bool, intensity: Float)?
        
        for state in effectTimeline where state.timestamp <= time {
            if let bloom = state.bloom {
                currentBloom = bloom
            }
            if let halation = state.halation {
                currentHalation = halation
            }
            if let vignette = state.vignette {
                currentVignette = vignette
            }
            if let filmGrain = state.filmGrain {
                currentFilmGrain = filmGrain
            }
            if let ca = state.chromaticAberration {
                currentChromaticAberration = ca
            }
        }
        
        // Apply to passes
        for pass in passes {
            if let bloomPass = pass as? BloomPass {
                if let bloom = currentBloom {
                    bloomPass.intensity = bloom.enabled ? bloom.intensity : 0.0
                    bloomPass.threshold = bloom.threshold
                }
            } else if let halationPass = pass as? HalationPass {
                if let halation = currentHalation {
                    halationPass.intensity = halation.enabled ? halation.intensity : 0.0
                    halationPass.threshold = halation.threshold
                }
            } else if let vignettePass = pass as? VignettePass {
                if let vignette = currentVignette {
                    vignettePass.intensity = vignette.enabled ? vignette.intensity : 0.0
                }
            } else if let grainPass = pass as? FilmGrainPass {
                if let grain = currentFilmGrain {
                    grainPass.intensity = grain.enabled ? grain.intensity : 0.0
                }
            } else if let postPass = pass as? PostProcessingPass {
                // Apply all effects to Uber Post-Processing Pass
                if let bloom = currentBloom {
                    postPass.config.bloomEnabled = bloom.enabled
                    postPass.config.bloomStrength = bloom.intensity
                    postPass.config.bloomThreshold = bloom.threshold
                }
                if let halation = currentHalation {
                    postPass.config.halationEnabled = halation.enabled
                    postPass.config.halationIntensity = halation.intensity
                    postPass.config.halationThreshold = halation.threshold
                }
                if let vignette = currentVignette {
                    postPass.config.vignetteIntensity = vignette.enabled ? vignette.intensity : 0.0
                }
                if let grain = currentFilmGrain {
                    postPass.config.filmGrainStrength = grain.enabled ? grain.intensity : 0.0
                }
                if let ca = currentChromaticAberration {
                    postPass.config.chromaticAberrationEnabled = ca.enabled
                    postPass.config.chromaticAberrationIntensity = ca.intensity
                }
            }
        }
    }
    
    /// Executes the pipeline for a single frame (or subframe).
    /// - Parameter context: The render context.
    /// - Returns: The final output texture (usually named "DisplayBuffer").
    public func render(context: RenderContext) throws -> MTLTexture? {
        
        // Apply timeline-based effect states before rendering
        if !effectTimeline.isEmpty {
            applyEffectStates(at: context.time)
        }
        
        // Dictionary to hold active textures by name
        var textureRegistry: [String: MTLTexture] = [:]
        
        // 1. Execute Passes
        for pass in passes {
            
            // A. Resolve Inputs
            var inputs: [String: MTLTexture] = [:]
            for inputName in pass.inputs {
                guard let texture = textureRegistry[inputName] else {
                    throw RenderError.missingInput(pass: pass.label, input: inputName)
                }
                inputs[inputName] = texture
            }
            
            // B. Allocate Outputs
            var outputs: [String: MTLTexture] = [:]
            for outputName in pass.outputs {
                // Check if texture already exists in registry (for cumulative rendering)
                if let existingTexture = textureRegistry[outputName] {
                    outputs[outputName] = existingTexture
                    continue
                }

                // Define standard descriptor (Linear HDR usually)
                // TODO: Allow passes to specify custom descriptors
                let pixelFormat: MTLPixelFormat = (outputName == "depth_buffer") ? .depth32Float : .rgba16Float
                
                let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat,
                                                                    width: context.resolution.x,
                                                                    height: context.resolution.y,
                                                                    mipmapped: false)
                desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
                desc.storageMode = .private
                
                guard let texture = context.device.makeTexture(descriptor: desc) else {
                    throw RenderError.allocationFailed(texture: outputName)
                }
                
                // CRITICAL: Clear before use to prevent purple noise (uninitialized VRAM)
                clearTexture(texture, using: context.commandBuffer)
                
                outputs[outputName] = texture
                textureRegistry[outputName] = texture
            }
            
            // C. Execute Pass
            print("DEBUG: Executing pass '\(pass.label)' with inputs: \(inputs.keys.sorted()) → outputs: \(outputs.keys.sorted())")
            try pass.execute(context: context, inputTextures: inputs, outputTextures: outputs)
            
            // D. Release Inputs that are no longer needed?
            // For now, we keep them until the end of the frame for simplicity.
            // Optimization: Reference counting for textures.
        }
        
        // 2. Retrieve Final Output
        // Prefer "display_buffer", then the output of the last pass, then any texture
        var finalOutput: MTLTexture?
        
        if let display = textureRegistry["display_buffer"] {
            finalOutput = display
        } else if let lastPass = passes.last, 
                  let lastOutputName = lastPass.outputs.first,
                  let lastTexture = textureRegistry[lastOutputName] {
            finalOutput = lastTexture
        } else {
            finalOutput = textureRegistry.values.first
        }
        
        // 3. Cleanup (Return everything to pool EXCEPT the final output)
        // In a real engine, we'd copy the final output to a drawable and return everything.
        // For this implementation, we'll just return the texture and let the caller handle it,
        // but we should return intermediate textures.
        
        // [REMOVED] TexturePool cleanup - ARC handles deallocation now
        
        return finalOutput
    }
    
    /// Clears a texture to transparent black
    private func clearTexture(_ texture: MTLTexture, using commandBuffer: MTLCommandBuffer) {
        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = texture
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPass.colorAttachments[0].storeAction = .store
        
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) {
            encoder.label = "Clear \(texture.label ?? "texture")"
            encoder.endEncoding()
        }
    }
}

public enum RenderError: Error {
    case missingInput(pass: String, input: String)
    case allocationFailed(texture: String)
}
