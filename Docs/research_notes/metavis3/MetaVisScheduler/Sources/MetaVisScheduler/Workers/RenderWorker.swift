import Foundation
import MetaVisImageGen
import Metal
import CoreImage
import MetaVisSimulation
import MetaVisTimeline
import MetaVisExport
import MetaVisCore
import AVFoundation

public struct AssetInfo: Codable, Sendable {
    public let id: UUID
    public let name: String
    public let url: URL
    public let type: MediaType
    
    public init(id: UUID, name: String, url: URL, type: MediaType) {
        self.id = id
        self.name = name
        self.url = url
        self.type = type
    }
}

public struct StarData: Codable, Sendable {
    public let u: Float
    public let v: Float
    public let mag: Float
    public let r: Float
    public let g: Float
    public let b: Float
    
    public init(u: Float, v: Float, mag: Float, r: Float, g: Float, b: Float) {
        self.u = u
        self.v = v
        self.mag = mag
        self.r = r
        self.g = g
        self.b = b
    }
}

public struct ConfigData: Codable, Sendable {
    // Must match `ConfigData` layout in `MetaVisSimulation/.../Resources/Shaders/Effects/Composite.metal`.
    public let exposure: Float
    public let saturation: Float
    public let contrast: Float
    public let lift: Float
    public let gamma: Float
    public let gain: Float

    public init(exposure: Float = 1.0, saturation: Float = 1.0, contrast: Float = 1.0, lift: Float = 0.0, gamma: Float = 1.0, gain: Float = 1.0) {
        self.exposure = exposure
        self.saturation = saturation
        self.contrast = contrast
        self.lift = lift
        self.gamma = gamma
        self.gain = gain
    }
}

public struct RenderJobPayload: Codable, Sendable {
    // Legacy LIGM support
    public let request: LIGMRequest?
    public let outputPath: String
    
    // New Timeline support
    public let timeline: Timeline?
    public let width: Int?
    public let height: Int?
    public let assets: [AssetInfo]?
    
    // v46 Data
    public let stars: [StarData]?
    public let config: ConfigData?
    
    public init(request: LIGMRequest, outputPath: String) {
        self.request = request
        self.outputPath = outputPath
        self.timeline = nil
        self.width = nil
        self.height = nil
        self.assets = nil
        self.stars = nil
        self.config = nil
    }
    
    public init(timeline: Timeline, outputPath: String, width: Int, height: Int, assets: [AssetInfo], stars: [StarData]? = nil, config: ConfigData? = nil) {
        self.request = nil
        self.outputPath = outputPath
        self.timeline = timeline
        self.width = width
        self.height = height
        self.assets = assets
        self.stars = stars
        self.config = config
    }
}

public struct RenderWorker: Worker {
    public let jobType: JobType = .render
    
    public init() {}
    
    public func execute(job: Job, progress: @escaping @Sendable (JobProgress) -> Void) async throws -> Data? {
        print("🎨 RenderWorker: Starting Job \(job.id)")
        
        let payload = try JSONDecoder().decode(RenderJobPayload.self, from: job.payload)
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw NSError(domain: "RenderWorker", code: 1, userInfo: [NSLocalizedDescriptionKey: "Metal device not available"])
        }
        
        if let timeline = payload.timeline, let width = payload.width, let height = payload.height {
            return try await renderTimeline(timeline, to: payload.outputPath, width: width, height: height, device: device, assets: payload.assets, stars: payload.stars, config: payload.config, jobId: job.id, progress: progress)
        } else if let request = payload.request {
            return try await renderLIGM(request, to: payload.outputPath, device: device)
        } else {
            throw NSError(domain: "RenderWorker", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid payload"])
        }
    }
    
    private func renderTimeline(_ timeline: Timeline, to path: String, width: Int, height: Int, device: MTLDevice, assets: [AssetInfo]?, stars: [StarData]?, config: ConfigData?, jobId: UUID, progress: @escaping (JobProgress) -> Void) async throws -> Data? {
        print("   🎬 Rendering Timeline: \(timeline.name)")

        let profilingEnabled = ProcessInfo.processInfo.environment["METAVIS_PROFILE_RENDER"] == "1"
        let diagnosticsEnabled = ProcessInfo.processInfo.environment["METAVIS_DIAGNOSTICS"] == "1"
        let jobStart = CFAbsoluteTimeGetCurrent()
        progress(JobProgress(jobId: jobId, progress: 0.0, message: "Initializing Engine...", step: "Setup"))
        
        // 1. Setup Engine & Orchestrator
        let clock = MasterClock()
        let engine = try SimulationEngine(clock: clock)
        engine.diagnosticsEnabled = diagnosticsEnabled

        if profilingEnabled {
            let t = CFAbsoluteTimeGetCurrent() - jobStart
            print(String(format: "   ⏱️  Setup (engine init) %.3fs", t))
        }
        
        // Set Auxiliary Buffers
        // NOTE: `jwst_composite_v4` currently reads a fixed 64-star table.
        if let starData = stars {
            var fixedStars = Array(repeating: StarData(u: 0, v: 0, mag: 0, r: 0, g: 0, b: 0), count: 64)
            let count = min(starData.count, fixedStars.count)
            if count > 0 {
                fixedStars.replaceSubrange(0..<count, with: starData.prefix(count))
            }
            let bufferSize = fixedStars.count * MemoryLayout<StarData>.stride
            if let buffer = device.makeBuffer(bytes: fixedStars, length: bufferSize, options: .storageModeShared) {
                engine.starBuffer = buffer
                print("   ✨ Bound Star Buffer with \(count)/64 stars")
            }
        }

        if let configData = config {
            var cfg = configData
            if let buffer = device.makeBuffer(bytes: &cfg, length: MemoryLayout<ConfigData>.stride, options: .storageModeShared) {
                engine.configBuffer = buffer
                print("   ⚙️ Bound Config Buffer (exposure=\(cfg.exposure), gamma=\(cfg.gamma))")
            }
        }
        
        // Ensure we are using real data, not debug/sanity modes
        engine.idtDebugMode = .off
        
        // Register Assets
        if let assets = assets {
            for info in assets {
                let asset = Asset(
                    id: info.id,
                    name: info.name,
                    status: .ready,
                    url: info.url,
                    representations: [
                        AssetRepresentation(type: .original, url: info.url, resolution: SIMD2(width, height))
                    ],
                    type: info.type,
                    duration: .zero
                )
                engine.assetManager.register(asset: asset)
            }
        }
        
        let orchestrator = SimulationOrchestrator(engine: engine)
        let session = MetaVisSession(timeline: timeline)
        orchestrator.session = session
        
        // Check for Composite Mode
        if timeline.name.contains("Composite") {
            print("   ✨ Enabling Composite Stack Mode")
            orchestrator.graphBuilder.mode = .stack
        }
        
        // 2. Setup Export Pipeline (ZeroCopy + Muxer)
        let outputURL = URL(fileURLWithPath: path)
        print("   🔧 Configuring Export Pipeline...")
        
        // Use Broadcast 4K Preset (ProRes 422 HQ) for highest quality intermediate
        // Or YouTube 4K (HEVC) for delivery.
        // Given the feedback about "Bit Rot" and the 10-bit pipeline, HEVC is the right choice.
        // Let's use a custom HEVC preset that matches our 10-bit pipeline.
        
        let videoSettings = VideoEncodingSettings(
            codec: .hevc, // HEVC Main10 profile is automatic with 10-bit buffers
            bitrate: 50_000_000, // 50 Mbps for high quality
            keyframeInterval: 1.0, // Frequent keyframes for scrubbing
            profile: nil // Let VideoToolbox decide (usually Main10)
        )
        
        // Check for Audio
        let hasAudio = timeline.tracks.contains(where: { $0.type == .audio })
        var audioSettings: AudioEncodingSettings? = nil
        
        if hasAudio {
            print("   🔊 Audio Track Detected")
            audioSettings = AudioEncodingSettings(
                codec: .aac,
                sampleRate: 48000,
                channelCount: 2,
                bitrate: 320000
            )
        }
        
        // Muxer Config
        let muxerConfig = MuxerConfiguration(
            outputURL: outputURL,
            videoSettings: videoSettings,
            resolution: ExportResolution(width: width, height: height),
            frameRate: 30.0,
            audioSettings: audioSettings
        )
        
        print("   🎥 Initializing Muxer...")
        let muxer = try Muxer(configuration: muxerConfig)
        try await muxer.start()

        if profilingEnabled {
            let t = CFAbsoluteTimeGetCurrent() - jobStart
            print(String(format: "   ⏱️  Setup (muxer start) %.3fs", t))
        }
        
        // Start Audio Processing in Background
        if hasAudio {
            Task {
                do {
                    try await processAudio(timeline: timeline, muxer: muxer, assets: assets, jobId: jobId, progress: progress)
                } catch {
                    print("   ❌ Audio Processing Failed: \(error)")
                    progress(JobProgress(jobId: jobId, progress: 0.0, message: "Audio Failed: \(error.localizedDescription)", step: "Audio"))
                }
            }
        }
        
        // ZeroCopy Converter
        print("   ⚡ Initializing ZeroCopyConverter...")
        let converter = try ZeroCopyConverter(device: engine.device as! MTLDevice)
        guard let pool = converter.createPixelBufferPool(width: width, height: height) else {
             throw NSError(domain: "RenderWorker", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create pixel buffer pool"])
        }

        if profilingEnabled {
            let t = CFAbsoluteTimeGetCurrent() - jobStart
            print(String(format: "   ⏱️  Setup (zerocopy pool) %.3fs", t))
        }
        
        // 3. Render Loop
        let duration = timeline.duration.seconds
        let fps = 30.0
        let totalFrames = Int(duration * fps)
        
        // Output Texture
        let outputDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        outputDesc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        
        print("   Rendering \(totalFrames) frames...")
        progress(JobProgress(jobId: jobId, progress: 0.0, message: "Starting Render...", step: "Rendering"))

        var totalRenderSeconds: Double = 0
        var totalConvertSeconds: Double = 0
        var totalEncodeSeconds: Double = 0
        let frameLogInterval = 30
        
        for frame in 0..<totalFrames {
            let time = CMTime(value: Int64(frame), timescale: Int32(fps))
            
            // Update Clock
            await clock.seek(to: time)
            
            // Create Texture
            guard let texture = (engine.device as! MTLDevice).makeTexture(descriptor: outputDesc) else { continue }
            
            // Render
            let renderStart = profilingEnabled ? CFAbsoluteTimeGetCurrent() : 0
            try await orchestrator.render(to: texture)
            if profilingEnabled {
                totalRenderSeconds += (CFAbsoluteTimeGetCurrent() - renderStart)
            }
            
            // Convert (ZeroCopy)
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            
            if let pb = pixelBuffer {
                let convertStart = profilingEnabled ? CFAbsoluteTimeGetCurrent() : 0
                try await converter.convert(sourceTexture: texture, to: pb)
                if profilingEnabled {
                    totalConvertSeconds += (CFAbsoluteTimeGetCurrent() - convertStart)
                }
                
                // Append to Muxer
                let encodeStart = profilingEnabled ? CFAbsoluteTimeGetCurrent() : 0
                try await muxer.appendVideo(pixelBuffer: pb, presentationTime: time)
                if profilingEnabled {
                    totalEncodeSeconds += (CFAbsoluteTimeGetCurrent() - encodeStart)
                }
            }

            if profilingEnabled && frame > 0 && (frame % frameLogInterval == 0) {
                let framesDone = Double(frame)
                let avgRenderMs = (totalRenderSeconds / framesDone) * 1000.0
                let avgConvertMs = (totalConvertSeconds / framesDone) * 1000.0
                let avgEncodeMs = (totalEncodeSeconds / framesDone) * 1000.0
                print(String(format: "   ⏱️  Avg/frame @%d: render %.1fms, convert %.1fms, encode+append %.1fms", frame, avgRenderMs, avgConvertMs, avgEncodeMs))
            }
            
            if frame % 10 == 0 {
                let pct = Double(frame) / Double(totalFrames)
                progress(JobProgress(jobId: jobId, progress: pct, message: "Rendering frame \(frame)/\(totalFrames)", step: "Rendering"))
            }
        }
        
        progress(JobProgress(jobId: jobId, progress: 1.0, message: "Finalizing...", step: "Finishing"))
        try await muxer.finish()

        if profilingEnabled {
            let total = CFAbsoluteTimeGetCurrent() - jobStart
            let frames = max(1.0, Double(totalFrames))
            print(String(format: "   ⏱️  Totals: %.3fs (%.1fms/frame)", total, (total / frames) * 1000.0))
            print(String(format: "   ⏱️  Breakdown/frame: render %.1fms, convert %.1fms, encode+append %.1fms", (totalRenderSeconds / frames) * 1000.0, (totalConvertSeconds / frames) * 1000.0, (totalEncodeSeconds / frames) * 1000.0))
        }
        print("   ✅ Render Complete: \(path)")
        return nil
    }
    
    private func processAudio(timeline: Timeline, muxer: Muxer, assets: [AssetInfo]?, jobId: UUID, progress: @escaping (JobProgress) -> Void) async throws {
        guard let audioTrack = timeline.tracks.first(where: { $0.type == .audio }) else { return }
        
        print("   🔊 Processing Audio Track...")
        progress(JobProgress(jobId: jobId, progress: 0.0, message: "Starting Audio Extraction...", step: "Audio"))
        
        var totalClips = audioTrack.clips.count
        var processedClips = 0
        
        for clip in audioTrack.clips {
            print("   🔊 Processing Clip: \(clip.name)")
            progress(JobProgress(jobId: jobId, progress: Double(processedClips) / Double(totalClips), message: "Processing \(clip.name)", step: "Audio"))
            
            guard let assetInfo = assets?.first(where: { $0.id == clip.assetId }) else { 
                print("   ⚠️ Audio asset not found for clip: \(clip.name)")
                continue 
            }
            
            let asset = AVAsset(url: assetInfo.url)
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard let track = tracks.first else { 
                print("   ⚠️ No audio track in asset: \(assetInfo.name)")
                continue 
            }
            
            let reader = try AVAssetReader(asset: asset)
            
            // Decompress to PCM so we can re-encode or mix
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: audioSettings) 
            reader.add(output)
            
            if !reader.startReading() {
                print("   ❌ Failed to start reading audio: \(String(describing: reader.error))")
                continue
            }
            
            // Calculate offset
            let clipStartSeconds = clip.range.start.seconds
            let clipStart = CMTime(seconds: clipStartSeconds, preferredTimescale: 600)
            
            var sampleCount = 0
            while let sampleBuffer = output.copyNextSampleBuffer() {
                sampleCount += 1
                var timingInfo = CMSampleTimingInfo()
                if CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timingInfo) == 0 {
                    // Adjust presentation time
                    timingInfo.presentationTimeStamp = CMTimeAdd(timingInfo.presentationTimeStamp, clipStart)
                    
                    // Create new sample buffer
                    var newSampleBuffer: CMSampleBuffer?
                    CMSampleBufferCreateCopyWithNewTiming(
                        allocator: kCFAllocatorDefault,
                        sampleBuffer: sampleBuffer,
                        sampleTimingEntryCount: 1,
                        sampleTimingArray: &timingInfo,
                        sampleBufferOut: &newSampleBuffer
                    )
                    
                    if let newBuf = newSampleBuffer {
                        try await muxer.appendAudio(sampleBuffer: newBuf)
                    }
                }
            }
            print("   ✅ Processed Audio Clip: \(clip.name) (\(sampleCount) samples)")
            processedClips += 1
            progress(JobProgress(jobId: jobId, progress: Double(processedClips) / Double(totalClips), message: "Finished \(clip.name)", step: "Audio"))
        }
        progress(JobProgress(jobId: jobId, progress: 1.0, message: "Audio Complete", step: "Audio"))
    }
    
    private func renderLIGM(_ request: LIGMRequest, to path: String, device: MTLDevice) async throws -> Data? {
        let ligm = LIGM(device: device)
        print("   Generating texture...")
        let response = try await ligm.generate(request: request)
        print("   Saving to \(path)...")
        try saveTexture(response.texture, to: path)
        return nil
    }
    
    private func saveTexture(_ texture: MTLTexture, to path: String) throws {
        guard let ciImage = CIImage(mtlTexture: texture, options: [.colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!]) else {
            throw NSError(domain: "RenderWorker", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create CIImage from texture"])
        }
        let flipped = ciImage.transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -CGFloat(texture.height)))
        let context = CIContext()
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        try context.writePNGRepresentation(of: flipped, to: URL(fileURLWithPath: path), format: .RGBA8, colorSpace: sRGB)
    }
}
