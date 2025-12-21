// LayeredPipeline.swift
// MetaVisRender
//
// Created for Sprint 3: Manifest Unification
// Pipeline for rendering layer-based compositions

import Metal
import MetalKit
import simd

public class LayeredPipeline: RenderPipeline {
    public let device: MTLDevice
    public let compositePass: CompositePass
    public let backgroundPass: BackgroundPass
    
    public init(device: MTLDevice) throws {
        self.device = device
        self.compositePass = try CompositePass(device: device)
        self.backgroundPass = try BackgroundPass(device: device)
    }
    
    public func render(context: RenderContext) throws {
        let commandBuffer = context.commandBuffer
        let time = Float(context.time)
        
        guard let outputTexture = context.renderPassDescriptor.colorAttachments[0].texture else {
            return
        }
        
        // 1. Render base background (if any)
        if let procBackground = context.scene.proceduralBackground {
            try backgroundPass.render(
                commandBuffer: commandBuffer,
                background: procBackground,
                outputTexture: outputTexture,
                time: time
            )
        }
        
        // 2. Process layers
        for layer in context.scene.layers {
            let base = layer.baseProperties
            guard base.enabled else { continue }
            
            // Check timing
            if time < base.startTime || (base.duration > 0 && time > base.startTime + base.duration) {
                continue
            }
            
            switch layer {
            case .solid(let solidLayer):
                // Create a temp texture for the solid layer
                let desc = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: outputTexture.pixelFormat,
                    width: outputTexture.width,
                    height: outputTexture.height,
                    mipmapped: false
                )
                desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
                
                guard let layerTexture = device.makeTexture(descriptor: desc) else { continue }
                
                // Render solid color to layerTexture
                let colorRGB = SIMD3<Float>(solidLayer.color.x, solidLayer.color.y, solidLayer.color.z)
                let bgDef = BackgroundDefinition.solid(SolidBackground(color: colorRGB))
                try backgroundPass.render(
                    commandBuffer: commandBuffer,
                    background: bgDef,
                    outputTexture: layerTexture,
                    time: time
                )
                
                // Composite layerTexture over outputTexture
                let composited = compositePass.composite(
                    background: outputTexture,
                    foreground: layerTexture,
                    mask: nil,
                    params: CompositeParams(
                        mode: CompositeBlendMode(base.blendMode),
                        maskThreshold: 0.5,
                        edgeSoftness: 0.05,
                        foregroundOpacity: base.opacity
                    ),
                    commandBuffer: commandBuffer
                )
                
                // Copy result back to outputTexture
                if let blit = commandBuffer.makeBlitCommandEncoder() {
                    blit.copy(from: composited, to: outputTexture)
                    blit.endEncoding()
                }
                
            case .procedural(let procLayer):
                // Similar to solid but with procedural background
                let desc = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: outputTexture.pixelFormat,
                    width: outputTexture.width,
                    height: outputTexture.height,
                    mipmapped: false
                )
                desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
                
                guard let layerTexture = device.makeTexture(descriptor: desc) else { continue }
                
                try backgroundPass.render(
                    commandBuffer: commandBuffer,
                    background: procLayer.background,
                    outputTexture: layerTexture,
                    time: time
                )
                
                let composited = compositePass.composite(
                    background: outputTexture,
                    foreground: layerTexture,
                    mask: nil,
                    params: CompositeParams(
                        mode: CompositeBlendMode(base.blendMode),
                        maskThreshold: 0.5,
                        edgeSoftness: 0.05,
                        foregroundOpacity: base.opacity
                    ),
                    commandBuffer: commandBuffer
                )
                
                if let blit = commandBuffer.makeBlitCommandEncoder() {
                    blit.copy(from: composited, to: outputTexture)
                    blit.endEncoding()
                }
                
            default:
                // Other layers not yet supported in this pass
                break
            }
        }
    }
}
