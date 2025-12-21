import Foundation
import ArgumentParser
import Metal
import MetaVisRender
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@main
struct MetaVis: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "metavis",
        abstract: "AI-powered video text compositing engine",
        version: "3.0.0",
        subcommands: [
            Render.self,
            TestRender.self,
            Analyze.self,
            Ingest.self,
            Probe.self,
            Transcribe.self,
            Diagnose.self,
            // Sprint 03 additions
            DocumentProbeCmd.self,
            DocumentAnalyzeCmd.self,
            LookExtract.self,
            LUTAnalyze.self,
            ClipAnalyze.self,
            DraftManifestCommand.self,
            Captions.self,
            SearchCommand.self,
            // Sprint 14 additions
            GeminiCommand.self,
            ElevenLabsCommand.self,
            GenerateCommand.self,
            // Sprint D Week 2 additions
            AnalyzeVideo.self,
            // Sprint C Week 1 additions
            GenerateReferencesCommand.self,
            // Sprint 2: Color Pipeline Testing
            GenerateTestsCommand.self,
            ValidateColorCommand.self
        ],
        defaultSubcommand: Render.self
    )
}

// MARK: - Render Command

struct Render: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Render a timeline to video (supports legacy RenderManifest format)"
    )
    
    @Argument(help: "Path to the input manifest JSON file")
    var input: String

    @Option(name: .shortAndLong, help: "Path to the output video file")
    var output: String = "output.mov"

    @Option(name: .shortAndLong, help: "Width of the output video")
    var width: Int = 1920

    @Option(name: .shortAndLong, help: "Height of the output video")
    var height: Int = 1080

    @Option(name: .shortAndLong, help: "Frame rate of the output video")
    var fps: Double = 30.0

    @Option(name: .shortAndLong, help: "Duration of the video in seconds")
    var duration: Double = 5.0
    
    @Flag(name: .long, help: "Enable AI person segmentation for depth compositing")
    var aiSegment: Bool = false
    
    @Flag(name: .long, help: "Enable AI text auto-placement")
    var aiPlace: Bool = false
    
    @Flag(name: .long, help: "Enable all AI features")
    var aiAll: Bool = false

    mutating func run() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Error: Metal is not supported on this device.")
            throw ExitCode.failure
        }

        let inputURL = URL(fileURLWithPath: input)
        let outputURL = URL(fileURLWithPath: output)

        print("Reading manifest from \(inputURL.path)...")
        fflush(stdout)
        let data = try Data(contentsOf: inputURL)
        
        // Check for Node Graph Manifest
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["graph"] != nil {
            print("Detected Node Graph Manifest. Using GraphPipeline...")
            try await renderGraph(data: data, output: outputURL, device: device)
            return
        }
        
        print("Data loaded, converting...")
        fflush(stdout)
        // Auto-detect and convert legacy RenderManifest or load TimelineModel
        var timeline: TimelineModel
        do {
            timeline = try ManifestConverter.load(from: data)
        } catch {
            print("ERROR in ManifestConverter.load: \(error)")
            fflush(stdout)
            throw error
        }
        
        // Check if it was converted from legacy format
        if ManifestConverter.isLegacyManifest(data) {
            print("✓ Converted legacy RenderManifest to TimelineModel")
        }
        
        // Probe video sources and update timeline settings for optimum quality
        print("Probing video sources for optimum quality...")
        for (id, source) in timeline.sources {
            if !source.path.hasPrefix("pdf://") {
                let sourceURL = URL(fileURLWithPath: source.path)
                if FileManager.default.fileExists(atPath: sourceURL.path) {
                    do {
                        let probeResult = try await EnhancedMediaProbe.probe(sourceURL)
                        if let video = probeResult.video {
                            print("  Found video source: \(source.path)")
                            print("    Resolution: \(video.width)x\(video.height)")
                            print("    FPS: \(video.fps)")
                            print("    Codec: \(video.codec)")
                            
                            // Update timeline settings to match source
                            timeline.resolution = SIMD2(video.width, video.height)
                            timeline.fps = video.fps
                            
                            // Update source info in timeline
                            var updatedSource = source
                            updatedSource.resolution = SIMD2(video.width, video.height)
                            updatedSource.fps = video.fps
                            updatedSource.codec = video.codec.rawValue
                            
                            // Determine color space string
                            if video.colorSpace.transfer == .appleLog {
                                updatedSource.colorSpace = "applelog"
                            } else if video.colorSpace.transfer == .hlg {
                                updatedSource.colorSpace = "hlg"
                            } else if video.colorSpace.transfer == .pq {
                                updatedSource.colorSpace = "hdr10"
                            } else if video.colorSpace.transfer == .slog3 {
                                updatedSource.colorSpace = "slog3"
                            } else {
                                updatedSource.colorSpace = video.colorSpace.primaries.rawValue
                            }
                            
                            updatedSource.duration = probeResult.duration
                            timeline.sources[id] = updatedSource
                            
                            print("  ✓ Updated timeline settings to match source video")
                        }
                    } catch {
                        print("  ⚠️ Failed to probe source \(source.path): \(error)")
                    }
                } else {
                    print("  ⚠️ Source file not found: \(source.path)")
                }
            }
        }
        
        print("Timeline info:")
        print("  Duration: \(timeline.duration)s")
        print("  FPS: \(timeline.fps)")
        print("  Resolution: \(timeline.resolution.x)x\(timeline.resolution.y)")
        print("  Video tracks: \(timeline.videoTracks.count)")
        print("  Graphics tracks: \(timeline.graphicsTracks.count)")
        print("  Sources: \(timeline.sources.count)")
        
        // Create output directory
        let outputDir = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        // Create timeline exporter
        let exporter = try TimelineExporter(
            timeline: timeline,
            device: device,
            outputURL: outputURL
        )
        
        // Check for PDF sources and register them
        let hasPDFSources = timeline.sources.values.contains { $0.path.hasPrefix("pdf://") }
        if hasPDFSources {
            print("Detected PDF sources, registering page renderer...")
            let pageRenderer = PageRenderer(device: device)
            try await exporter.registerPDFSources(pageRenderer: pageRenderer)
            print("PDF sources registered")
        }
        
        // Export with progress
        print("Starting render...")
        let startTime = Date()
        
        try await exporter.export { progress in
            if progress.currentFrame % 30 == 0 || progress.currentFrame == progress.totalFrames - 1 {
                let percentage = String(format: "%.1f", progress.progress * 100)
                print("Progress: \(percentage)% (\(progress.currentFrame)/\(progress.totalFrames) frames)")
            }
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        print("\n✅ Render complete!")
        print("Output: \(outputURL.path)")
        print("Duration: \(timeline.duration)s at \(timeline.fps) FPS")
        print("Rendered in \(String(format: "%.2f", elapsed)) seconds")
    }
    
    private func renderGraph(data: Data, output: URL, device: MTLDevice) async throws {
        let decoder = JSONDecoder()
        let manifest = try decoder.decode(RenderManifest.self, from: data)
        
        let engine = RenderEngine(device: device)
        let config = VideoExportConfig(
            codec: .h264,
            bitrate: nil,
            quality: 1.0,
            keyframeInterval: nil,
            colorDepth: .bit8,
            bandingMitigation: .auto,
            maxFramesInFlight: 3
        )
        
        let exporter = try VideoExporter(
            outputURL: output,
            width: manifest.metadata.resolution.x,
            height: manifest.metadata.resolution.y,
            frameRate: Int(manifest.metadata.fps),
            config: config
        )
        
        let totalFrames = Int(manifest.metadata.duration * manifest.metadata.fps)
        
        // Setup Input Provider
        let inputProvider = SimpleVideoInputProvider(device: device)
        let videoPath = "/Users/kwilliams/Projects/metavis_render/keith_talk.mov"
        print("Checking for video file at: \(videoPath)")
        if FileManager.default.fileExists(atPath: videoPath) {
            print("Video file found. Loading asset...")
            try await inputProvider.loadAsset(id: "main_video", url: URL(fileURLWithPath: videoPath))
        } else {
            print("Warning: Video file not found at \(videoPath)")
        }
        
        print("Rendering \(totalFrames) frames via GraphPipeline...")
        
        for frame in 0..<totalFrames {
            let time = Double(frame) / manifest.metadata.fps
            let duration = 1.0 / manifest.metadata.fps
            
            // Create a texture for output
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float,
                width: manifest.metadata.resolution.x,
                height: manifest.metadata.resolution.y,
                mipmapped: false
            )
            desc.usage = [MTLTextureUsage.shaderRead, MTLTextureUsage.shaderWrite, MTLTextureUsage.renderTarget]
            guard let texture = device.makeTexture(descriptor: desc) else { continue }
            
            let job = RenderJob(
                manifest: manifest,
                timeRange: time..<(time + duration),
                resolution: SIMD2(manifest.metadata.resolution.x, manifest.metadata.resolution.y),
                fps: manifest.metadata.fps,
                output: .texture(texture)
            )
            
            try await engine.execute(job: job, inputProvider: inputProvider)
            
            try await exporter.append(texture: texture)
            
            if frame % 30 == 0 {
                print("Rendered frame \(frame)/\(totalFrames)")
            }
        }
        
        try await exporter.finish()
        print("Render complete: \(output.path)")
    }
}

// MARK: - Test Render Command (Scientific Debugging)

struct TestRender: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Render a single frame to PNG for debugging (bypasses video export)"
    )
    
    @Argument(help: "Path to the input manifest JSON file")
    var input: String
    
    @Option(name: .shortAndLong, help: "Path to the output PNG file")
    var output: String = "test_frame.png"
    
    @Option(name: .shortAndLong, help: "Frame number to render (default: 0)")
    var frame: Int = 0
    
    mutating func run() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("❌ Metal is not supported on this device.")
            throw ExitCode.failure
        }
        
        let inputURL = URL(fileURLWithPath: input)
        let outputPath = output
        
        print("🔬 SCIENTIFIC RENDER TEST")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("Input:  \(inputURL.path)")
        print("Output: \(outputPath)")
        print("Frame:  \(frame)")
        print("")
        
        // Load manifest
        print("📖 Loading manifest...")
        let data = try Data(contentsOf: inputURL)
        let timeline = try ManifestConverter.load(from: data)
        
        print("  Duration: \(timeline.duration)s")
        print("  FPS: \(timeline.fps)")
        print("  Resolution: \(timeline.resolution.x)x\(timeline.resolution.y)")
        print("")
        
        // Create dummy output URL (won't be written)
        let tempDir = FileManager.default.temporaryDirectory
        let dummyOutputURL = tempDir.appendingPathComponent("test_dummy.mov")
        
        // Create timeline exporter  
        print("🎬 Creating timeline exporter...")
        let exporter = try TimelineExporter(
            timeline: timeline,
            device: device,
            outputURL: dummyOutputURL
        )
        
        // Calculate time for requested frame
        let time = Double(frame) / timeline.fps
        print("  Rendering frame \(frame) at t=\(String(format: "%.3f", time))s")
        print("")
        
        // Render single frame using exporter's internal method
        print("🎨 Rendering frame...")
        let texture = try await exporter.renderSingleFrameForTest(at: time)
        
        print("  Texture format: \(texture.pixelFormat)")
        print("  Texture size: \(texture.width)x\(texture.height)")
        print("  Texture usage: \(texture.usage)")
        print("")
        
        // Export to PNG
        print("💾 Exporting to PNG...")
        let success = TextureUtils.textureToPNG(texture, path: outputPath)
        
        if success {
            // Check file size
            if let attributes = try? FileManager.default.attributesOfItem(atPath: outputPath),
               let fileSize = attributes[.size] as? UInt64 {
                let sizeMB = Double(fileSize) / (1024 * 1024)
                print("  File size: \(String(format: "%.2f", sizeMB)) MB (\(fileSize) bytes)")
            }
            
            print("")
            print("✅ TEST COMPLETE - Render pipeline validated!")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("Next step: Open \(outputPath) to verify visual output")
            print("If PNG shows valid render → bug is in VideoExporter")
            print("If PNG is black → bug is in render pipeline")
        } else {
            print("")
            print("❌ TEST FAILED - Could not export PNG")
            print("This suggests a texture reading issue")
            throw ExitCode.failure
        }
    }
}

// MARK: - Analyze Command

struct Analyze: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Analyze an image using AI vision features"
    )
    
    @Argument(help: "Path to the input image file")
    var input: String
    
    @Option(name: .shortAndLong, help: "Output path for analysis results")
    var output: String?
    
    @Flag(name: .long, help: "Run all analysis types")
    var all: Bool = false
    
    @Flag(name: .long, help: "Detect saliency regions")
    var saliency: Bool = false
    
    @Flag(name: .long, help: "Segment people in the image")
    var segment: Bool = false
    
    @Flag(name: .long, help: "Detect faces")
    var faces: Bool = false
    
    @Flag(name: .long, help: "Detect and recognize text")
    var text: Bool = false
    
    @Flag(name: .long, help: "Detect horizon angle")
    var horizon: Bool = false
    
    @Flag(name: .long, help: "Classify scene type")
    var scene: Bool = false
    
    @Flag(name: .long, help: "Find safe zones for text placement")
    var findZones: Bool = false
    
    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false
    
    mutating func run() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Error: Metal is not supported on this device.")
            throw ExitCode.failure
        }
        
        let inputURL = URL(fileURLWithPath: input)
        
        print("Loading image from \(inputURL.path)...")
        
        // Load image as texture
        guard let texture = try loadImageAsTexture(url: inputURL, device: device) else {
            print("Error: Could not load image as texture")
            throw ExitCode.failure
        }
        
        print("Image size: \(texture.width) x \(texture.height)")
        print("")
        
        // Determine what to analyze
        let runAll = all || (!saliency && !segment && !faces && !text && !horizon && !scene && !findZones)
        
        let visionProvider = VisionProvider(device: device)
        var results: [String: Any] = [
            "input": input,
            "width": texture.width,
            "height": texture.height
        ]
        
        // Saliency
        if runAll || saliency {
            print("Analyzing saliency...")
            do {
                let saliencyResult = try await visionProvider.detectSaliency(in: texture, mode: .attention)
                if json {
                    results["saliency"] = [
                        "regions": saliencyResult.regions.map { [
                            "bounds": ["x": $0.bounds.origin.x, "y": $0.bounds.origin.y, 
                                       "width": $0.bounds.width, "height": $0.bounds.height],
                            "confidence": $0.confidence
                        ]}
                    ]
                } else {
                    print("  Saliency regions: \(saliencyResult.regions.count)")
                    for (i, region) in saliencyResult.regions.enumerated() {
                        print("    [\(i)] bounds: \(formatRect(region.bounds)), confidence: \(String(format: "%.2f", region.confidence))")
                    }
                }
            } catch {
                print("  Error: \(error.localizedDescription)")
            }
        }
        
        // Segmentation
        if runAll || segment {
            print("Segmenting people...")
            if #available(macOS 12.0, *) {
                do {
                    let segmentResult = try await visionProvider.segmentPeople(in: texture, quality: .balanced)
                    if json {
                        results["segmentation"] = [
                            "bounds": ["x": segmentResult.bounds.origin.x, "y": segmentResult.bounds.origin.y,
                                       "width": segmentResult.bounds.width, "height": segmentResult.bounds.height],
                            "labels": segmentResult.labels.map { $0.rawValue }
                        ]
                    } else {
                        print("  Person detected: \(segmentResult.bounds != .zero)")
                        if segmentResult.bounds != .zero {
                            print("  Bounds: \(formatRect(segmentResult.bounds))")
                        }
                    }
                } catch {
                    print("  Error: \(error.localizedDescription)")
                }
            } else {
                print("  Requires macOS 12.0+")
            }
        }
        
        // Faces
        if runAll || faces {
            print("Detecting faces...")
            do {
                let facesResult = try await visionProvider.detectFaces(in: texture, landmarks: true)
                if json {
                    results["faces"] = facesResult.map { [
                        "bounds": ["x": $0.bounds.origin.x, "y": $0.bounds.origin.y,
                                   "width": $0.bounds.width, "height": $0.bounds.height],
                        "confidence": $0.confidence,
                        "roll": $0.roll as Any,
                        "yaw": $0.yaw as Any,
                        "pitch": $0.pitch as Any
                    ]}
                } else {
                    print("  Faces found: \(facesResult.count)")
                    for (i, face) in facesResult.enumerated() {
                        print("    [\(i)] bounds: \(formatRect(face.bounds)), confidence: \(String(format: "%.2f", face.confidence))")
                        if let yaw = face.yaw {
                            print("        yaw: \(String(format: "%.1f°", yaw * 180 / .pi))")
                        }
                    }
                }
            } catch {
                print("  Error: \(error.localizedDescription)")
            }
        }
        
        // Text detection
        if runAll || text {
            print("Detecting text...")
            do {
                let textResult = try await visionProvider.detectText(in: texture, recognizeText: true)
                if json {
                    results["text"] = textResult.map { [
                        "bounds": ["x": $0.bounds.origin.x, "y": $0.bounds.origin.y,
                                   "width": $0.bounds.width, "height": $0.bounds.height],
                        "text": $0.text as Any,
                        "confidence": $0.confidence
                    ]}
                } else {
                    print("  Text regions found: \(textResult.count)")
                    for (i, textObs) in textResult.enumerated() {
                        let recognized = textObs.text ?? "(not recognized)"
                        print("    [\(i)] \"\(recognized)\" - confidence: \(String(format: "%.2f", textObs.confidence))")
                    }
                }
            } catch {
                print("  Error: \(error.localizedDescription)")
            }
        }
        
        // Horizon
        if runAll || horizon {
            print("Detecting horizon...")
            do {
                if let horizonResult = try await visionProvider.detectHorizon(in: texture) {
                    let degrees = horizonResult.angle * 180 / .pi
                    if json {
                        results["horizon"] = [
                            "angle": horizonResult.angle,
                            "degrees": degrees
                        ]
                    } else {
                        print("  Horizon angle: \(String(format: "%.2f°", degrees))")
                    }
                } else {
                    print("  No horizon detected")
                }
            } catch {
                print("  Error: \(error.localizedDescription)")
            }
        }
        
        // Scene classification
        if runAll || scene {
            print("Classifying scene...")
            do {
                let sceneResult = try await visionProvider.analyzeScene(texture)
                if json {
                    results["scene"] = [
                        "type": sceneResult.sceneType.rawValue,
                        "tags": sceneResult.tags,
                        "confidence": sceneResult.confidence
                    ]
                } else {
                    print("  Scene type: \(sceneResult.sceneType.rawValue)")
                    print("  Tags: \(sceneResult.tags.joined(separator: ", "))")
                    print("  Confidence: \(String(format: "%.2f", sceneResult.confidence))")
                }
            } catch {
                print("  Error: \(error.localizedDescription)")
            }
        }
        
        // Find zones
        if runAll || findZones {
            print("Finding safe text zones...")
            do {
                let saliencyResult = try await visionProvider.detectSaliency(in: texture, mode: .attention)
                let facesResult = try await visionProvider.detectFaces(in: texture, landmarks: false)
                
                let zones = findSafeZones(
                    saliencyRegions: saliencyResult.regions.map { $0.bounds },
                    faceRegions: facesResult.map { $0.bounds }
                )
                
                if json {
                    results["safeZones"] = zones.map { [
                        "x": $0.origin.x, "y": $0.origin.y,
                        "width": $0.width, "height": $0.height
                    ]}
                } else {
                    print("  Safe zones found: \(zones.count)")
                    for (i, zone) in zones.enumerated() {
                        print("    [\(i)] \(formatRect(zone))")
                    }
                }
            } catch {
                print("  Error: \(error.localizedDescription)")
            }
        }
        
        // Output JSON if requested
        if json {
            if let jsonData = try? JSONSerialization.data(withJSONObject: results, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                if let outputPath = output {
                    try jsonString.write(toFile: outputPath, atomically: true, encoding: .utf8)
                    print("\nResults written to \(outputPath)")
                } else {
                    print("\n\(jsonString)")
                }
            }
        }
        
        print("\nAnalysis complete!")
    }
    
    private func loadImageAsTexture(url: URL, device: MTLDevice) throws -> MTLTexture? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        
        let width = cgImage.width
        let height = cgImage.height
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: width, height: height, depth: 1)
        )
        
        texture.replace(region: region, mipmapLevel: 0, withBytes: pixelData, bytesPerRow: bytesPerRow)
        
        return texture
    }
    
    private func formatRect(_ rect: CGRect) -> String {
        return String(format: "(%.2f, %.2f, %.2f x %.2f)", 
                      rect.origin.x, rect.origin.y, rect.width, rect.height)
    }
    
    private func findSafeZones(saliencyRegions: [CGRect], faceRegions: [CGRect]) -> [CGRect] {
        // Candidate zones for text
        let zones: [CGRect] = [
            CGRect(x: 0.05, y: 0.70, width: 0.4, height: 0.25),  // Lower left
            CGRect(x: 0.55, y: 0.70, width: 0.4, height: 0.25), // Lower right
            CGRect(x: 0.05, y: 0.05, width: 0.4, height: 0.15), // Upper left
            CGRect(x: 0.55, y: 0.05, width: 0.4, height: 0.15), // Upper right
            CGRect(x: 0.02, y: 0.35, width: 0.2, height: 0.3),  // Left side
            CGRect(x: 0.78, y: 0.35, width: 0.2, height: 0.3)   // Right side
        ]
        
        let subjectRegions = saliencyRegions + faceRegions
        
        return zones.filter { zone in
            for subject in subjectRegions {
                if zone.intersects(subject) {
                    let intersection = zone.intersection(subject)
                    let overlapRatio = (intersection.width * intersection.height) / (zone.width * zone.height)
                    if overlapRatio > 0.3 {
                        return false
                    }
                }
            }
            return true
        }
    }
}
