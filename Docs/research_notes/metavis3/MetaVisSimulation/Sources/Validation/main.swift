@preconcurrency import Foundation
// @preconcurrency import MetaVisKit
@preconcurrency import MetaVisTimeline
@preconcurrency import MetaVisCore
@preconcurrency import MetaVisSimulation
@preconcurrency import MetaVisExport
@preconcurrency import Metal
@preconcurrency import AVFoundation
@preconcurrency import CoreVideo

@main
struct ValidationMain {
    static func main() async {
        print("✨ Starting JWST Composite Generation (via Validation)...")
        
        let output = "./renders/jwst_composite.mov"
        let outputURL = URL(fileURLWithPath: output)
        let outputDirectory = outputURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        
        // 1. Setup Engine
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("❌ Metal device not available.")
            return
        }
        
        let clock = MasterClock()
        let engine = try! SimulationEngine(clock: clock)
        
        // Enable Data Debug Mode
        engine.idtDebugMode = .off
        
        // 2. Define Assets & Colors
        // F770W (Blue), F1130W (Green), F1280W (Orange), F1800W (Red)
        let assetsDir = URL(fileURLWithPath: "/Users/kwilliams/Projects/metavis_render_two/assets")
        
        struct LayerConfig {
            let filename: String
            let color: SIMD3<Float> // RGB
            let blackPoint: Float
            let whitePoint: Float
        }
        
        // Adjusted White Points based on data stats (P50 background, P99 highlights)
        let layers = [
            LayerConfig(filename: "hlsp_jwst-ero_jwst_miri_carina_f770w_v1_i2d.fits", color: SIMD3<Float>(0.0, 0.0, 1.0), blackPoint: 40.0, whitePoint: 300.0), // Blue
            LayerConfig(filename: "hlsp_jwst-ero_jwst_miri_carina_f1130w_v1_i2d.fits", color: SIMD3<Float>(0.0, 1.0, 0.0), blackPoint: 40.0, whitePoint: 300.0), // Green
            LayerConfig(filename: "hlsp_jwst-ero_jwst_miri_carina_f1280w_v1_i2d.fits", color: SIMD3<Float>(1.0, 0.5, 0.0), blackPoint: 60.0, whitePoint: 300.0), // Orange
            LayerConfig(filename: "hlsp_jwst-ero_jwst_miri_carina_f1800w_v1_i2d.fits", color: SIMD3<Float>(1.0, 0.0, 0.0), blackPoint: 180.0, whitePoint: 400.0) // Red
        ]
        
        var clipIds: [UUID] = []
        
        // Register Assets
        for layer in layers {
            let url = assetsDir.appendingPathComponent(layer.filename)
            if FileManager.default.fileExists(atPath: url.path) {
                let id = UUID()
                let asset = Asset(
                    id: id,
                    name: layer.filename,
                    status: .ready,
                    url: url,
                    representations: [
                        AssetRepresentation(type: .original, url: url, resolution: SIMD2(1920, 1080)) // Assuming resolution
                    ],
                    type: .fits,
                    duration: .zero
                )
                engine.assetManager.register(asset: asset)
                clipIds.append(id)
                print("   ✅ Registered Layer: \(layer.filename)")
            } else {
                print("   ⚠️ Missing Layer: \(layer.filename)")
                return
            }
        }
        
        // 3. Build Timeline (Vertical Stacking)
        print("   Building Composite Timeline...")
        var timeline = Timeline(name: "JWST Composite")
        let duration = 5.0 // 5 seconds
        
        for (index, id) in clipIds.enumerated() {
            var track = Track(name: "Layer \(index)", type: .video)
            let clip = Clip(
                name: "Clip \(index)",
                assetId: id,
                range: TimeRange(
                    start: .zero,
                    duration: RationalTime(value: Int64(duration), timescale: 1)
                ),
                sourceStartTime: .zero
            )
            try! track.add(clip)
            timeline.addTrack(track)
        }
        
        // 4. Setup Export
        let width = 1920
        let height = 1080
        
        let muxerConfig = MuxerConfiguration(
            outputURL: outputURL,
            videoSettings: VideoEncodingSettings(codec: .h264, bitrate: 50_000_000, profile: nil), // High bitrate
            resolution: ExportResolution(width: width, height: height),
            frameRate: 30.0,
            audioSettings: nil
        )
        let muxer = try! Muxer(configuration: muxerConfig)
        try! await muxer.start()
        
        let converter = try! ZeroCopyConverter(device: device)
        guard let pool = converter.createPixelBufferPool(width: width, height: height) else {
            print("❌ Failed to create pixel buffer pool")
            return
        }
        
        // 5. Render Loop
        let fps = 30.0
        let totalFrames = 150 // 5 seconds at 30fps
        let outputDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        outputDesc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        
        let compiler = GraphCompiler(device: device)
        
        print("   Rendering \(totalFrames) frames...")
        
        for frame in 0..<totalFrames {
            let time = CMTime(value: Int64(frame), timescale: Int32(fps))
            
            await clock.seek(to: time)
            
            // Build Graph Manually for maximum control
            var graph = NodeGraph(name: "Composite Frame \(frame)")
            
            // 1. Create Source Nodes
            var previousOutputNodeID: UUID? = nil
            
            for (index, layer) in layers.enumerated() {
                let assetId = clipIds[index]
                
                let sourceNode = Node(
                    name: "Layer \(index) (\(layer.filename))",
                    type: NodeType.fitsSource,
                    properties: [
                        "assetId": .string(assetId.uuidString),
                        "sourceStart": .float(0.0),
                        "duration": .float(Double(duration)),
                        "color": .color(SIMD4<Float>(layer.color, 1.0)),
                        "blackPoint": .float(Double(layer.blackPoint)),
                        "whitePoint": .float(Double(layer.whitePoint))
                    ],
                    outputs: [NodePort(id: "output", name: "Output", type: .image)]
                )
                graph.add(node: sourceNode)
                
                if let prevID = previousOutputNodeID {
                    // Blend with previous
                    let blendNode = Node(
                        name: "Blend \(index)",
                        type: "com.metavis.effect.blend",
                        properties: ["mode": .string("add")],
                        inputs: [
                            NodePort(id: "background", name: "Background", type: .image),
                            NodePort(id: "foreground", name: "Foreground", type: .image)
                        ],
                        outputs: [NodePort(id: "output", name: "Output", type: .image)]
                    )
                    graph.add(node: blendNode)
                    
                    // Connect
                    try! graph.connect(fromNode: prevID, fromPort: "output", toNode: blendNode.id, toPort: "background")
                    try! graph.connect(fromNode: sourceNode.id, fromPort: "output", toNode: blendNode.id, toPort: "foreground")
                    
                    previousOutputNodeID = blendNode.id
                } else {
                    // First layer is the base
                    previousOutputNodeID = sourceNode.id
                }
            }
            
            // Post-Process Node (Cinematic Look)
            if let finalID = previousOutputNodeID {
                let postNode = Node(
                    name: "Cinematic Grading",
                    type: NodeType.Effect.postProcess,
                    properties: [
                        "tonemapOperator": .float(1.0), // ACES Approx
                        "exposure": .float(2.0),        // Boost exposure
                        "saturation": .float(1.2),
                        "contrast": .float(1.0),        // Neutral contrast to avoid crushing blacks
                        "vignetteIntensity": .float(0.3),
                        "odt": .float(1.0) // sRGB Output
                    ],
                    inputs: [NodePort(id: "input", name: "Input", type: .image)],
                    outputs: [NodePort(id: "output", name: "Output", type: .image)]
                )
                graph.add(node: postNode)
                try! graph.connect(fromNode: finalID, fromPort: "output", toNode: postNode.id, toPort: "input")
                previousOutputNodeID = postNode.id
            }
            
            // Output Node
            let outputNode = Node(
                name: "Output",
                type: NodeType.output,
                inputs: [NodePort(id: "input", name: "Input", type: .image)]
            )
            graph.add(node: outputNode)
            
            if let finalID = previousOutputNodeID {
                try! graph.connect(fromNode: finalID, fromPort: "output", toNode: outputNode.id, toPort: "input")
            }
            
            // Compile
            let pass = try! compiler.compile(graph: graph)
            
            // Pre-load assets (Original)
            for command in pass.commands {
                if case .loadFITS(_, let assetId, _, _, _, _) = command {
                    print("   [Validation] Loading FITS asset: \(assetId)")
                    engine.loadAsset(assetId: assetId, quality: .original)
                }
            }
            
            // Render
            guard let texture = device.makeTexture(descriptor: outputDesc) else { continue }
            texture.label = "ValidationOutputTexture"
            
            // DIAGNOSTIC: Log Validation Texture
            print("[Validation] Using output texture:")
            print("  Pointer: \(Unmanaged.passUnretained(texture).toOpaque())")
            print("  Label: \(texture.label ?? "nil")")
            print("  Size: \(texture.width)x\(texture.height)")
            print("  PixelFormat: \(texture.pixelFormat.rawValue)")
            
            try! await engine.render(pass: pass, outputTexture: texture)
            
            // DIAGNOSTIC: Check Final Frame Output
            // We can use the engine's diagnostic tool if we expose it, or just assume if it's black here it's real.
            // Since we made render() wait for completion, we can check it now.
            // But we don't have easy access to the engine's private diagnostic methods.
            // Let's just trust the visual output or add a quick check here if needed.
            
            // Convert & Save
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            
            if let pb = pixelBuffer {
                try! await converter.convert(sourceTexture: texture, to: pb)
                // Wrap in SendablePixelBuffer to avoid data race warning
                let sendablePB = SendablePixelBuffer(pb)
                try! await muxer.appendVideo(pixelBuffer: sendablePB, presentationTime: time)
            }
            
            if frame % 10 == 0 {
                print("   Rendering frame \(frame)/\(totalFrames)")
            }
        }
        
        try! await muxer.finish()
        print("✅ Composite Generation Complete: \(outputURL.path)")
    }
}
