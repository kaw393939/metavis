import Metal
import simd

public class BokehPass: RenderPass {
    public var label: String = "Bokeh Blur"
    public var inputs: [String] = ["main_buffer", "depth_buffer"]
    public var outputs: [String] = ["display_buffer"]
    
    private var pipelineState: MTLComputePipelineState?
    
    // Parameters
    public var radius: Float = 20.0
    
    public init(device: MTLDevice) {
        // No-op
    }
    
    public func execute(context: RenderContext,
                        inputTextures: [String: MTLTexture],
                        outputTextures: [String: MTLTexture]) throws {
        
        guard let inputTexture = inputTextures[inputs[0]],
              let depthTexture = inputTextures["depth_buffer"],
              let outputTexture = outputTextures[outputs[0]] else {
            return
        }
        
        if pipelineState == nil {
            try buildPipeline(device: context.device)
        }
        
        guard let pipeline = pipelineState else {
            return
        }
        
        guard let encoder = context.commandBuffer.makeComputeCommandEncoder() else { return }
        
        encoder.label = label
        encoder.setComputePipelineState(pipeline)
        
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        encoder.setTexture(depthTexture, index: 2)
        
        // DoF Parameters
        struct FocusZone {
            var zMin: Float
            var zMax: Float
            var focusDistance: Float
            var fStop: Float
        }
        
        struct DoFParams {
            var focusDistance: Float
            var fStop: Float
            var focalLength: Float
            var maxRadius: Float
            var zoneCount: Int32
            var padding: SIMD3<Float>
            var zones: (FocusZone, FocusZone, FocusZone, FocusZone)
        }
        
        // Default Zone (Global)
        let defaultZone = FocusZone(zMin: 0, zMax: 1000, focusDistance: context.camera.focusDistance, fStop: context.camera.fStop)
        
        // Map Scene Zones to Structs
        var zone0 = defaultZone
        var zone1 = defaultZone
        var zone2 = defaultZone
        var zone3 = defaultZone
        
        let sceneZones = context.scene.focusZones
        let zoneCount = min(sceneZones.count, 4)
        
        if zoneCount > 0 { zone0 = FocusZone(zMin: sceneZones[0].zMin, zMax: sceneZones[0].zMax, focusDistance: sceneZones[0].focalDistanceM, fStop: sceneZones[0].apertureFstop) }
        if zoneCount > 1 { zone1 = FocusZone(zMin: sceneZones[1].zMin, zMax: sceneZones[1].zMax, focusDistance: sceneZones[1].focalDistanceM, fStop: sceneZones[1].apertureFstop) }
        if zoneCount > 2 { zone2 = FocusZone(zMin: sceneZones[2].zMin, zMax: sceneZones[2].zMax, focusDistance: sceneZones[2].focalDistanceM, fStop: sceneZones[2].apertureFstop) }
        if zoneCount > 3 { zone3 = FocusZone(zMin: sceneZones[3].zMin, zMax: sceneZones[3].zMax, focusDistance: sceneZones[3].focalDistanceM, fStop: sceneZones[3].apertureFstop) }
        
        var params = DoFParams(
            focusDistance: context.camera.focusDistance,
            fStop: context.camera.fStop,
            focalLength: context.camera.focalLength,
            maxRadius: self.radius,
            zoneCount: Int32(zoneCount),
            padding: .zero,
            zones: (zone0, zone1, zone2, zone3)
        )
        
        encoder.setBytes(&params, length: MemoryLayout<DoFParams>.size, index: 0)
        
        let w = pipeline.threadExecutionWidth
        let h = pipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerGroup = MTLSizeMake(w, h, 1)
        let threadsPerGrid = MTLSizeMake(outputTexture.width, outputTexture.height, 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
    }
    
    private func buildPipeline(device: MTLDevice) throws {
        let library = ShaderLibrary(device: device)
        
        if (try? library.makeFunction(name: "fx_depth_of_field")) == nil {
             try? library.loadSource(resource: "Effects/Blur")
        }
        
        let function = try library.makeFunction(name: "fx_depth_of_field")
        self.pipelineState = try device.makeComputePipelineState(function: function)
    }
}
