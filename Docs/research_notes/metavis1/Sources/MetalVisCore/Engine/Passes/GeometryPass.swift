import Metal
import simd

public class GeometryPass: RenderPass {
    public var label: String = "Geometry Pass"
    public var inputs: [String] = [] // Usually reads nothing, just clears and draws
    public var outputs: [String] = ["main_buffer", "depth_buffer"]
    
    private var pipelineState: MTLRenderPipelineState?
    private var unlitPipelineState: MTLRenderPipelineState?
    private var texturedPipelineState: MTLRenderPipelineState?
    private var pbrPipelineState: MTLRenderPipelineState? // V6.0 PBR
    private var depthState: MTLDepthStencilState?
    private var transparentDepthState: MTLDepthStencilState?
    private let scene: Scene
    
    // Accumulation Buffer Support
    private var tempTexture: MTLTexture?
    private var tempDepthTexture: MTLTexture?
    private var accumulatePipeline: MTLRenderPipelineState?
    
    public init(device: MTLDevice, scene: Scene) {
        self.scene = scene
    }
    
    private func halton(index: Int, base: Int) -> Float {
        var f: Float = 1.0
        var r: Float = 0.0
        var i = index
        while i > 0 {
            f = f / Float(base)
            r = r + f * Float(i % base)
            i = i / base
        }
        return r
    }
    
    private func ensureTempTextures(device: MTLDevice, width: Int, height: Int) {
        if tempTexture == nil || tempTexture!.width != width || tempTexture!.height != height {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
            desc.usage = [.renderTarget, .shaderRead]
            tempTexture = device.makeTexture(descriptor: desc)
            
            let depthDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: width, height: height, mipmapped: false)
            depthDesc.usage = [.renderTarget]
            
            if device.supportsFamily(.apple1) {
                depthDesc.storageMode = .memoryless
            } else {
                depthDesc.storageMode = .private
            }
            
            tempDepthTexture = device.makeTexture(descriptor: depthDesc)
        }
    }
    
    public func execute(context: RenderContext,
                        inputTextures: [String: MTLTexture],
                        outputTextures: [String: MTLTexture]) throws {
        
        if pipelineState == nil {
            try buildPipeline(device: context.device)
        }
        
        guard let pipeline = pipelineState,
              let depthState = depthState,
              let colorTexture = outputTextures[outputs[0]],
              let depthTexture = outputTextures[outputs[1]] else {
            return
        }
        
        // Check for Depth of Field
        // Use 16 samples if fStop <= 0.1 (Validation/Cinematic Mode)
        // Disabled for standard validation to prevent double-blur with BokehPass
        let sampleCount = (scene.camera.fStop <= 0.1) ? 16 : 1
        
        if sampleCount > 1 {
            // --- Distributed Ray Tracing (Accumulation) ---
            ensureTempTextures(device: context.device, width: colorTexture.width, height: colorTexture.height)
            
            // 1. Clear Output Texture (Accumulator)
            let clearDesc = MTLRenderPassDescriptor()
            clearDesc.colorAttachments[0].texture = colorTexture
            clearDesc.colorAttachments[0].loadAction = .clear
            clearDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            clearDesc.colorAttachments[0].storeAction = .store
            
            if let clearEncoder = context.commandBuffer.makeRenderCommandEncoder(descriptor: clearDesc) {
                clearEncoder.endEncoding()
            }
            
            for i in 0..<sampleCount {
                // 2. Render Scene to Temp Texture
                let renderDesc = MTLRenderPassDescriptor()
                renderDesc.colorAttachments[0].texture = tempTexture
                renderDesc.colorAttachments[0].loadAction = .clear
                renderDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
                renderDesc.colorAttachments[0].storeAction = .store
                
                renderDesc.depthAttachment.texture = tempDepthTexture
                renderDesc.depthAttachment.loadAction = .clear
                renderDesc.depthAttachment.clearDepth = 1.0
                renderDesc.depthAttachment.storeAction = .dontCare
                
                guard let encoder = context.commandBuffer.makeRenderCommandEncoder(descriptor: renderDesc) else { continue }
                encoder.label = "\(label) - Sample \(i)"
                
                // Calculate Jitter (Halton Sequence)
                // Skip index 0 to avoid (0,0) correlation issues sometimes
                let u1 = halton(index: i + 1, base: 2)
                let u2 = halton(index: i + 1, base: 3)
                
                // Map to disk (Concentric mapping is better, but simple polar is fine for now)
                let r = sqrt(u1)
                let theta = 2.0 * Float.pi * u2
                let apertureSample = SIMD2<Float>(r * cos(theta), r * sin(theta))
                
                encodeScene(encoder: encoder, targetWidth: colorTexture.width, targetHeight: colorTexture.height, apertureSample: apertureSample, time: Float(context.time))
                encoder.endEncoding()
                
                // 3. Accumulate Temp to Output
                let accDesc = MTLRenderPassDescriptor()
                accDesc.colorAttachments[0].texture = colorTexture
                accDesc.colorAttachments[0].loadAction = .load
                accDesc.colorAttachments[0].storeAction = .store
                
                guard let accEncoder = context.commandBuffer.makeRenderCommandEncoder(descriptor: accDesc) else { continue }
                accEncoder.label = "Accumulate \(i)"
                
                if accumulatePipeline == nil {
                    // Should have been built in buildPipeline, but ensure here
                    // (Actually buildPipeline is called at start, we need to add it there)
                }
                
                accEncoder.setRenderPipelineState(accumulatePipeline!)
                accEncoder.setFragmentTexture(tempTexture, index: 0)
                
                // Set Blend Color for weight (1/N)
                let weight = 1.0 / Float(sampleCount)
                accEncoder.setBlendColor(red: 0, green: 0, blue: 0, alpha: weight)
                
                accEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                accEncoder.endEncoding()
            }
            
        } else {
            // --- Standard Rendering (Single Pass) ---
            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture = colorTexture
            descriptor.colorAttachments[0].loadAction = .load // Assume background pass cleared it
            descriptor.colorAttachments[0].storeAction = .store
            
            descriptor.depthAttachment.texture = depthTexture
            descriptor.depthAttachment.loadAction = .clear
            descriptor.depthAttachment.clearDepth = 1.0
            descriptor.depthAttachment.storeAction = .store
            
            guard let encoder = context.commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                return
            }
            
            encoder.label = label
            encodeScene(encoder: encoder, targetWidth: colorTexture.width, targetHeight: colorTexture.height, apertureSample: .zero, time: Float(context.time))
            encoder.endEncoding()
        }
        
        // DEBUG: Report what was rendered
        print("GeometryPass: Rendered \(scene.meshes.count) meshes")
    }
    
    private func encodeScene(encoder: MTLRenderCommandEncoder, targetWidth: Int, targetHeight: Int, apertureSample: SIMD2<Float>, time: Float) {
        // Fix 2: Reset Viewport
        encoder.setViewport(MTLViewport(
            originX: 0,
            originY: 0,
            width: Double(targetWidth),
            height: Double(targetHeight),
            znear: 0,
            zfar: 1
        ))
        
        encoder.setRenderPipelineState(pipelineState!)
        encoder.setDepthStencilState(depthState!)
        
        // Bind Lighting
        struct LightUniform {
            var position: SIMD3<Float>
            var color: SIMD3<Float>
            var intensity: Float
            var padding: Float = 0
        }
        
        struct LightingUniforms {
            var light0: LightUniform
            var light1: LightUniform
            var light2: LightUniform
            var light3: LightUniform
            var lightCount: Int32
            var padding: SIMD3<Int32> = .zero
        }
        
        var lights: [LightUniform] = []
        for light in scene.lights.prefix(4) {
            lights.append(LightUniform(position: light.position, color: light.color, intensity: light.intensity, padding: 0))
        }
        while lights.count < 4 {
            lights.append(LightUniform(position: .zero, color: .zero, intensity: 0, padding: 0))
        }
        
        var lighting = LightingUniforms(
            light0: lights[0],
            light1: lights[1],
            light2: lights[2],
            light3: lights[3],
            lightCount: Int32(min(scene.lights.count, 4))
        )
        
        // Initial state: Lit
        var isLit = true
        encoder.setFragmentBytes(&lighting, length: MemoryLayout<LightingUniforms>.stride, index: 0)
        
        // Bind Camera Uniforms
        var cameraUniforms = scene.camera.getUniforms(aspectRatio: Float(targetWidth) / Float(targetHeight), apertureSample: apertureSample)
        encoder.setVertexBytes(&cameraUniforms, length: MemoryLayout<CameraUniforms>.stride, index: 1)
        
        // Sort Meshes: Opaque first, then Transparent (Back-to-Front)
        let opaqueMeshes = scene.meshes.filter { !$0.isTransparent }
        
        // For transparent meshes, we should sort by distance to camera
        // Simple approximation: Sort by Z value of position
        // Better: Project position to view space and sort by Z
        let viewMatrix = cameraUniforms.viewMatrix
        let transparentMeshes = scene.meshes.filter { $0.isTransparent }.sorted { m1, m2 in
            let p1 = m1.transform.columns.3
            let p2 = m2.transform.columns.3
            // Transform to View Space
            let v1 = viewMatrix * p1
            let v2 = viewMatrix * p2
            // Sort Back-to-Front (Larger Z (more negative) first? No, View Space Z is negative forward)
            // In View Space (Right Handed), Camera is at 0. Forward is -Z.
            // Far objects have very negative Z (e.g. -100). Near objects have less negative Z (e.g. -1).
            // We want to draw Far objects first.
            // So sort by Z ascending (e.g. -100 before -1).
            return v1.z < v2.z
        }
        
        let sortedMeshes = opaqueMeshes + transparentMeshes
        
        // Draw Meshes
        for mesh in sortedMeshes {
            // Set Depth State
            if mesh.isTransparent {
                encoder.setDepthStencilState(transparentDepthState!)
            } else {
                encoder.setDepthStencilState(depthState!)
            }
            
            // Check if mesh needs unlit rendering
            if let color = mesh.color {
                struct MaterialUniforms {
                    var color: SIMD4<Float>
                    var twinkleStrength: Float
                    var time: Float
                    var padding: SIMD2<Float> = .zero
                }
                
                var materialUniforms = MaterialUniforms(
                    color: SIMD4<Float>(color.x, color.y, color.z, 1.0),
                    twinkleStrength: mesh.twinkleStrength,
                    time: time
                )
                
                if let texture = mesh.texture {
                    encoder.setRenderPipelineState(texturedPipelineState!)
                    encoder.setFragmentTexture(texture, index: 0)
                } else {
                    encoder.setRenderPipelineState(unlitPipelineState!)
                }
                
                encoder.setFragmentBytes(&materialUniforms, length: MemoryLayout<MaterialUniforms>.stride, index: 0)
                isLit = false // Flag that we broke the lit state
            } else if var material = mesh.material {
                // V6.0 PBR Rendering
                encoder.setRenderPipelineState(pbrPipelineState!)
                
                // Check for texture
                if let texture = mesh.texture {
                    material.hasBaseColorMap = 1
                    encoder.setFragmentTexture(texture, index: 0)
                } else {
                    material.hasBaseColorMap = 0
                }
                
                encoder.setFragmentBytes(&material, length: MemoryLayout<PBRMaterial>.stride, index: 0)
                encoder.setFragmentBytes(&lighting, length: MemoryLayout<LightingUniforms>.stride, index: 1)
                
                var camPos = scene.camera.position
                encoder.setFragmentBytes(&camPos, length: MemoryLayout<SIMD3<Float>>.stride, index: 2)
                
                isLit = false // PBR uses its own lighting binding, so we consider it "custom lit"
            } else {
                if !isLit {
                    encoder.setRenderPipelineState(pipelineState!)
                    encoder.setFragmentBytes(&lighting, length: MemoryLayout<LightingUniforms>.stride, index: 0)
                    isLit = true
                }
            }
            
            encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
            
            var modelMatrix = mesh.transform
            encoder.setVertexBytes(&modelMatrix, length: MemoryLayout<matrix_float4x4>.stride, index: 2)
            
            encoder.drawIndexedPrimitives(type: .triangle,
                                          indexCount: mesh.indexCount,
                                          indexType: .uint16,
                                          indexBuffer: mesh.indexBuffer,
                                          indexBufferOffset: 0)
        }
    }
    
    private func buildPipeline(device: MTLDevice) throws {
        let library = ShaderLibrary(device: device)
        
        // Ensure shaders are loaded
        if (try? library.makeFunction(name: "vertex_mesh")) == nil {
             try? library.loadSource(resource: "StandardMesh")
        }
        
        let vertexFn = try library.makeFunction(name: "vertex_mesh")
        let fragmentFn = try library.makeFunction(name: "fragment_mesh_standard")
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = label
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .rgba16Float
        descriptor.depthAttachmentPixelFormat = .depth32Float
        
        // Define Vertex Descriptor
        let vertexDescriptor = MTLVertexDescriptor()
        
        // Position (float3)
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        // Normal (float3)
        vertexDescriptor.attributes[1].format = .float3
        vertexDescriptor.attributes[1].offset = 12
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        // UV (float2)
        vertexDescriptor.attributes[2].format = .float2
        vertexDescriptor.attributes[2].offset = 24
        vertexDescriptor.attributes[2].bufferIndex = 0
        
        // Layout
        vertexDescriptor.layouts[0].stride = 32
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        descriptor.vertexDescriptor = vertexDescriptor
        
        self.pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        
        // Build Unlit Pipeline
        let unlitFragmentFn = try library.makeFunction(name: "fragment_mesh_unlit")
        descriptor.fragmentFunction = unlitFragmentFn
        self.unlitPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        
        // Build Textured Pipeline
        let texturedFragmentFn = try library.makeFunction(name: "fragment_mesh_textured")
        descriptor.fragmentFunction = texturedFragmentFn
        
        // Enable Blending for Textured Pipeline (Alpha Blending)
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        self.texturedPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        
        // Build PBR Pipeline (V6.0)
        // Disable blending for opaque PBR (unless we support transmission later)
        descriptor.colorAttachments[0].isBlendingEnabled = false
        
        if (try? library.makeFunction(name: "fragment_mesh_pbr")) == nil {
             try? library.loadSource(resource: "Materials/PBR")
        }
        let pbrFragmentFn = try library.makeFunction(name: "fragment_mesh_pbr")
        descriptor.fragmentFunction = pbrFragmentFn
        self.pbrPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = true
        self.depthState = device.makeDepthStencilState(descriptor: depthDesc)
        
        // Transparent Depth State (No Write)
        let transDepthDesc = MTLDepthStencilDescriptor()
        transDepthDesc.depthCompareFunction = .less
        transDepthDesc.isDepthWriteEnabled = false
        self.transparentDepthState = device.makeDepthStencilState(descriptor: transDepthDesc)
        
        // Build Accumulate Pipeline
        try buildAccumulatePipeline(device: device, library: library)
    }
    
    private func buildAccumulatePipeline(device: MTLDevice, library: ShaderLibrary) throws {
        let vertexFn = try library.makeFunction(name: "vertex_fullscreen_triangle")
        let fragmentFn = try library.makeFunction(name: "fragment_texture_passthrough")
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Accumulate Pipeline"
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .rgba16Float
        
        // Additive Blending with Constant Alpha Weight
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .blendAlpha // Use constant alpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .blendAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
        
        self.accumulatePipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }
}

