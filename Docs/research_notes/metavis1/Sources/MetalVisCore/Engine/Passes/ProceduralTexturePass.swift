import Metal
import Foundation

/// ProceduralTexturePass - Generates procedural textures using compute shaders
/// Supports fractals (Julia, Mandelbrot, Burning Ship) and noise (Perlin, Simplex, Worley, FBM)
@available(macOS 14.0, *)
public class ProceduralTexturePass: RenderPass {
    public var name = "ProceduralTexture"
    
    // MARK: - Configuration
    
    public enum ProceduralType {
        case julia
        case mandelbrot
        case burningShip
        case perlin
        case simplex
        case worley
        case fbmPerlin
        case fbmSimplex
        case pbrSphere // NEW: PBR Material Preview
    }
    
    public struct GradientStop {
        public let color: SIMD3<Float>  // ACEScg
        public let position: Float       // 0.0 to 1.0
        
        public init(color: SIMD3<Float>, position: Float) {
            self.color = color
            self.position = position
        }
    }
    
    // Public properties
    public var proceduralType: ProceduralType = .julia
    public var fieldDefinition: ProceduralFieldDefinition? // NEW: Unified Field Definition
    public var resolution: SIMD2<Int>? = nil  // nil = match screen resolution
    public var quality: MVQualityMode = .cinema
    
    // Fractal parameters
    public var maxIterations: Int = 256
    public var escapeRadius: Float = 2.0
    public var smoothColoring: Bool = true
    public var juliaC: SIMD2<Float> = SIMD2(0.355, 0.355)
    public var mandelbrotCenter: SIMD2<Float> = SIMD2(-0.5, 0.0)
    public var zoom: Float = 1.0
    public var fractalCenter: SIMD2<Float> = SIMD2(0.0, 0.0)
    
    // Noise parameters
    public var frequency: Float = 2.0
    public var octaves: Int = 6
    public var lacunarity: Float = 2.0
    public var gain: Float = 0.5
    public var domainWarp: Bool = false
    public var warpStrength: Float = 0.3
    
    // Color mapping
    public var gradientColors: [GradientStop] = [
        GradientStop(color: SIMD3(0.05, 0.0, 0.15), position: 0.0),
        GradientStop(color: SIMD3(1.2, 0.4, 0.0), position: 0.5),
        GradientStop(color: SIMD3(0.0, 0.9, 1.5), position: 1.0)
    ]
    public var loopGradient: Bool = true
    
    // Animation
    public var time: Float = 0.0
    
    // Private state
    private var fractalPipeline: MTLComputePipelineState?
    private var noisePipeline: MTLComputePipelineState?
    private var graphPipeline: MTLComputePipelineState? // NEW: Graph Interpreter
    private var pbrPipeline: MTLComputePipelineState?
    var outputTexture: MTLTexture?
    private var library: MTLLibrary?
    
    public init() {}
    
    // MARK: - RenderPass Protocol
    
    public var label: String { name }
    public var inputs: [String] = []
    public var outputs: [String] = ["procedural_texture"]
    
    public func setup(device: MTLDevice, library: MTLLibrary) throws {
        self.library = library
        
        // Load fractal kernels
        if let juliaFunction = library.makeFunction(name: "fx_fractal_julia") {
            fractalPipeline = try device.makeComputePipelineState(function: juliaFunction)
        }
        
        // Load noise kernel
        if let noiseFunction = library.makeFunction(name: "fx_procedural_field") {
            noisePipeline = try device.makeComputePipelineState(function: noiseFunction)
        }
        
        // Load graph kernel
        if let graphFunction = library.makeFunction(name: "fx_procedural_graph") {
            graphPipeline = try device.makeComputePipelineState(function: graphFunction)
        }
        
        // Load PBR kernel
        if let pbrFunction = library.makeFunction(name: "fx_pbr_material") {
            pbrPipeline = try device.makeComputePipelineState(function: pbrFunction)
        }
    }
    
    public func execute(context: RenderContext,
                        inputTextures: [String: MTLTexture],
                        outputTextures: [String: MTLTexture]) throws {
        
        // Ensure pipelines are loaded (Lazy Initialization)
        if noisePipeline == nil {
            try ensurePipelines(device: context.device)
        }
        
        guard let encoder = context.commandBuffer.makeComputeCommandEncoder() else {
            throw RenderPassError.failedToCreateEncoder
        }
        
        encoder.label = "ProceduralTexture"
        
        // Determine output resolution
        let targetResolution = resolution ?? context.resolution
        
        // Create or reuse output texture
        let output = try getOrCreateOutputTexture(
            device: context.device,
            width: targetResolution.x,
            height: targetResolution.y
        )
        
        // Check for Field Definition override
        if let field = fieldDefinition {
            // 1. PBR Preview
            if let type = field.patternType, type == "PBR_SPHERE" {
                try executePBR(encoder: encoder, output: output, context: context)
                encoder.endEncoding()
                outputTexture = output
                return
            }
            
            // 2. Graph Execution (Phase 2)
            if let graph = field.graph {
                try executeGraph(graph: graph, encoder: encoder, output: output, context: context)
                encoder.endEncoding()
                outputTexture = output
                return
            }
            
            // 3. Check for Noise/Fractal override from Field Definition
            if let type = field.patternType {
                switch type {
                case "PERLIN", "SIMPLEX", "WORLEY", "FBM_PERLIN", "FBM_SIMPLEX":
                    try executeNoise(encoder: encoder, output: output, context: context)
                    encoder.endEncoding()
                    outputTexture = output
                    return
                case "JULIA", "MANDELBROT", "BURNING_SHIP":
                    // Map string to enum if needed, or just call executeFractal
                    // For now, we rely on proceduralType being set correctly or add logic here
                    // But since we are fixing the Noise case specifically:
                    break
                default:
                    break
                }
            }
        }
        
        // Choose kernel based on type
        switch proceduralType {
        case .julia, .mandelbrot, .burningShip:
            try executeFractal(encoder: encoder, output: output, context: context)
        case .perlin, .simplex, .worley, .fbmPerlin, .fbmSimplex:
            try executeNoise(encoder: encoder, output: output, context: context)
        case .pbrSphere:
            try executePBR(encoder: encoder, output: output, context: context)
        }
        
        encoder.endEncoding()
        
        // Store for downstream passes
        outputTexture = output
        
        // If we have an output binding, write to it?
        // But this pass generates its own texture.
        // We can copy it to the output texture if provided.
        if let outputName = outputs.first,
           let target = outputTextures[outputName] {
            // Blit copy
            if let blit = context.commandBuffer.makeBlitCommandEncoder() {
                blit.copy(from: output, to: target)
                blit.endEncoding()
            }
        }
    }
    
    private func ensurePipelines(device: MTLDevice) throws {
        let shaderLib = ShaderLibrary(device: device)
        
        // Load fractal kernels
        if let juliaFunction = try? shaderLib.makeFunction(name: "fx_fractal_julia") {
            fractalPipeline = try device.makeComputePipelineState(function: juliaFunction)
        }
        
        // Load noise kernel
        if let noiseFunction = try? shaderLib.makeFunction(name: "fx_procedural_field") {
            noisePipeline = try device.makeComputePipelineState(function: noiseFunction)
        }
        
        // Load graph kernel
        if let graphFunction = try? shaderLib.makeFunction(name: "fx_procedural_graph") {
            graphPipeline = try device.makeComputePipelineState(function: graphFunction)
        }
        
        // Load PBR kernel
        if let pbrFunction = try? shaderLib.makeFunction(name: "fx_pbr_material") {
            pbrPipeline = try device.makeComputePipelineState(function: pbrFunction)
        }
    }
    
    public func resize(width: Int, height: Int) {
        // Force texture recreation on next execute
        outputTexture = nil
    }
    
    // MARK: - Graph Execution (Phase 2)
    
    private func executeGraph(
        graph: ProceduralGraph,
        encoder: MTLComputeCommandEncoder,
        output: MTLTexture,
        context: RenderContext
    ) throws {
        guard let pipeline = graphPipeline else {
            throw RenderPassError.pipelineNotInitialized
        }
        
        encoder.setComputePipelineState(pipeline)
        
        // Compile graph to nodes
        let nodes = compileGraph(graph)
        var nodeCount = Int32(nodes.count)
        
        // Prepare gradient
        let gradientData = gradientColors.map { GradientColorData(
            colorACEScg: $0.color,
            position: $0.position
        )}
        var gradientCount = Int32(gradientData.count)
        
        // Set buffers
        encoder.setTexture(output, index: 0)
        
        // Buffer 0: Nodes
        if !nodes.isEmpty {
            encoder.setBytes(nodes, length: MemoryLayout<GraphNode>.stride * nodes.count, index: 0)
        }
        
        // Buffer 1: Node Count
        encoder.setBytes(&nodeCount, length: MemoryLayout<Int32>.size, index: 1)
        
        // Buffer 2: Gradient
        var gradientMutable = gradientData
        encoder.setBytes(&gradientMutable, length: MemoryLayout<GradientColorData>.stride * gradientData.count, index: 2)
        
        // Buffer 3: Gradient Count
        encoder.setBytes(&gradientCount, length: MemoryLayout<Int32>.size, index: 3)
        
        // Buffer 4: Time
        var t = time
        encoder.setBytes(&t, length: MemoryLayout<Float>.size, index: 4)
        
        // Dispatch
        let threadGroupSize = MTLSize(width: 8, height: 8, depth: 1)
        let threadGroups = MTLSize(
            width: (output.width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (output.height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
    }
    
    private func compileGraph(_ graph: ProceduralGraph) -> [GraphNode] {
        var nodes: [GraphNode] = []
        var idToIndex: [String: Int] = [:]
        
        // Map IDs to indices
        for (index, node) in graph.nodes.enumerated() {
            idToIndex[node.id] = index
        }
        
        for node in graph.nodes {
            let op = getOpCode(node.op)
            
            // Resolve inputs
            var inputIndices: [Int32] = [-1, -1, -1, -1]
            if let inputs = node.inputs {
                for (i, inputId) in inputs.enumerated() {
                    if i < 4 {
                        if let idx = idToIndex[inputId] {
                            inputIndices[i] = Int32(idx)
                        }
                    }
                }
            }
            
            // Resolve params
            var params: [Float] = [0, 0, 0, 0]
            
            if let p = node.params {
                switch node.op {
                case "CONSTANT":
                    params[0] = p["value"] ?? 0.0
                case "COORD":
                    params[0] = p["selector"] ?? 0.0
                case "FBM":
                    params[0] = p["frequency"] ?? 1.0
                    params[1] = p["octaves"] ?? 6.0
                    params[2] = p["lacunarity"] ?? 2.0
                    params[3] = p["gain"] ?? 0.5
                case "PERLIN", "SIMPLEX", "WORLEY":
                    params[0] = p["frequency"] ?? 1.0
                case "MIX":
                    params[0] = p["factor"] ?? 0.5
                case "DOMAIN_WARP":
                    params[0] = p["strength"] ?? 0.1
                case "DOMAIN_ROTATE":
                    params[0] = p["angle"] ?? 0.0
                case "DOMAIN_SCALE":
                    params[0] = p["x"] ?? 1.0
                    params[1] = p["y"] ?? 1.0
                case "DOMAIN_OFFSET":
                    params[0] = p["x"] ?? 0.0
                    params[1] = p["y"] ?? 0.0
                default:
                    break
                }
            }
            
            nodes.append(GraphNode(
                op: op,
                inputs: (inputIndices[0], inputIndices[1], inputIndices[2], inputIndices[3]),
                params: (params[0], params[1], params[2], params[3])
            ))
        }
        
        return nodes
    }
    
    private func getOpCode(_ op: String) -> Int32 {
        switch op {
        case "CONSTANT": return 0
        case "COORD": return 1
        case "ADD": return 2
        case "SUB": return 3
        case "MUL": return 4
        case "DIV": return 5
        case "SIN": return 6
        case "COS": return 7
        case "ABS": return 8
        case "MIN": return 9
        case "MAX": return 10
        case "MIX": return 11
        case "POW": return 12
        case "EXP": return 13
        case "NORMALIZE": return 14
        case "PERLIN": return 20
        case "SIMPLEX": return 21
        case "WORLEY": return 22
        case "FBM": return 23
        case "DOMAIN_WARP": return 30
        case "DOMAIN_ROTATE": return 31
        case "DOMAIN_SCALE": return 32
        case "DOMAIN_OFFSET": return 33
        default: return 0
        }
    }
    
    private struct GraphNode {
        var op: Int32
        var inputs: (Int32, Int32, Int32, Int32)
        var params: (Float, Float, Float, Float)
    }

    // MARK: - Fractal Execution
    
    private func executeFractal(
        encoder: MTLComputeCommandEncoder,
        output: MTLTexture,
        context: RenderContext
    ) throws {
        guard let pipeline = fractalPipeline else {
            throw RenderPassError.pipelineNotInitialized
        }
        
        // Select kernel name based on fractal type
        let kernelName: String
        switch proceduralType {
        case .julia:
            kernelName = "fx_fractal_julia"
        case .mandelbrot:
            kernelName = "fx_fractal_mandelbrot"
        case .burningShip:
            kernelName = "fx_fractal_burning_ship"
        default:
            throw RenderPassError.invalidConfiguration
        }
        
        // Load the correct pipeline
        if let lib = library,
           let function = lib.makeFunction(name: kernelName),
           let correctPipeline = try? context.device.makeComputePipelineState(function: function) {
            encoder.setComputePipelineState(correctPipeline)
        } else {
            encoder.setComputePipelineState(pipeline)
        }
        
        // Prepare parameters
        var params = FractalParams(
            maxIterations: Int32(getIterationsForQuality()),
            escapeRadius: escapeRadius,
            smoothColoring: smoothColoring ? 1 : 0,
            c: proceduralType == .julia ? juliaC : mandelbrotCenter,
            zoom: zoom,
            center: fractalCenter,
            colorCount: Int32(gradientColors.count),
            loopGradient: loopGradient ? 1 : 0,
            time: Float(context.time)
        )
        
        // Prepare gradient buffer
        let gradientData = gradientColors.map {  GradientColorData(
            colorACEScg: $0.color,
            position: $0.position
        )}
        
        // Set buffers
        encoder.setTexture(output, index: 0)
        encoder.setBytes(&params, length: MemoryLayout<FractalParams>.size, index: 0)
        
        var gradientMutable = gradientData
        encoder.setBytes(&gradientMutable, length: MemoryLayout<GradientColorData>.stride * gradientData.count, index: 1)
        
        // Dispatch
        let threadGroupSize = MTLSize(width: 8, height: 8, depth: 1)
        let threadGroups = MTLSize(
            width: (output.width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (output.height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
    }
    
    // MARK: - Noise Execution
    
    private func executeNoise(
        encoder: MTLComputeCommandEncoder,
        output: MTLTexture,
        context: RenderContext
    ) throws {
        // Load the generic field kernel if not already loaded
        // Note: In a real implementation, we'd cache this pipeline separately
        // For now, we assume noisePipeline was initialized with "fx_procedural_field"
        
        guard let pipeline = noisePipeline else {
            throw RenderPassError.pipelineNotInitialized
        }
        
        encoder.setComputePipelineState(pipeline)
        
        // Map type to int
        let noiseTypeInt: Int32
        
        // If we have a field definition, use it
        if let field = fieldDefinition {
            // Parse graph or legacy parameters
            // For Phase 1, we map the "patternType" string to our internal ID
            if let type = field.patternType {
                switch type {
                case "PERLIN": noiseTypeInt = 0
                case "SIMPLEX": noiseTypeInt = 1
                case "WORLEY": noiseTypeInt = 2
                case "FBM_PERLIN": noiseTypeInt = 3
                case "FBM_SIMPLEX": noiseTypeInt = 3 // Shared FBM for now
                case "FIRE": noiseTypeInt = 4 // New Fire Kernel
                case "PBR_SPHERE": 
                    // Special case: Switch proceduralType to .pbrSphere and return early?
                    // No, executeNoise is called only if type is noise.
                    // We need to handle this dispatch logic at the top level.
                    // For now, assume noiseTypeInt = 0 if PBR is requested here (shouldn't happen if logic is correct)
                    noiseTypeInt = 0
                default: noiseTypeInt = 0
                }
            } else {
                noiseTypeInt = 0
            }
        } else {
            // Fallback to legacy enum
            switch proceduralType {
            case .perlin: noiseTypeInt = 0
            case .simplex: noiseTypeInt = 1
            case .worley: noiseTypeInt = 2
            case .fbmPerlin: noiseTypeInt = 3
            case .fbmSimplex: noiseTypeInt = 3
            default: noiseTypeInt = 0
            }
        }
        
        // Extract parameters
        var freq: Float = frequency
        var oct: Int32 = Int32(getOctavesForQuality())
        var lac: Float = lacunarity
        var gn: Float = gain
        var warp: Bool = domainWarp
        var warpStr: Float = warpStrength
        
        if let params = fieldDefinition?.parameters {
            if let f = params["frequency"] { freq = f }
            if let o = params["octaves"] { oct = Int32(o) }
            if let l = params["lacunarity"] { lac = l }
            if let g = params["gain"] { gn = g }
        }
        
        if let domain = fieldDefinition?.domain {
            if let w = domain.warpStrength {
                warp = w > 0
                warpStr = w
            }
        }
        
        // Prepare gradient
        // Override gradient for FIRE type if using default
        var currentGradient = gradientColors
        var loopGradientVal = loopGradient ? 1 : 0
        
        if noiseTypeInt == 4 { // FIRE
             currentGradient = [
                GradientStop(color: SIMD3(0.0, 0.0, 0.0), position: 0.0),    // Black
                GradientStop(color: SIMD3(0.5, 0.0, 0.0), position: 0.2),    // Dark Red
                GradientStop(color: SIMD3(1.0, 0.2, 0.0), position: 0.4),    // Red-Orange
                GradientStop(color: SIMD3(1.5, 0.8, 0.0), position: 0.6),    // Bright Orange (HDR)
                GradientStop(color: SIMD3(2.0, 1.5, 0.5), position: 0.8),    // Yellow-White (HDR)
                GradientStop(color: SIMD3(1.0, 1.0, 1.0), position: 1.0)     // White
            ]
            loopGradientVal = 0 // Don't loop fire gradient
        }

        // Prepare parameters (FieldParams)
        var params = FieldParams(
            fieldType: noiseTypeInt,
            frequency: freq,
            octaves: oct,
            lacunarity: lac,
            gain: gn,
            domainWarp: warp ? 1 : 0,
            warpStrength: warpStr,
            scale: SIMD2(1.0, 1.0), // Default scale
            offset: SIMD2(0.0, 0.0), // Default offset
            rotation: 0.0,
            colorCount: Int32(currentGradient.count),
            loopGradient: Int32(loopGradientVal),
            time: Float(context.time) // Use context time for animation
        )

        let gradientData = currentGradient.map { GradientColorData(
            colorACEScg: $0.color,
            position: $0.position
        )}
        
        // Set buffers
        encoder.setTexture(output, index: 0)
        encoder.setBytes(&params, length: MemoryLayout<FieldParams>.size, index: 0)
        
        var gradientMutable = gradientData
        encoder.setBytes(&gradientMutable, length: MemoryLayout<GradientColorData>.stride * gradientData.count, index: 1)
        
        // Dispatch
        let threadGroupSize = MTLSize(width: 8, height: 8, depth: 1)
        let threadGroups = MTLSize(
            width: (output.width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (output.height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
    }
    
    // MARK: - PBR Execution
    
    private func executePBR(
        encoder: MTLComputeCommandEncoder,
        output: MTLTexture,
        context: RenderContext
    ) throws {
        guard let pipeline = pbrPipeline else {
            throw RenderPassError.pipelineNotInitialized
        }
        
        encoder.setComputePipelineState(pipeline)
        
        // Default PBR Params (Marble-like)
        var params = PBRMaterialParams(
            baseColor: SIMD3(0.9, 0.9, 0.9),
            metallic: 0.0,
            roughness: 0.1,
            specular: 0.5,
            specularTint: 0.0,
            sheen: 0.0,
            sheenTint: 0.0,
            clearcoat: 1.0,
            clearcoatGloss: 1.0,
            ior: 1.5,
            transmission: 0.0,
            roughnessMapType: 2, // Worley
            normalMapType: 0,
            metallicMapType: 0,
            mapFrequency: 10.0,
            mapStrength: 0.5
        )
        
        // Override from fieldDefinition if present
        if let field = fieldDefinition, let p = field.parameters {
            if let r = p["roughness"] { params.roughness = r }
            if let m = p["metallic"] { params.metallic = m }
            if let f = p["frequency"] { params.mapFrequency = f }
        }
        
        // Lights (Simple setup)
        var lights = [
            Light(position: SIMD3(5, 5, 5), color: SIMD3(1, 1, 1), intensity: 10.0),
            Light(position: SIMD3(-5, 2, 5), color: SIMD3(0.5, 0.5, 1.0), intensity: 5.0)
        ]
        var lightCount: Int32 = Int32(lights.count)
        var cameraPos = SIMD3<Float>(0, 0, 2)
        
        encoder.setTexture(output, index: 0)
        encoder.setBytes(&params, length: MemoryLayout<PBRMaterialParams>.size, index: 0)
        encoder.setBytes(&lights, length: MemoryLayout<Light>.stride * lights.count, index: 1)
        encoder.setBytes(&lightCount, length: MemoryLayout<Int32>.size, index: 2)
        encoder.setBytes(&cameraPos, length: MemoryLayout<SIMD3<Float>>.size, index: 3)
        
        // Dispatch
        let threadGroupSize = MTLSize(width: 8, height: 8, depth: 1)
        let threadGroups = MTLSize(
            width: (output.width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (output.height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
    }

    // MARK: - Helpers
    
    private func getIterationsForQuality() -> Int {
        switch quality {
        case .realtime:
            return min(maxIterations, 128)
        case .cinema:
            return maxIterations
        case .lab:
            return max(maxIterations, 512)
        }
    }
    
    private func getOctavesForQuality() -> Int {
        switch quality {
        case .realtime:
            return min(octaves, 4)
        case .cinema:
            return octaves
        case .lab:
            return max(octaves, 8)
        }
    }
    
    private func getOrCreateOutputTexture(
        device: MTLDevice,
        width: Int,
        height: Int
    ) throws -> MTLTexture {
        // Check if we can reuse existing texture
        if let existing = outputTexture,
           existing.width == width,
           existing.height == height {
            return existing
        }
        
        // Create new texture
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,  // HDR support
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderWrite, .shaderRead]
        descriptor.storageMode = .private
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RenderPassError.failedToCreateTexture
        }
        
        texture.label = "ProceduralTexture.Output"
        return texture
    }
    
    public func getOutputTexture() -> MTLTexture? {
        return outputTexture
    }
}

// MARK: - Metal Structs (matching shader)

private struct FractalParams {
    let maxIterations: Int32
    let escapeRadius: Float
    let smoothColoring: Int32
    
    let c: SIMD2<Float>
    let zoom: Float
    let center: SIMD2<Float>
    
    let colorCount: Int32
    let loopGradient: Int32
    
    let time: Float
    let padding: Float = 0
}

private struct FieldParams {
    let fieldType: Int32
    let frequency: Float
    let octaves: Int32
    let lacunarity: Float
    let gain: Float
    
    let domainWarp: Int32
    let warpStrength: Float
    
    // Padding to align 'scale' (float2) to 8 bytes
    // Current offset: 28. Next alignment: 32. Padding: 4 bytes.
    let padding1: Float = 0
    
    let scale: SIMD2<Float>
    let offset: SIMD2<Float>
    let rotation: Float
    
    let colorCount: Int32
    let loopGradient: Int32
    
    let time: Float
    let padding2: Float = 0
}

private struct PBRMaterialParams {
    var baseColor: SIMD3<Float>
    var metallic: Float
    var roughness: Float
    var specular: Float
    var specularTint: Float
    var sheen: Float
    var sheenTint: Float
    var clearcoat: Float
    var clearcoatGloss: Float
    var ior: Float
    var transmission: Float
    
    var roughnessMapType: Int32
    var normalMapType: Int32
    var metallicMapType: Int32
    
    var mapFrequency: Float
    var mapStrength: Float
}

private struct Light {
    var position: SIMD3<Float>
    var color: SIMD3<Float>
    var intensity: Float
}

// MARK: - Errors

public enum RenderPassError: Error {
    case failedToCreateEncoder
    case pipelineNotInitialized
    case invalidConfiguration
    case failedToCreateTexture
}

private struct GradientColorData {
    let colorACEScg: SIMD3<Float>
    let position: Float
}
