import Foundation
import Metal
import CoreMedia
import simd
import MetaVisCore
import MetaVisImageGen

// MARK: - Shared Data Structures
// Removed duplicate StarData and ConfigData definitions to avoid ambiguity with MetaVisScheduler.
// We will rely on the caller to pass buffers, or define internal structs if needed for Metal layout.
// But since we need to bind them, we need a type.
// Let's define them as `SimulationStarData` and `SimulationConfigData` to avoid conflict,
// OR just use the ones from MetaVisScheduler if we import it?
// But Simulation shouldn't depend on Scheduler.
// Scheduler depends on Simulation.
// So Simulation should define them, and Scheduler should use them?
// Or Scheduler defines them for JSON payload, and converts them?
// The error says `MetaVisScheduler.StarData` exists.
// I added `StarData` to `SimulationEngine.swift` which caused the conflict in CLI (which imports both).

// Let's rename the structs in SimulationEngine to be internal or specific.
public struct SimStarData {
    var u: Float
    var v: Float
    var mag: Float
    var r: Float
    var g: Float
    var b: Float
    
    public init(u: Float, v: Float, mag: Float, r: Float, g: Float, b: Float) {
        self.u = u
        self.v = v
        self.mag = mag
        self.r = r
        self.g = g
        self.b = b
    }
}

public struct SimConfigData {
    var exposure: Float = 1.0
    var saturation: Float = 1.0
    var contrast: Float = 1.0
    var lift: Float = 0.0
    var gamma: Float = 1.0
    var gain: Float = 1.0
    
    public init() {}
}

public enum SimulationError: Error {
    case deviceNotFound
    case commandQueueFailed
    case renderPassFailed
    case textureCreationFailed
}

// MARK: - Color Space Definitions
public enum InputTransferFunction: Int32 {
    case linear = 0
    case sRGB = 1
    case rec709 = 2
    case pq = 3
    case hlg = 4
    case appleLog = 5
    case logC3 = 6
    case sLog3 = 7
}

public enum InputPrimaries: Int32 {
    case acescg = 0
    case ap0 = 1
    case sRGB = 2
    // case rec709 = 2 // Duplicate of sRGB (same primaries)
    case p3d65 = 3
    case rec2020 = 4
    case alexaWide = 5
    case sGamut3 = 6
}

struct IDTParams {
    var transferFunction: Int32
    var primaries: Int32
    var _pad0: Float = 0
    var _pad1: Float = 0
}

/// The Core Engine that drives the simulation and rendering.
public class SimulationEngine {
    public enum CompositeDebugMode {
        case normal
        case forceInput0 // Background
        case forceInput1 // Foreground
    }
    
    public enum IDTDebugMode {
        case off
        case constant
        case data
        case sanity
        case copy
    }
    
    public var debugMode: CompositeDebugMode = .normal
    public var idtDebugMode: IDTDebugMode = .sanity
    public var diagnosticsEnabled: Bool = false
    
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let clock: MasterClock
    public let textureManager: TextureManager
    public let lutLoader: LUTLoader
    public let fitsReader: FITSReader
    public let assetManager: AssetManager
    
    private var activeLUT: MTLTexture?
    private var identityLUT: MTLTexture?
    public let videoProvider: VideoFrameProvider
    public let audioProvider: AudioWaveformProvider
    public let colorPipeline: ColorPipeline
    
    // Geometry
    struct Vertex {
        var position: SIMD4<Float>
        var texCoord: SIMD2<Float>
    }
    private var quadBuffer: MTLBuffer?
    
    // Text Support
    private let glyphManager: GlyphManager
    private let textRenderer: TextRenderer
    private let fontRegistry: FontRegistry
    
    private var videoPipelineState: MTLRenderPipelineState?
    private var processPipelineState: MTLRenderPipelineState?
    private var addBlendPipelineState: MTLRenderPipelineState? // New Additive Blend
    private var colorGradePipelineState: MTLRenderPipelineState?
    private var splitScreenPipelineState: MTLRenderPipelineState?
    private var odtPipelineState: MTLRenderPipelineState?      // For Screen (BGRA8)
    private var odtPipelineFloatState: MTLRenderPipelineState? // For Export (RGBA16Float)
    private var finalCompositePipelineState: MTLComputePipelineState? // Post-Process Uber Kernel
    private var jwstCompositePipelineState: MTLComputePipelineState? // JWST Composite Kernel
    private var toneMapPipelineState: MTLComputePipelineState?
    private var acesOutputPipelineState: MTLComputePipelineState?
    private var waveformPipelineState: MTLRenderPipelineState?
    private var volumePipelineState: MTLRenderPipelineState?
    
    // v46 Auxiliary Buffers
    public var starBuffer: MTLBuffer?
    public var configBuffer: MTLBuffer?
    
    // IDT Kernels
    private var idtSRGBToACEScg: MTLComputePipelineState?
    private var idtRec709ToACEScg: MTLComputePipelineState?
    private var idtGenericToACEScg: MTLComputePipelineState?
    private var idtFITSToACEScg: MTLComputePipelineState?
    private var idtFITSDebugCopy: MTLComputePipelineState? // New Debug Kernel
    private var idtFITSConstantFill: MTLComputePipelineState? // Constant Fill Debug Kernel
    private var idtFITSDataDebug: MTLComputePipelineState? // Data Debug Kernel
    private var idtSanityConstant: MTLComputePipelineState? // Sanity Check Kernel
    private var idtCopyNorm: MTLComputePipelineState? // Copy Norm Kernel
    
    // Diagnostic Pipelines
    private var fitsMinMaxPipeline: MTLComputePipelineState?
    private var compositeMinMaxPipeline: MTLComputePipelineState?
    
    public init(clock: MasterClock, colorPipeline: ColorPipeline = ColorPipeline()) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw SimulationError.deviceNotFound
        }
        self.device = device
        
        // Create Quad Buffer
        let vertices: [Vertex] = [
            Vertex(position: SIMD4(-1, 1, 0, 1), texCoord: SIMD2(0, 0)), // Top Left
            Vertex(position: SIMD4(-1, -1, 0, 1), texCoord: SIMD2(0, 1)), // Bottom Left
            Vertex(position: SIMD4( 1, 1, 0, 1), texCoord: SIMD2(1, 0)), // Top Right
            Vertex(position: SIMD4( 1, -1, 0, 1), texCoord: SIMD2(1, 1))  // Bottom Right
        ]
        self.quadBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Vertex>.stride, options: [])
        
        self.textureManager = TextureManager(device: device)
        self.lutLoader = LUTLoader(device: device)
        self.fitsReader = FITSReader()
        self.assetManager = AssetManager()
        // self.videoProvider = VideoFrameProvider(device: device) // Moved below library loading
        self.audioProvider = AudioWaveformProvider()
        self.colorPipeline = colorPipeline
        
        // Create Identity LUT (1x1x1)
        let lutDesc = MTLTextureDescriptor()
        lutDesc.textureType = .type3D
        lutDesc.pixelFormat = .rgba32Float
        lutDesc.width = 1
        lutDesc.height = 1
        lutDesc.depth = 1
        if let lut = device.makeTexture(descriptor: lutDesc) {
            var data: [Float] = [0.0, 0.0, 0.0, 1.0] // Black/Identity? No, identity LUT maps x->x. 
            // But for a 1x1 LUT, it's just a single color. 
            // Actually, a 1x1 LUT is useless for identity. 
            // But we just need a valid texture to bind. 
            // If we sample it, we get this value.
            // We will handle "no LUT" by checking intensity in shader or just binding this and ensuring intensity is 0.
            lut.replace(region: MTLRegion(origin: MTLOrigin(x:0,y:0,z:0), size: MTLSize(width:1,height:1,depth:1)), mipmapLevel: 0, slice: 0, withBytes: &data, bytesPerRow: 16, bytesPerImage: 16)
            self.identityLUT = lut
        }
        
        // Initialize Text Engine
        self.fontRegistry = FontRegistry()
        self.glyphManager = GlyphManager(device: device, fontRegistry: fontRegistry)
        // Load default font
        _ = try? fontRegistry.register(name: "Helvetica", size: 64)
        
        // We need the library for TextRenderer. 
        let imageGenBundle = Bundle(for: TextRenderer.self)
        let library = try? device.makeDefaultLibrary(bundle: imageGenBundle)
        self.textRenderer = try TextRenderer(device: device, glyphManager: glyphManager, library: library)
        
        guard let queue = device.makeCommandQueue() else {
            throw SimulationError.commandQueueFailed
        }
        self.commandQueue = queue
        self.clock = clock
        
        // Load Library for Simulation Shaders
        var simLibrary: MTLLibrary?
        
        do {
            simLibrary = try device.makeDefaultLibrary(bundle: Bundle.module)
        } catch {
            print("⚠️ Failed to load default library from Bundle.module: \(error)")
            
            // Fallback: Compile from Source
            // We need to manually concatenate the files in the correct order because
            // the CLI environment flattens the bundle and breaks relative includes.
            
            // Reordered to satisfy dependencies: Color.metal must be before ACES.metal
            let coreHeaders = ["ColorSpace.metal", "Color.metal", "ACES.metal", "Noise.metal", "ColorKernels.metal", "QualitySettings.metal"]
            let effects = ["FilmGrain.metal", "Vignette.metal", "ColorGrading.metal", "Bloom.metal", "FaceEnhance.metal", "BackgroundBlur.metal"]
            let shaders = ["Shaders.metal", "PostProcessing.metal", "Waveform.metal", "Volumetric.metal", "SplitScreen.metal", "Display.metal", "FITSIDT.metal", "IDT.metal", "Composite.metal", "Pipeline.metal"]
            
            let allFiles = coreHeaders + effects + shaders
            var combinedSource = "#include <metal_stdlib>\nusing namespace metal;\n"
            
            for file in allFiles {
                if let url = Bundle.module.url(forResource: file, withExtension: nil) ?? Bundle.module.url(forResource: (file as NSString).deletingPathExtension, withExtension: "metal") {
                    do {
                        var source = try String(contentsOf: url)
                        
                        // Strip includes
                        let lines = source.components(separatedBy: .newlines)
                        let filteredLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#include") }
                        source = filteredLines.joined(separator: "\n")
                        
                        // Handle Struct Redefinitions by namespacing/renaming based on file
                        if file == "Display.metal" {
                            source = source.replacingOccurrences(of: "VertexIn", with: "DisplayVertexIn")
                            source = source.replacingOccurrences(of: "VertexOut", with: "DisplayVertexOut")
                        } else if file == "Waveform.metal" {
                            source = source.replacingOccurrences(of: "VertexIn", with: "WaveVertexIn")
                            source = source.replacingOccurrences(of: "VertexOut", with: "WaveVertexOut")
                        } else if file == "Volumetric.metal" {
                            source = source.replacingOccurrences(of: "VertexIn", with: "VolVertexIn")
                            source = source.replacingOccurrences(of: "VertexOut", with: "VolVertexOut")
                        } else if file == "SplitScreen.metal" {
                            source = source.replacingOccurrences(of: "VertexIn", with: "SplitVertexIn")
                            source = source.replacingOccurrences(of: "VertexOut", with: "SplitVertexOut")
                        } else if file == "ColorGrading.metal" {
                            source = source.replacingOccurrences(of: "VertexIn", with: "GradeVertexIn")
                            source = source.replacingOccurrences(of: "VertexOut", with: "GradeVertexOut")
                        } else if file == "FITSIDT.metal" {
                             source = source.replacingOccurrences(of: "VertexIn", with: "FITSVertexIn")
                             source = source.replacingOccurrences(of: "VertexOut", with: "FITSVertexOut")
                        } else if file == "Composite.metal" {
                             source = source.replacingOccurrences(of: "SplitScreenParams", with: "CompositeSplitScreenParams")
                        }
                        
                        combinedSource += "\n// --- \(file) ---\n"
                        combinedSource += source
                    } catch {
                        print("⚠️ Failed to read \(file): \(error)")
                    }
                } else {
                    print("⚠️ Could not find \(file) in Bundle.module")
                }
            }
            
            do {
                simLibrary = try device.makeLibrary(source: combinedSource, options: nil)
                print("✅ Compiled Simulation Shaders from combined source.")
            } catch {
                print("❌ Failed to compile combined shaders: \(error)")
                // print("Source:\n\(combinedSource)") // Debug if needed
            }
        }
        
        // Initialize Video Provider with the compiled library
        self.videoProvider = VideoFrameProvider(device: device, library: simLibrary)
        
        if let library = simLibrary {
            // Common Vertex Descriptor
            let vertexDescriptor = MTLVertexDescriptor()
            vertexDescriptor.attributes[0].format = .float4
            vertexDescriptor.attributes[0].offset = 0
            vertexDescriptor.attributes[0].bufferIndex = 0
            vertexDescriptor.attributes[1].format = .float2
            vertexDescriptor.attributes[1].offset = 16
            vertexDescriptor.attributes[1].bufferIndex = 0
            vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride
            vertexDescriptor.layouts[0].stepRate = 1
            vertexDescriptor.layouts[0].stepFunction = .perVertex

            // Video Plane Pipeline
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexDescriptor = vertexDescriptor
            descriptor.vertexFunction = library.makeFunction(name: "video_plane_vertex")
            descriptor.fragmentFunction = library.makeFunction(name: "video_plane_fragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm // Default
            descriptor.depthAttachmentPixelFormat = .invalid
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            
            self.videoPipelineState = try? device.makeRenderPipelineState(descriptor: descriptor)
            
            // Process Pipeline (ACEScg Intermediate)
            let processDescriptor = MTLRenderPipelineDescriptor()
            processDescriptor.vertexDescriptor = vertexDescriptor
            processDescriptor.vertexFunction = library.makeFunction(name: "video_plane_vertex")
            processDescriptor.fragmentFunction = library.makeFunction(name: "video_plane_fragment")
            processDescriptor.colorAttachments[0].pixelFormat = .rgba16Float // ACEScg Linear
            processDescriptor.depthAttachmentPixelFormat = .invalid
            processDescriptor.colorAttachments[0].isBlendingEnabled = true
            processDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            processDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            
            self.processPipelineState = try? device.makeRenderPipelineState(descriptor: processDescriptor)
            
            // Additive Blend Pipeline (for FITS Compositing)
            let addDescriptor = MTLRenderPipelineDescriptor()
            addDescriptor.vertexDescriptor = vertexDescriptor
            addDescriptor.vertexFunction = library.makeFunction(name: "video_plane_vertex")
            addDescriptor.fragmentFunction = library.makeFunction(name: "video_plane_fragment") // Use standard video fragment
            addDescriptor.colorAttachments[0].pixelFormat = .rgba16Float
            addDescriptor.colorAttachments[0].isBlendingEnabled = true
            addDescriptor.colorAttachments[0].rgbBlendOperation = .add
            addDescriptor.colorAttachments[0].alphaBlendOperation = .add
            addDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            addDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            addDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one
            addDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
            addDescriptor.depthAttachmentPixelFormat = .invalid
            
            self.addBlendPipelineState = try? device.makeRenderPipelineState(descriptor: addDescriptor)
            
            // Color Grade Pipeline
            let colorGradeDescriptor = MTLRenderPipelineDescriptor()
            colorGradeDescriptor.vertexDescriptor = vertexDescriptor
            colorGradeDescriptor.vertexFunction = library.makeFunction(name: "video_plane_vertex")
            colorGradeDescriptor.fragmentFunction = library.makeFunction(name: "fx_color_grade_fragment")
            colorGradeDescriptor.colorAttachments[0].pixelFormat = .rgba16Float
            colorGradeDescriptor.depthAttachmentPixelFormat = .invalid
            
            self.colorGradePipelineState = try? device.makeRenderPipelineState(descriptor: colorGradeDescriptor)
            
            // Split Screen Pipeline
            let splitDescriptor = MTLRenderPipelineDescriptor()
            splitDescriptor.vertexDescriptor = vertexDescriptor
            splitDescriptor.vertexFunction = library.makeFunction(name: "video_plane_vertex")
            splitDescriptor.fragmentFunction = library.makeFunction(name: "fx_split_screen_fragment")
            splitDescriptor.colorAttachments[0].pixelFormat = .rgba16Float
            splitDescriptor.depthAttachmentPixelFormat = .invalid
            
            self.splitScreenPipelineState = try? device.makeRenderPipelineState(descriptor: splitDescriptor)
            
            // ODT Pipeline (Display)
            let odtDescriptor = MTLRenderPipelineDescriptor()
            odtDescriptor.vertexDescriptor = vertexDescriptor
            odtDescriptor.vertexFunction = library.makeFunction(name: "display_vertex")
            odtDescriptor.fragmentFunction = library.makeFunction(name: "display_fragment")
            odtDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm // Output to screen
            odtDescriptor.depthAttachmentPixelFormat = .invalid
            
            self.odtPipelineState = try? device.makeRenderPipelineState(descriptor: odtDescriptor)
            
            // ODT Pipeline (Export - RGBA16Float)
            let odtFloatDescriptor = MTLRenderPipelineDescriptor()
            odtFloatDescriptor.vertexDescriptor = vertexDescriptor
            odtFloatDescriptor.vertexFunction = library.makeFunction(name: "display_vertex")
            odtFloatDescriptor.fragmentFunction = library.makeFunction(name: "display_fragment")
            odtFloatDescriptor.colorAttachments[0].pixelFormat = .rgba16Float // Output to Export Texture
            odtFloatDescriptor.depthAttachmentPixelFormat = .invalid
            
            self.odtPipelineFloatState = try? device.makeRenderPipelineState(descriptor: odtFloatDescriptor)
            
            // Waveform Pipeline
            let waveDescriptor = MTLRenderPipelineDescriptor()
            waveDescriptor.vertexDescriptor = vertexDescriptor
            waveDescriptor.vertexFunction = library.makeFunction(name: "video_plane_vertex")
            waveDescriptor.fragmentFunction = library.makeFunction(name: "waveform_fragment")
            waveDescriptor.colorAttachments[0].pixelFormat = .rgba16Float
            waveDescriptor.depthAttachmentPixelFormat = .invalid
            waveDescriptor.colorAttachments[0].isBlendingEnabled = true
            waveDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            waveDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            
            self.waveformPipelineState = try? device.makeRenderPipelineState(descriptor: waveDescriptor)
            
            // Volume Pipeline
            let volDescriptor = MTLRenderPipelineDescriptor()
            volDescriptor.vertexDescriptor = vertexDescriptor
            volDescriptor.vertexFunction = library.makeFunction(name: "volume_vertex")
            volDescriptor.fragmentFunction = library.makeFunction(name: "volume_fragment")
            volDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            volDescriptor.depthAttachmentPixelFormat = .invalid
            volDescriptor.colorAttachments[0].isBlendingEnabled = true
            volDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            volDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            
            self.volumePipelineState = try? device.makeRenderPipelineState(descriptor: volDescriptor)
            
            // Load IDT Kernels
            if let srgbFunc = library.makeFunction(name: "idt_srgb_to_acescg") {
                self.idtSRGBToACEScg = try? device.makeComputePipelineState(function: srgbFunc)
            }
            if let rec709Func = library.makeFunction(name: "idt_rec709_to_acescg") {
                self.idtRec709ToACEScg = try? device.makeComputePipelineState(function: rec709Func)
            }
            if let genericFunc = library.makeFunction(name: "idt_generic_to_acescg") {
                self.idtGenericToACEScg = try? device.makeComputePipelineState(function: genericFunc)
            }
            if let fitsFunc = library.makeFunction(name: "idt_fits_to_acescg") {
                self.idtFITSToACEScg = try? device.makeComputePipelineState(function: fitsFunc)
            }
            if let debugFunc = library.makeFunction(name: "jwstIDTDebugCopy") {
                self.idtFITSDebugCopy = try? device.makeComputePipelineState(function: debugFunc)
            }
            if let constFunc = library.makeFunction(name: "jwstIDTDebugConstant") {
                self.idtFITSConstantFill = try? device.makeComputePipelineState(function: constFunc)
            }
            if let dataFunc = library.makeFunction(name: "jwstIDTDebugData") {
                self.idtFITSDataDebug = try? device.makeComputePipelineState(function: dataFunc)
            }
            if let sanityFunc = library.makeFunction(name: "idt_sanity_constant") {
                self.idtSanityConstant = try? device.makeComputePipelineState(function: sanityFunc)
            }
            if let copyFunc = library.makeFunction(name: "idt_copy_norm") {
                self.idtCopyNorm = try? device.makeComputePipelineState(function: copyFunc)
            }
            
            // Diagnostic Kernels
            if let fitsMinMaxFunc = library.makeFunction(name: "FITSMinMaxKernel") {
                self.fitsMinMaxPipeline = try? device.makeComputePipelineState(function: fitsMinMaxFunc)
            }
            if let compMinMaxFunc = library.makeFunction(name: "CompositeMinMaxKernel") {
                self.compositeMinMaxPipeline = try? device.makeComputePipelineState(function: compMinMaxFunc)
            }
            
            if let finalCompFunc = library.makeFunction(name: "final_composite") {
                self.finalCompositePipelineState = try? device.makeComputePipelineState(function: finalCompFunc)
            }
            
            if let jwstCompFunc = library.makeFunction(name: "jwst_composite_v4") {
                do {
                    self.jwstCompositePipelineState = try device.makeComputePipelineState(function: jwstCompFunc)
                } catch {
                    print("❌ Failed to create JWST Composite Pipeline: \(error)")
                }
            }
            
            if let toneMapFunc = library.makeFunction(name: "toneMapKernel") {
                self.toneMapPipelineState = try? device.makeComputePipelineState(function: toneMapFunc)
            }
            if let acesFunc = library.makeFunction(name: "acesOutputKernel") {
                self.acesOutputPipelineState = try? device.makeComputePipelineState(function: acesFunc)
            } else {
                print("❌ Could not find function 'jwst_composite_v2' in library")
            }
        }
    }
    
    public func loadAsset(assetId: UUID, quality: AssetQuality = .preview) {
        guard let asset = assetManager.get(id: assetId) else {
            print("Asset not found in manager: \(assetId)")
            return
        }
        
        guard let url = assetManager.resolve(assetId: assetId, quality: quality) else {
            print("Could not resolve URL for asset: \(asset.name)")
            return
        }
        
        switch asset.type {
        case .fits:
            // Use VideoProvider for FITS (it now supports caching and loading)
            videoProvider.register(assetId: assetId, url: url)
        case .audio:
            loadAudio(url: url)
        case .video:
            videoProvider.register(assetId: assetId, url: url)
            // print("Registered Video Asset: \(url.lastPathComponent)")
        case .image:
            // Avoid re-loading the same image every frame.
            if textureManager.texture(for: assetId) != nil {
                return
            }
            do {
                try textureManager.loadTexture(url: url, for: assetId)
                if diagnosticsEnabled {
                    print("Loaded Image Asset: \(url.lastPathComponent)")
                }
            } catch {
                print("Failed to load Image: \(error)")
            }
        default:
            print("Unsupported asset type: \(asset.type)")
        }
    }

    public func loadLUT(url: URL) {
        do {
            self.activeLUT = try lutLoader.loadCubeLUT(url: url)
            print("Loaded LUT: \(url.lastPathComponent)")
        } catch {
            print("Failed to load LUT: \(error)")
        }
    }
    
    public func loadAudio(url: URL) {
        audioProvider.load(url: url)
    }
    
    public func loadFITS(url: URL, assetId: UUID) {
        // Check cache first
        if textureManager.texture(for: assetId) != nil {
            return
        }
        
        do {
            // Use Core FITSReader
            let asset = try fitsReader.read(url: url)
            
            // Use MetalTextureManager
            if let texture = MetalTextureManager.shared.createTexture(from: asset) {
                textureManager.register(texture: texture, for: assetId)
                print("Loaded FITS Asset: \(url.lastPathComponent) (\(asset.width)x\(asset.height))")
            } else {
                print("Failed to create Metal texture for FITS asset")
            }
        } catch {
            print("Failed to load FITS: \(error)")
        }
    }
    
    /// Renders a compiled pass.
    /// - Parameters:
    ///   - pass: The RenderPass instructions to execute.
    ///   - outputTexture: The texture to write the final image to.
    public func render(pass: RenderPass, outputTexture: MTLTexture) async throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw SimulationError.renderPassFailed
        }
        
        let time = await clock.currentTime
        
        // Execute Commands
        // We need a temporary texture cache for intermediate node results
        var nodeTextures: [UUID: MTLTexture] = [:]
        var debugTexturesToCheck: [(MTLTexture, String)] = []
        
        for command in pass.commands {
            switch command {
            case .loadTexture(let nodeId, let assetId, let isVideo, _, _):
                var sourceTexture: MTLTexture?
                
                if isVideo {
                    if let texture = videoProvider.texture(for: assetId, at: time) {
                        sourceTexture = texture
                    } else {
                        // Fallback to static if video frame missing (e.g. not started yet)
                        if let texture = textureManager.texture(for: assetId) {
                            sourceTexture = texture
                        } else {
                            print("⚠️ Missing video texture for asset \(assetId) at \(time.seconds)s")
                        }
                    }
                } else {
                    if let texture = textureManager.texture(for: assetId) {
                        sourceTexture = texture
                    } else {
                        print("⚠️ Missing texture for asset \(assetId)")
                    }
                }
                
                // Apply IDT (Input Device Transform) using Generic Kernel
                // DEBUG: Force bypass IDT to verify if it's the cause of black frames
                /*
                if let input = sourceTexture, let idt = idtGenericToACEScg {
                    // Create ACEScg texture
                    let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: input.width, height: input.height, mipmapped: false)
                    desc.usage = [.shaderRead, .shaderWrite]
                    
                    if let output = device.makeTexture(descriptor: desc),
                       let encoder = commandBuffer.makeComputeCommandEncoder() {
                        
                        encoder.setComputePipelineState(idt)
                        encoder.setTexture(input, index: 0)
                        encoder.setTexture(output, index: 1)
                        
                        var params = IDTParams(transferFunction: Int32(tf), primaries: Int32(prim))
                        encoder.setBytes(&params, length: MemoryLayout<IDTParams>.stride, index: 0)
                        
                        let w = idt.threadExecutionWidth
                        let h = idt.maxTotalThreadsPerThreadgroup / w
                        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
                        let threadsPerGrid = MTLSize(width: input.width, height: input.height, depth: 1)
                        
                        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                        encoder.endEncoding()
                        
                        nodeTextures[nodeId] = output
                    }
                } else {
                    // Fallback: Just use source if IDT fails (should not happen)
                    if let input = sourceTexture {
                        nodeTextures[nodeId] = input
                    }
                }
                */
                if let input = sourceTexture {
                    nodeTextures[nodeId] = input
                }
                
            case .loadFITS(let nodeId, let assetId):
                // 1. Get Raw Texture (R32Float)
                var input = videoProvider.texture(for: assetId, at: time)
                if input == nil {
                    input = textureManager.texture(for: assetId)
                }
                
                guard let input = input else {
                    print("⚠️ Missing FITS texture for asset \(assetId)")
                    continue
                }
                
                nodeTextures[nodeId] = input
                
                /*
                // 2. Apply Scientific IDT (FITS -> ACEScg)
                
                if idtDebugMode == .constant, let idt = idtFITSConstantFill {
                    // Use standard resolution for this test
                    let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 1920, height: 1080, mipmapped: false)
                    desc.usage = [.shaderRead, .shaderWrite]
                    
                    if let output = device.makeTexture(descriptor: desc),
                       let encoder = commandBuffer.makeComputeCommandEncoder() {
                        
                        encoder.setComputePipelineState(idt)
                        // Kernel expects outTex at texture(0)
                        encoder.setTexture(output, index: 0)
                        
                        struct FITSParams {
                            var exposure: Float
                            var blackPoint: Float
                            var whitePoint: Float
                            var stretch: Float
                            var falseColor: SIMD4<Float>
                        }
                        var params = FITSParams(exposure: exposure, blackPoint: blackPoint, whitePoint: whitePoint, stretch: 10.0, falseColor: color)
                        
                        print("[IDT-DEBUG] Params - Exp: \(exposure), BP: \(blackPoint), WP: \(whitePoint), Color: \(color)")
                        encoder.setBytes(&params, length: MemoryLayout<FITSParams>.stride, index: 0)
                        
                        let w = idt.threadExecutionWidth
                        let h = idt.maxTotalThreadsPerThreadgroup / w
                        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
                        let threadsPerGrid = MTLSize(width: output.width, height: output.height, depth: 1)
                        
                        print("[IDT-DEBUG] Constant Fill Dispatch")
                        
                        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                        encoder.endEncoding()
                        
                        nodeTextures[nodeId] = output
                    }
                } else if idtDebugMode == .data, let idt = idtFITSDataDebug {
                    // Data Debug Mode: FITS -> Normalize -> Scale -> Output
                    let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: input.width, height: input.height, mipmapped: false)
                    desc.usage = [.shaderRead, .shaderWrite]
                    
                    if let output = device.makeTexture(descriptor: desc),
                       let encoder = commandBuffer.makeComputeCommandEncoder() {
                        
                        encoder.setComputePipelineState(idt)
                        encoder.setTexture(input, index: 0)
                        encoder.setTexture(output, index: 1)
                        
                        struct FITSParams {
                            var exposure: Float
                            var blackPoint: Float
                            var whitePoint: Float
                            var stretch: Float
                            var falseColor: SIMD4<Float>
                        }
                        var params = FITSParams(exposure: exposure, blackPoint: blackPoint, whitePoint: whitePoint, stretch: 10.0, falseColor: color)
                        
                        encoder.setBytes(&params, length: MemoryLayout<FITSParams>.stride, index: 0)
                        
                        let w = idt.threadExecutionWidth
                        let h = idt.maxTotalThreadsPerThreadgroup / w
                        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
                        let threadsPerGrid = MTLSize(width: output.width, height: output.height, depth: 1)
                        
                        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                        encoder.endEncoding()
                        
                        nodeTextures[nodeId] = output
                    }
                } else if idtDebugMode == .sanity, let idt = idtSanityConstant {
                    // Sanity Check: Constant Fill
                    let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: input.width, height: input.height, mipmapped: false)
                    desc.usage = [.shaderRead, .shaderWrite]
                    
                    if let output = device.makeTexture(descriptor: desc),
                       let encoder = commandBuffer.makeComputeCommandEncoder() {
                        
                        encoder.setComputePipelineState(idt)
                        // Kernel expects outTex at texture(1)
                        encoder.setTexture(output, index: 1)
                        
                        let w = idt.threadExecutionWidth
                        let h = idt.maxTotalThreadsPerThreadgroup / w
                        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
                        let threadsPerGrid = MTLSize(width: output.width, height: output.height, depth: 1)
                        
                        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                        encoder.endEncoding()
                        
                        nodeTextures[nodeId] = output
                        print("✅ [IDT-Sanity] Processed FITS Node \(nodeId)")
                        debugTexturesToCheck.append((output, "IDT_Sanity_\(nodeId)"))
                    }
                } else if idtDebugMode == .copy, let idt = idtCopyNorm {
                    // Sanity Check: Copy Norm
                    let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: input.width, height: input.height, mipmapped: false)
                    desc.usage = [.shaderRead, .shaderWrite]
                    
                    if let output = device.makeTexture(descriptor: desc),
                       let encoder = commandBuffer.makeComputeCommandEncoder() {
                        
                        encoder.setComputePipelineState(idt)
                        encoder.setTexture(input, index: 0)
                        encoder.setTexture(output, index: 1)
                        
                        struct FITSParams {
                            var exposure: Float
                            var blackPoint: Float
                            var whitePoint: Float
                            var stretch: Float
                            var falseColor: SIMD4<Float>
                        }
                        var params = FITSParams(exposure: exposure, blackPoint: blackPoint, whitePoint: whitePoint, stretch: 10.0, falseColor: color)
                        
                        encoder.setBytes(&params, length: MemoryLayout<FITSParams>.stride, index: 0)
                        
                        let w = idt.threadExecutionWidth
                        let h = idt.maxTotalThreadsPerThreadgroup / w
                        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
                        let threadsPerGrid = MTLSize(width: output.width, height: output.height, depth: 1)
                        
                        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                        encoder.endEncoding()
                        
                        nodeTextures[nodeId] = output
                    }
                } else if let idt = idtFITSToACEScg {
                    let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: input.width, height: input.height, mipmapped: false)
                    desc.usage = [.shaderRead, .shaderWrite]
                    
                    if let output = device.makeTexture(descriptor: desc),
                       let encoder = commandBuffer.makeComputeCommandEncoder() {
                        
                        encoder.setComputePipelineState(idt)
                        encoder.setTexture(input, index: 0)
                        encoder.setTexture(output, index: 1)
                        
                        struct FITSParams {
                            var exposure: Float
                            var blackPoint: Float
                            var whitePoint: Float
                            var stretch: Float
                            var falseColor: SIMD4<Float>
                        }
                        var params = FITSParams(exposure: exposure, blackPoint: blackPoint, whitePoint: whitePoint, stretch: stretch, falseColor: color)
                        // print("[IDT] Params - Exp: \(exposure), BP: \(blackPoint), WP: \(whitePoint), Color: \(color)")
                        encoder.setBytes(&params, length: MemoryLayout<FITSParams>.stride, index: 0)
                        
                        let w = idt.threadExecutionWidth
                        let h = idt.maxTotalThreadsPerThreadgroup / w
                        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
                        let threadsPerGrid = MTLSize(width: input.width, height: input.height, depth: 1)
                        
                        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                        encoder.endEncoding()
                        
                        nodeTextures[nodeId] = output
                        print("✅ [IDT] Processed FITS Node \(nodeId)")
                        debugTexturesToCheck.append((output, "IDT_Output_\(nodeId)"))
                    } else {
                        print("❌ [IDT] Failed to create output texture or encoder")
                    }
                } else {
                    print("❌ [IDT] Pipeline idtFITSToACEScg is nil")
                }
                */
                
            case .generateText(let nodeId, let text, let fontName, let size):
                // 1. Create Output Texture (ACEScg Linear)
                let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: outputTexture.width, height: outputTexture.height, mipmapped: false)
                desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
                guard let outputTex = device.makeTexture(descriptor: desc) else { continue }
                nodeTextures[nodeId] = outputTex
                
                // 2. Clear Texture (Transparent)
                let renderPassDesc = MTLRenderPassDescriptor()
                renderPassDesc.colorAttachments[0].texture = outputTex
                renderPassDesc.colorAttachments[0].loadAction = .clear
                renderPassDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
                renderPassDesc.colorAttachments[0].storeAction = .store
                
                if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) {
                    encoder.endEncoding()
                }
                
                // 3. Render Text
                let fontID = (try? fontRegistry.register(name: fontName, size: CGFloat(size))) ?? 0
                
                let style = TextStyle(color: SIMD4(1,1,1,1))
                let cmd = TextDrawCommand(
                    text: text,
                    position: SIMD3<Float>(Float(outputTexture.width)/2, Float(outputTexture.height)/2, 0),
                    fontSize: CGFloat(size),
                    style: style,
                    fontID: fontID
                )
                
                let proj = matrix_float4x4(columns: (
                    SIMD4(2.0 / Float(outputTexture.width), 0, 0, 0),
                    SIMD4(0, -2.0 / Float(outputTexture.height), 0, 0),
                    SIMD4(0, 0, 1, 0),
                    SIMD4(-1, 1, 0, 1)
                ))
                
                textRenderer.render(command: cmd, to: outputTex, projection: proj)
                
            case .generateWaveform(let nodeId, let color):
                // 1. Create Output Texture
                let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: outputTexture.width, height: outputTexture.height, mipmapped: false)
                desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
                guard let outputTex = device.makeTexture(descriptor: desc) else { continue }
                nodeTextures[nodeId] = outputTex
                
                // 2. Get Waveform Data
                let samplesCount = 1024 // Resolution of waveform
                let samples = audioProvider.getWaveform(at: time.seconds, duration: 0.05, samplesCount: samplesCount) // 50ms window
                
                // 3. Create Buffer
                let bufferSize = samplesCount * MemoryLayout<Float>.stride
                guard let sampleBuffer = device.makeBuffer(bytes: samples, length: bufferSize, options: []) else { continue }
                
                // 4. Render Pass
                let renderPassDesc = MTLRenderPassDescriptor()
                renderPassDesc.colorAttachments[0].texture = outputTex
                renderPassDesc.colorAttachments[0].loadAction = .clear
                renderPassDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
                renderPassDesc.colorAttachments[0].storeAction = .store
                
                guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else { continue }
                
                // Set Viewport
                let viewport = MTLViewport(originX: 0, originY: 0, width: Double(outputTex.width), height: Double(outputTex.height), znear: 0, zfar: 1)
                encoder.setViewport(viewport)
                
                if let pipeline = waveformPipelineState {
                    encoder.setRenderPipelineState(pipeline)
                    encoder.setFragmentBuffer(sampleBuffer, offset: 0, index: 0)
                    
                    // Bind Geometry
                    encoder.setVertexBuffer(quadBuffer, offset: 0, index: 0)
                    var identity = matrix_identity_float4x4
                    encoder.setVertexBytes(&identity, length: MemoryLayout<matrix_float4x4>.stride, index: 1)
                    
                    struct WaveParams {
                        var color: SIMD4<Float>
                        var sampleCount: UInt32
                        var thickness: Float
                        var amplitude: Float
                    }
                    var params = WaveParams(color: color, sampleCount: UInt32(samplesCount), thickness: 0.01, amplitude: 0.8)
                    encoder.setFragmentBytes(&params, length: MemoryLayout<WaveParams>.stride, index: 1)
                    
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                }
                encoder.endEncoding()
                
            case .process(let nodeId, let shaderName, let inputIds, let params):
                // Special handling for Compute Shaders (Post-Process)
                if shaderName == "final_composite" {
                    guard let pipeline = finalCompositePipelineState else { continue }
                    
                    // Create Output Texture (Write Access)
                    let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: outputTexture.width, height: outputTexture.height, mipmapped: false)
                    desc.usage = [.shaderRead, .shaderWrite]
                    guard let outputTex = device.makeTexture(descriptor: desc) else { continue }
                    outputTex.label = "PostProcess_\(nodeId)"
                    nodeTextures[nodeId] = outputTex
                    
                    guard let encoder = commandBuffer.makeComputeCommandEncoder() else { continue }
                    encoder.setComputePipelineState(pipeline)
                    
                    // Bind Input (Texture 0)
                    if let inputId = inputIds.first, let inputTex = nodeTextures[inputId] {
                        encoder.setTexture(inputTex, index: 0)
                    }
                    
                    // Bind Output (Texture 1)
                    encoder.setTexture(outputTex, index: 1)
                    
                    // Bind LUT (Texture 2)
                    if let lut = activeLUT {
                        encoder.setTexture(lut, index: 2)
                    } else if let identity = identityLUT {
                        encoder.setTexture(identity, index: 2)
                    }
                    
                    // Bind Bloom (Texture 3) - Placeholder
                    // encoder.setTexture(bloomTex, index: 3)
                    
                    // Bind Params
                    var vignetteIntensity = params["vignetteIntensity"]?.floatValue ?? 0.0
                    encoder.setBytes(&vignetteIntensity, length: 4, index: 0)
                    
                    var vignetteSmoothness = params["vignetteSmoothness"]?.floatValue ?? 0.0
                    encoder.setBytes(&vignetteSmoothness, length: 4, index: 1)
                    
                    var filmGrainStrength = params["filmGrainStrength"]?.floatValue ?? 0.0
                    encoder.setBytes(&filmGrainStrength, length: 4, index: 2)
                    
                    var lutIntensity = params["lutIntensity"]?.floatValue ?? 1.0
                    encoder.setBytes(&lutIntensity, length: 4, index: 3)
                    
                    var hasLUT = (activeLUT != nil)
                    encoder.setBytes(&hasLUT, length: 1, index: 4)
                    
                    var timeVal = Float(time.seconds)
                    encoder.setBytes(&timeVal, length: 4, index: 5)
                    
                    var letterboxRatio = params["letterboxRatio"]?.floatValue ?? 0.0
                    encoder.setBytes(&letterboxRatio, length: 4, index: 6)
                    
                    var exposure = params["exposure"]?.floatValue ?? 1.0
                    encoder.setBytes(&exposure, length: 4, index: 7)
                    
                    var tonemapOperator = UInt32(params["tonemapOperator"]?.floatValue ?? 1.0) // Default ACES Approx
                    encoder.setBytes(&tonemapOperator, length: 4, index: 8)
                    
                    var saturation = params["saturation"]?.floatValue ?? 1.0
                    encoder.setBytes(&saturation, length: 4, index: 9)
                    
                    var contrast = params["contrast"]?.floatValue ?? 1.0
                    encoder.setBytes(&contrast, length: 4, index: 10)
                    
                    var odt = UInt32(params["odt"]?.floatValue ?? 1.0) // Default sRGB
                    encoder.setBytes(&odt, length: 4, index: 11)
                    
                    var debugFlag = UInt32(0)
                    encoder.setBytes(&debugFlag, length: 4, index: 12)
                    
                    var validationMode = UInt32(0)
                    encoder.setBytes(&validationMode, length: 4, index: 13)
                    
                    var bloomStrength = params["bloomStrength"]?.floatValue ?? 0.0
                    encoder.setBytes(&bloomStrength, length: 4, index: 14)
                    
                    var hasBloom = false
                    encoder.setBytes(&hasBloom, length: 1, index: 15)
                    
                    // Dispatch
                    let w = pipeline.threadExecutionWidth
                    let h = pipeline.maxTotalThreadsPerThreadgroup / w
                    let threadsPerGroup = MTLSizeMake(w, h, 1)
                    let threadsPerGrid = MTLSizeMake(outputTex.width, outputTex.height, 1)
                    
                    encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
                    encoder.endEncoding()
                    
                    continue
                } else if shaderName == "toneMapKernel" {
                    guard let pipeline = toneMapPipelineState else { continue }
                    
                    let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: outputTexture.width, height: outputTexture.height, mipmapped: false)
                    desc.usage = [.shaderRead, .shaderWrite]
                    guard let outputTex = device.makeTexture(descriptor: desc) else { continue }
                    nodeTextures[nodeId] = outputTex
                    
                    guard let encoder = commandBuffer.makeComputeCommandEncoder() else { continue }
                    encoder.setComputePipelineState(pipeline)
                    
                    if let inputId = inputIds.first, let inputTex = nodeTextures[inputId] {
                        encoder.setTexture(inputTex, index: 0)
                    }
                    encoder.setTexture(outputTex, index: 1)
                    
                    var blackPoint = params["blackPoint"]?.floatValue ?? 0.0
                    encoder.setBytes(&blackPoint, length: 4, index: 0)
                    
                    var whitePoint = params["whitePoint"]?.floatValue ?? 1.0
                    encoder.setBytes(&whitePoint, length: 4, index: 1)
                    
                    var gamma = params["gamma"]?.floatValue ?? 1.0
                    encoder.setBytes(&gamma, length: 4, index: 2)
                    
                    let w = pipeline.threadExecutionWidth
                    let h = pipeline.maxTotalThreadsPerThreadgroup / w
                    let threadsPerGroup = MTLSizeMake(w, h, 1)
                    let threadsPerGrid = MTLSizeMake(outputTex.width, outputTex.height, 1)
                    
                    encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
                    encoder.endEncoding()
                    continue
                    
                } else if shaderName == "acesOutputKernel" {
                    guard let pipeline = acesOutputPipelineState else { continue }
                    
                    let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: outputTexture.width, height: outputTexture.height, mipmapped: false)
                    desc.usage = [.shaderRead, .shaderWrite]
                    guard let outputTex = device.makeTexture(descriptor: desc) else { continue }
                    nodeTextures[nodeId] = outputTex
                    
                    guard let encoder = commandBuffer.makeComputeCommandEncoder() else { continue }
                    encoder.setComputePipelineState(pipeline)
                    
                    if let inputId = inputIds.first, let inputTex = nodeTextures[inputId] {
                        encoder.setTexture(inputTex, index: 0)
                    }
                    encoder.setTexture(outputTex, index: 1)
                    
                    let w = pipeline.threadExecutionWidth
                    let h = pipeline.maxTotalThreadsPerThreadgroup / w
                    let threadsPerGroup = MTLSizeMake(w, h, 1)
                    let threadsPerGrid = MTLSizeMake(outputTex.width, outputTex.height, 1)
                    
                    encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
                    encoder.endEncoding()
                    continue
                    
                } else if shaderName == "jwst_composite" {
                    print("Processing JWST Composite Node: \(nodeId)")
                    guard let pipeline = jwstCompositePipelineState else { 
                        print("❌ JWST Composite Pipeline is NIL")
                        continue 
                    }
                    
                    // Create Output Texture (Write Access)
                    let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: outputTexture.width, height: outputTexture.height, mipmapped: false)
                    desc.usage = [.shaderRead, .shaderWrite]
                    guard let outputTex = device.makeTexture(descriptor: desc) else { continue }
                    outputTex.label = "JWSTComposite_\(nodeId)"
                    nodeTextures[nodeId] = outputTex
                    
                    guard let encoder = commandBuffer.makeComputeCommandEncoder() else { continue }
                    encoder.setComputePipelineState(pipeline)
                    
                    // Bind Inputs (Textures 0-1)
                    // v46: Input 0 = Density, Input 1 = Color
                    for i in 0..<2 {
                        var bound = false
                        if i < inputIds.count {
                            let inputId = inputIds[i]
                            if inputId.uuidString != "00000000-0000-0000-0000-000000000000",
                               let inputTex = nodeTextures[inputId] {
                                encoder.setTexture(inputTex, index: i)
                                bound = true
                                print("  Bound Input \(i): \(inputId) (\(inputTex.width)x\(inputTex.height))")
                            }
                        }
                        
                        if !bound {
                            print("  ⚠️ Missing Input \(i) for JWST Composite")
                        }
                    }
                    
                    // Bind Output (Texture 2)
                    encoder.setTexture(outputTex, index: 2)
                    
                    // Bind Stars (Buffer 0)
                    if let stars = starBuffer {
                        encoder.setBuffer(stars, offset: 0, index: 0)
                    } else {
                        // Bind dummy buffer if no stars
                         let dummySize = MemoryLayout<SimStarData>.stride * 64
                         if let dummy = device.makeBuffer(length: dummySize, options: []) {
                             encoder.setBuffer(dummy, offset: 0, index: 0)
                         }
                    }
                    
                    // Bind Config (Buffer 1)
                    if let config = configBuffer {
                        encoder.setBuffer(config, offset: 0, index: 1)
                    } else {
                         // Bind dummy config
                         var dummyConfig = SimConfigData()
                         encoder.setBytes(&dummyConfig, length: MemoryLayout<SimConfigData>.stride, index: 1)
                    }
                    
                    // Bind Time (Buffer 2)
                    var timeVal = Float(await clock.currentTime.seconds)
                    encoder.setBytes(&timeVal, length: MemoryLayout<Float>.stride, index: 2)
                    

                    
                    // Dispatch
                    let w = pipeline.threadExecutionWidth
                    let h = pipeline.maxTotalThreadsPerThreadgroup / w
                    let threadsPerGroup = MTLSizeMake(w, h, 1)
                    let threadsPerGrid = MTLSizeMake(outputTex.width, outputTex.height, 1)
                    
                    encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
                    encoder.endEncoding()
                    
                    continue
                }

                // 1. Create Output Texture for this node (ACEScg Linear)
                let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: outputTexture.width, height: outputTexture.height, mipmapped: false)
                desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
                guard let outputTex = device.makeTexture(descriptor: desc) else { continue }
                outputTex.label = "ProcessOutput_\(nodeId)"
                nodeTextures[nodeId] = outputTex
                
                // DIAGNOSTIC: Log Composite Target
                print("[Composite] Using output texture for Node \(nodeId):")
                print("  Pointer: \(Unmanaged.passUnretained(outputTex).toOpaque())")
                print("  Label: \(outputTex.label ?? "nil")")
                print("  Size: \(outputTex.width)x\(outputTex.height)")
                print("  PixelFormat: \(outputTex.pixelFormat.rawValue)")
                
                // 2. Render Pass
                let renderPassDesc = MTLRenderPassDescriptor()
                renderPassDesc.colorAttachments[0].texture = outputTex
                renderPassDesc.colorAttachments[0].loadAction = .clear
                renderPassDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
                renderPassDesc.colorAttachments[0].storeAction = .store
                
                guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else { continue }
                
                // Set Viewport
                let viewport = MTLViewport(originX: 0, originY: 0, width: Double(outputTex.width), height: Double(outputTex.height), znear: 0, zfar: 1)
                encoder.setViewport(viewport)
                
                // Bind Geometry
                encoder.setVertexBuffer(quadBuffer, offset: 0, index: 0)
                var identity = matrix_identity_float4x4
                encoder.setVertexBytes(&identity, length: MemoryLayout<matrix_float4x4>.stride, index: 1)
                
                // 3. Setup Pipeline & Params
                if shaderName == "color_grade" {
                    guard let pipeline = colorGradePipelineState else { encoder.endEncoding(); continue }
                    encoder.setRenderPipelineState(pipeline)
                    
                    // Parse ColorGradeParams
                    var gradeParams = ColorGradeParams()
                    if let v = params["exposure"], case .float(let f) = v { gradeParams.exposure = Float(f) }
                    if let v = params["temperature"], case .float(let f) = v { gradeParams.temperature = Float(f) }
                    if let v = params["tint"], case .float(let f) = v { gradeParams.tint = Float(f) }
                    if let v = params["saturation"], case .float(let f) = v { gradeParams.saturation = Float(f) }
                    if let v = params["contrast"], case .float(let f) = v { gradeParams.contrast = Float(f) }
                    if let v = params["contrastPivot"], case .float(let f) = v { gradeParams.contrastPivot = Float(f) }
                    if let v = params["lutIntensity"], case .float(let f) = v { gradeParams.lutIntensity = Float(f) }
                    
                    encoder.setFragmentBytes(&gradeParams, length: MemoryLayout<ColorGradeParams>.size, index: 0)
                    
                    // Bind LUT (Active or Identity)
                    if let lut = activeLUT {
                        encoder.setFragmentTexture(lut, index: 1)
                    } else if let identity = identityLUT {
                        encoder.setFragmentTexture(identity, index: 1)
                    }
                    
                } else if shaderName == "split_screen" {
                    guard let pipeline = splitScreenPipelineState else { encoder.endEncoding(); continue }
                    encoder.setRenderPipelineState(pipeline)
                    
                } else if shaderName == "blend" {
                    let mode = params["mode"]?.stringValue ?? "normal"
                    
                    if mode == "add" {
                        guard let pipeline = addBlendPipelineState else { encoder.endEncoding(); continue }
                        encoder.setRenderPipelineState(pipeline)
                        
                        // Dissolve shader expects a mix factor.
                        // For additive blend, we want A + B.
                        // The dissolve shader does mix(A, B, w).
                        // If we use native blending (src + dst), we should just draw B over A.
                        // But our architecture is: Input 0 (BG), Input 1 (FG) -> Output.
                        // We bind BG to texture 0, FG to texture 1.
                        // If we use native blending, we need to draw FG *over* BG.
                        // So we should clear output to BG, then draw FG with additive blend.
                        
                        // Wait, the pipeline is configured to blend with the destination.
                        // But we are clearing the destination to transparent at the start of this block!
                        // See: renderPassDesc.colorAttachments[0].loadAction = .clear
                        
                        // So we need to:
                        // 1. Draw BG (Opaque)
                        // 2. Draw FG (Additive)
                        
                        // But our current architecture runs ONE draw call per node.
                        // The shader samples both textures and outputs the result.
                        // If the shader does the math, we don't need native blending.
                        // If we use native blending, we need two draw calls.
                        
                        // Let's stick to the shader doing the math if possible.
                        // But I don't have a "composite_add" shader compiled in the library yet?
                        // I saw `Composite.metal` in the file list. Let's check if it's in the library.
                        // If `composite_add` exists, we should use it.
                        
                        // Assuming `composite_add` is available (I saw the file).
                        // I need to create a pipeline for it.
                        // But I didn't create `compositeAddPipelineState` in init.
                        // I created `addBlendPipelineState` which uses `fx_dissolve_fragment` with native blending.
                        // That's confusing.
                        
                        // Let's try to use `composite_add` kernel if I can find it.
                        // But I can't change init easily without re-reading everything.
                        
                        // Let's use the `addBlendPipelineState` I just added.
                        // It uses `fx_dissolve_fragment` + Native Additive Blend.
                        // `fx_dissolve_fragment` samples A and B and mixes them.
                        // If we use native additive blend, the result of the shader (mix) is added to the destination (clear).
                        // That's not what we want.
                        
                        // We want: Output = A + B.
                        // If we use `composite_add` shader:
                        // Output = sample(A) + sample(B).
                        // This is the cleanest way.
                        
                        // I will assume `composite_add` is available as `fx_composite_add_fragment`?
                        // I need to check the function name in `Composite.metal`.
                        // It was `kernel void composite_add`. That's a COMPUTE kernel!
                        // Ah, `Composite.metal` uses `kernel void`.
                        // My engine uses Render Pipelines (Vertex/Fragment).
                        
                        // So I cannot use `composite_add` directly in the render pass loop.
                        // I need to use a Compute Pass or a Fragment Shader.
                        
                        // Let's look at `fx_dissolve_fragment`.
                        // It's likely in `Effects/Transition.metal` (implied).
                        
                        // Plan B: Use `processPipelineState` (which is generic) but with a custom fragment shader?
                        // No, `processPipelineState` uses `video_plane_fragment` (implied default).
                        
                        // Let's just use the `addBlendPipelineState` I added, but change the function to `fx_add_fragment` if it exists?
                        // Or just write a quick fragment shader? No, I can't write metal files easily and compile them without a build step.
                        
                        // Wait, `addBlendPipelineState` uses `fx_dissolve_fragment`.
                        // `mix(a, b, w)`.
                        // If I set w=0, result is A.
                        // If I set w=1, result is B.
                        // If I set w=0.5, result is 0.5A + 0.5B.
                        
                        // If I enable native additive blending:
                        // Dst = Dst + Src.
                        // Dst is cleared to 0.
                        // So Output = mix(A, B, w).
                        // This is NOT A + B.
                        
                        // I need a shader that outputs A + B.
                        // Or I need to draw A, then draw B with additive blend.
                        
                        // Let's do the 2-pass draw approach within this block.
                        // 1. Draw BG (Opaque)
                        // 2. Draw FG (Additive)
                        
                        // But `inputIds` has 2 IDs.
                        // We need textures for them.
                        guard inputIds.count >= 2,
                              let texBG = nodeTextures[inputIds[0]],
                              let texFG = nodeTextures[inputIds[1]] else { encoder.endEncoding(); continue }
                        
                        // DEBUG MODE
                        if self.debugMode == .forceInput0 {
                             print("[Composite] Debug Mode: Force Input 0 (Background)")
                             // Just draw BG, skip FG
                             guard let videoPipeline = videoPipelineState else { encoder.endEncoding(); continue }
                             encoder.setRenderPipelineState(videoPipeline)
                             encoder.setFragmentTexture(texBG, index: 0)
                             var opacity: Float = 1.0
                             encoder.setFragmentBytes(&opacity, length: MemoryLayout<Float>.size, index: 0)
                             encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                             encoder.endEncoding()
                             continue
                        } else if self.debugMode == .forceInput1 {
                             print("[Composite] Debug Mode: Force Input 1 (Foreground)")
                             // Just draw FG (Opaque), skip BG
                             guard let videoPipeline = videoPipelineState else { encoder.endEncoding(); continue }
                             encoder.setRenderPipelineState(videoPipeline)
                             encoder.setFragmentTexture(texFG, index: 0)
                             var opacity: Float = 1.0
                             encoder.setFragmentBytes(&opacity, length: MemoryLayout<Float>.size, index: 0)
                             encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                             encoder.endEncoding()
                             continue
                        }
                        
                        // Pass 1: Draw BG
                        // We need a simple "Copy" pipeline. `videoPipelineState` does this?
                        // `videoPipelineState` uses `video_plane_fragment` which samples texture 0.
                        guard let videoPipeline = videoPipelineState else { encoder.endEncoding(); continue }
                        
                        encoder.setRenderPipelineState(videoPipeline)
                        encoder.setFragmentTexture(texBG, index: 0)
                        
                        var opacityBG: Float = 1.0
                        encoder.setFragmentBytes(&opacityBG, length: MemoryLayout<Float>.size, index: 0)
                        
                        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                        
                        // Pass 2: Draw FG (Additive)
                        // We need a pipeline with Additive Blending enabled.
                        // `addBlendPipelineState` has it enabled!
                        // And it uses `video_plane_fragment` now.
                        
                        guard let addPipeline = addBlendPipelineState else { encoder.endEncoding(); continue }
                        encoder.setRenderPipelineState(addPipeline)
                        
                        encoder.setFragmentTexture(texFG, index: 0) // Texture 0
                        
                        var opacityFG: Float = 1.0
                        encoder.setFragmentBytes(&opacityFG, length: MemoryLayout<Float>.size, index: 0)
                        
                        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                        encoder.endEncoding()
                        
                        // DIAGNOSTIC: Check Composite
                        // self.runCompositeMinMax(texture: outputTex)
                        
                        continue
                        
                    } else {
                        // Fallback to Dissolve (Normal) - Not fully implemented yet
                        // guard let pipeline = dissolvePipelineState else { encoder.endEncoding(); continue }
                        print("⚠️ Blend mode '\(mode)' not implemented")
                        encoder.endEncoding()
                        continue
                    }
                } else if shaderName == "split" {
                    guard let pipeline = splitScreenPipelineState else { encoder.endEncoding(); continue }
                    encoder.setRenderPipelineState(pipeline)
                    
                    var splitPos: Float = 0.5
                    if let v = params["splitPosition"], case .float(let f) = v { splitPos = Float(f) }
                    
                    struct SplitParams {
                        var splitPosition: Float
                        var angle: Float
                        var width: Float
                        var _pad: Float
                    }
                    var splitParams = SplitParams(splitPosition: splitPos, angle: 0, width: 0, _pad: 0)
                    encoder.setFragmentBytes(&splitParams, length: MemoryLayout<SplitParams>.stride, index: 0)
                    
                } else {
                    // Default / Mix Pipeline
                    guard let pipeline = processPipelineState else { encoder.endEncoding(); continue }
                    encoder.setRenderPipelineState(pipeline)
                    
                    if let mixVal = params["mix"], case .float(let mix) = mixVal {
                        var m = Float(mix)
                        encoder.setFragmentBytes(&m, length: MemoryLayout<Float>.size, index: 0)
                    } else {
                        var m: Float = 1.0
                        encoder.setFragmentBytes(&m, length: MemoryLayout<Float>.size, index: 0)
                    }
                }
                
                // 4. Bind Inputs
                for (index, inputId) in inputIds.enumerated() {
                    if let inputTex = nodeTextures[inputId] {
                        encoder.setFragmentTexture(inputTex, index: index)
                    }
                }
                
                // 5. Draw
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                encoder.endEncoding()
                
            case .present(let nodeId):
                if diagnosticsEnabled {
                    print("📺 [Present] Presenting Node: \(nodeId)")
                    if let tex = nodeTextures[nodeId] {
                        print("   Texture: \(tex.width)x\(tex.height) \(tex.pixelFormat)")
                        self.encodeCompositeMinMax(commandBuffer: commandBuffer, texture: tex, label: "FinalOutputBeforeODT")
                    } else {
                        print("❌ [Present] Texture for Node \(nodeId) NOT FOUND")
                    }
                }

                // Blit the final node texture to the outputTexture with ODT
                let renderPassDesc = MTLRenderPassDescriptor()
                renderPassDesc.colorAttachments[0].texture = outputTexture
                renderPassDesc.colorAttachments[0].loadAction = .clear
                renderPassDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
                renderPassDesc.colorAttachments[0].storeAction = .store
                
                guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else { continue }
                
                // Set Viewport
                let viewport = MTLViewport(originX: 0, originY: 0, width: Double(outputTexture.width), height: Double(outputTexture.height), znear: 0, zfar: 1)
                encoder.setViewport(viewport)
                
                // Bind Geometry
                encoder.setVertexBuffer(quadBuffer, offset: 0, index: 0)
                var identity = matrix_identity_float4x4
                encoder.setVertexBytes(&identity, length: MemoryLayout<matrix_float4x4>.stride, index: 1)
                
                // Use ODT Pipeline if available, otherwise fallback to video (pass-through)
                // Select pipeline based on output format
                var pipeline: MTLRenderPipelineState?
                
                if outputTexture.pixelFormat == .rgba16Float {
                    pipeline = odtPipelineFloatState ?? videoPipelineState
                } else {
                    pipeline = odtPipelineState ?? videoPipelineState
                }
                
                if pipeline == nil { print("⚠️ ODT Pipeline is NIL, falling back to Video") }
                
                guard let pso = pipeline else { 
                    print("❌ No Pipeline Available for Present")
                    encoder.endEncoding()
                    continue 
                }
                encoder.setRenderPipelineState(pso)
                
                if let finalTex = nodeTextures[nodeId] {
                    encoder.setFragmentTexture(finalTex, index: 0)
                }
                
                // Set Display Mode (0 = Rec.709 SDR)
                var displayMode: Int32 = 0
                encoder.setFragmentBytes(&displayMode, length: MemoryLayout<Int32>.size, index: 0)
                
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                encoder.endEncoding()
                
                if diagnosticsEnabled {
                    // DIAGNOSTIC: Check Output Texture
                    self.encodeCompositeMinMax(commandBuffer: commandBuffer, texture: outputTexture, label: "FinalVideoOutput")
                }
            }
        }

        await withCheckedContinuation { continuation in
            commandBuffer.addCompletedHandler { cb in
                if let error = cb.error {
                    print("❌ Command Buffer Error: \(error)")
                }
                continuation.resume()
            }
            commandBuffer.commit()
        }
        
        if diagnosticsEnabled {
            // Run Deferred Diagnostics
            for (tex, label) in debugTexturesToCheck {
                self.runCompositeMinMax(texture: tex, label: label)
            }
        }
    }
    
    // MARK: - Diagnostics
    
    private func runFITSMinMax(texture: MTLTexture, name: String) {
        guard let pipeline = fitsMinMaxPipeline,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        
        let bufferSize = 2 * MemoryLayout<UInt32>.stride
        guard let buffer = device.makeBuffer(length: bufferSize, options: .storageModeShared) else { return }
        
        let ptr = buffer.contents().bindMemory(to: UInt32.self, capacity: 2)
        ptr[0] = Float.greatestFiniteMagnitude.bitPattern
        ptr[1] = 0 
        
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        
        let w = pipeline.threadExecutionWidth
        let h = pipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
        let threadsPerGrid = MTLSize(width: texture.width, height: texture.height, depth: 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let minVal = Float(bitPattern: ptr[0])
        let maxVal = Float(bitPattern: ptr[1])
        
        print("[GPU] Texture Stats for \(name)")
        print("  Min: \(minVal)")
        print("  Max: \(maxVal)")
    }
    
    private func encodeCompositeMinMax(commandBuffer: MTLCommandBuffer, texture: MTLTexture, label: String = "Composite") {
        guard let pipeline = compositeMinMaxPipeline,
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        
        let bufferSize = 2 * MemoryLayout<UInt32>.stride
        guard let buffer = device.makeBuffer(length: bufferSize, options: .storageModeShared) else { return }
        
        let ptr = buffer.contents().bindMemory(to: UInt32.self, capacity: 2)
        ptr[0] = Float.greatestFiniteMagnitude.bitPattern
        ptr[1] = 0
        
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        
        let w = pipeline.threadExecutionWidth
        let h = pipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
        let threadsPerGrid = MTLSize(width: texture.width, height: texture.height, depth: 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
        commandBuffer.addCompletedHandler { _ in
            let minVal = Float(bitPattern: ptr[0])
            let maxVal = Float(bitPattern: ptr[1])
            
            print("[GPU] \(label) Stats (Async)")
            print("  Min: \(minVal)")
            print("  Max: \(maxVal)")
            
            if maxVal < 1e-6 {
                // print("❌ CRITICAL FAILURE: \(label) is effectively black (Max < 1e-6).")
            }
        }
    }

    private func runCompositeMinMax(texture: MTLTexture, label: String = "Composite") {
        guard let pipeline = compositeMinMaxPipeline,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        
        let bufferSize = 2 * MemoryLayout<UInt32>.stride
        guard let buffer = device.makeBuffer(length: bufferSize, options: .storageModeShared) else { return }
        
        let ptr = buffer.contents().bindMemory(to: UInt32.self, capacity: 2)
        ptr[0] = Float.greatestFiniteMagnitude.bitPattern
        ptr[1] = 0
        
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        
        let w = pipeline.threadExecutionWidth
        let h = pipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
        let threadsPerGrid = MTLSize(width: texture.width, height: texture.height, depth: 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let minVal = Float(bitPattern: ptr[0])
        let maxVal = Float(bitPattern: ptr[1])
        
        print("[GPU] \(label) Stats")
        print("  Min: \(minVal)")
        print("  Max: \(maxVal)")
    }

}
