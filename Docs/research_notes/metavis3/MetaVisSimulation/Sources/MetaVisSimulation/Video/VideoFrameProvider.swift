import Foundation
import AVFoundation
import Metal
import MetalKit
import CoreVideo
import MetaVisCore

/// Manages video playback for the Simulation Engine.
/// Uses AVPlayerItemVideoOutput for efficient hardware decoding.
/// Applies Input Device Transform (IDT) to convert to Linear ACEScg.
public class VideoFrameProvider {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var textureCache: CVMetalTextureCache?
    
    // Color Pipeline
    private var idtPass: InputDeviceTransformPass?
    
    // Active Players
    private var players: [UUID: VideoPlayerSession] = [:]
    
    // FITS Support
    private let fitsReader = FITSReader()
    private var fitsCache: [UUID: MTLTexture] = [:]
    private var fitsAssets: [UUID: URL] = [:]
    
    public init(device: MTLDevice, library: MTLLibrary? = nil) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        
        do {
            self.idtPass = try InputDeviceTransformPass(device: device, library: library)
        } catch {
            print("❌ VideoFrameProvider: Failed to create IDT pass: \(error)")
        }
    }
    
    public func register(assetId: UUID, url: URL) {
        // Check extension for FITS
        if url.pathExtension.lowercased() == "fits" || url.pathExtension.lowercased() == "fit" {
            fitsAssets[assetId] = url
            return
        }
        
        // Only create if not exists or URL changed
        if let existing = players[assetId], existing.url == url {
            return
        }
        players[assetId] = VideoPlayerSession(url: url)
    }
    
    public func texture(for assetId: UUID, at time: CMTime) -> MTLTexture? {
        // 1. Check FITS
        if let _ = fitsAssets[assetId] {
            if let tex = fitsCache[assetId] {
                return tex
            }
            
            // Load FITS if not in cache
            return loadFITS(assetId: assetId)
        }
        
        guard let session = players[assetId] else { return nil }
        
        // Get raw texture from decoder
        guard let rawTexture = session.getTexture(at: time, textureCache: textureCache) else {
            return nil
        }
        
        // If we have an IDT pass and a detected color space, apply the transform
        if let idtPass = idtPass, let sourceSpace = session.detectedColorSpace {
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                return rawTexture
            }
            
            do {
                let outputTexture = try idtPass.convert(
                    texture: rawTexture,
                    from: sourceSpace,
                    commandBuffer: commandBuffer
                )
                commandBuffer.commit()
                return outputTexture
            } catch {
                print("❌ IDT conversion failed: \(error)")
                return rawTexture
            }
        }
        
        // Fallback: Return raw texture (likely sRGB/Rec.709)
        return rawTexture
    }
    
    private func loadFITS(assetId: UUID) -> MTLTexture? {
        guard let url = fitsAssets[assetId] else { return nil }
        
        do {
            let asset = try fitsReader.read(url: url)
            
            // Create Texture (R32Float for raw FITS data)
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r32Float,
                width: asset.width,
                height: asset.height,
                mipmapped: false
            )
            desc.usage = [.shaderRead]
            
            guard let texture = device.makeTexture(descriptor: desc) else { return nil }
            texture.label = url.lastPathComponent
            
            // Upload Data
            let region = MTLRegionMake2D(0, 0, asset.width, asset.height)
            
            asset.rawData.withUnsafeBytes { buffer in
                if let baseAddress = buffer.baseAddress {
                    texture.replace(region: region, mipmapLevel: 0, withBytes: baseAddress, bytesPerRow: asset.width * 4)
                }
            }
            
            fitsCache[assetId] = texture
            print("✅ Loaded FITS Texture: \(url.lastPathComponent) (\(asset.width)x\(asset.height))")
            print("STATS: Min=\(asset.statistics.min), Max=\(asset.statistics.max), Mean=\(asset.statistics.mean)")
            return texture
            
        } catch {
            print("❌ Failed to load FITS texture: \(error)")
            return nil
        }
    }
}

/// Internal helper to wrap AVAssetReader for offline rendering
private class VideoPlayerSession: @unchecked Sendable {
    let url: URL
    let asset: AVAsset
    var reader: AVAssetReader?
    var output: AVAssetReaderTrackOutput?
    
    // Frame Caching
    private var currentFrame: (buffer: CVPixelBuffer, time: CMTime)?
    private var nextFrame: (buffer: CVPixelBuffer, time: CMTime)?
    
    // Color Management
    private let lock = NSLock()
    private var _detectedColorSpace: RenderColorSpace?
    var detectedColorSpace: RenderColorSpace? {
        get { lock.lock(); defer { lock.unlock() }; return _detectedColorSpace }
        set { lock.lock(); defer { lock.unlock() }; _detectedColorSpace = newValue }
    }
    
    init(url: URL) {
        self.url = url
        self.asset = AVAsset(url: url)
        
        // Start async probe
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let asset = try await Asset(from: url)
                if let cp = asset.colorProfile {
                    // Map Core types to Simulation types
                    let primaries = ColorPrimaries(rawValue: cp.primaries.rawValue) ?? .bt709
                    let transfer = TransferFunction(rawValue: cp.transferFunction.rawValue) ?? .bt709
                    
                    self.detectedColorSpace = RenderColorSpace(primaries: primaries, transfer: transfer)
                    print("✅ Video detected as: \(self.detectedColorSpace?.name ?? "Unknown")")
                }
            } catch {
                print("⚠️ Video probe failed for \(url.lastPathComponent): \(error)")
            }
        }
    }
    
    func getTexture(at time: CMTime, textureCache: CVMetalTextureCache?) -> MTLTexture? {
        // 1. Initialize or Reset Reader if needed
        if let reader = reader, reader.status == .failed {
            // Try to recover
            setupReader(at: time)
        }
        
        // If we have no reader, or if we need to seek backwards
        if reader == nil || (currentFrame != nil && time < currentFrame!.time) {
            if !setupReader(at: time) {
                return nil
            }
        }
        
        // 2. Advance to the correct frame
        while let next = nextFrame, next.time <= time {
            currentFrame = next
            nextFrame = readNextFrame()
            
            if nextFrame == nil {
                // End of stream handling
                if let current = currentFrame, time > current.time + CMTime(value: 1, timescale: 10) {
                    return nil
                }
                break
            }
        }
        
        // 3. Return texture from current frame
        if let frame = currentFrame {
            return createTexture(from: frame.buffer, cache: textureCache)
        }
        
        return nil
    }
    
    private func setupReader(at time: CMTime) -> Bool {
        reader?.cancelReading()
        reader = nil
        output = nil
        currentFrame = nil
        nextFrame = nil
        
        do {
            reader = try AVAssetReader(asset: asset)
            
            guard let track = asset.tracks(withMediaType: .video).first else {
                return false
            }
            
            // Use 64-bit RGBA Half (Float16) for high precision / HDR support
            let settings: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_64RGBAHalf)
            ]
            
            let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
            trackOutput.alwaysCopiesSampleData = false
            
            if reader?.canAdd(trackOutput) == true {
                reader?.add(trackOutput)
                self.output = trackOutput
            } else {
                return false
            }
            
            reader?.timeRange = CMTimeRange(start: time, duration: .positiveInfinity)
            
            if reader?.startReading() == false {
                return false
            }
            
            // Prime the pump
            if let first = readNextFrame() {
                currentFrame = first
                nextFrame = readNextFrame()
            }
            
            return true
            
        } catch {
            print("❌ VideoPlayerSession: Setup failed: \(error)")
            return false
        }
    }
    
    private func readNextFrame() -> (buffer: CVPixelBuffer, time: CMTime)? {
        guard let output = output else { return nil }
        
        if let sampleBuffer = output.copyNextSampleBuffer(),
           let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            return (pixelBuffer, time)
        }
        return nil
    }
    
    private func createTexture(from pixelBuffer: CVPixelBuffer, cache: CVMetalTextureCache?) -> MTLTexture? {
        guard let cache = cache else { return nil }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            .rgba16Float, // Match kCVPixelFormatType_64RGBAHalf
            width,
            height,
            0,
            &cvTexture
        )
        
        if status == kCVReturnSuccess, let cvTexture = cvTexture {
            return CVMetalTextureGetTexture(cvTexture)
        }
        return nil
    }
}

// MARK: - Extensions

extension RenderColorSpace {
    /// Initialize from probed ColorSpaceInfo
    init(from info: ColorSpaceInfo) {
        // Map Primaries
        let p: ColorPrimaries
        switch info.primaries {
        case .bt709: p = .bt709
        case .bt2020: p = .bt2020
        case .p3DCI: p = .p3DCI
        case .p3D65: p = .p3D65
        case .sRGB: p = .sRGB
        case .adobeRGB: p = .adobeRGB
        case .unknown: p = .bt709 // Default
        }
        
        // Map Transfer
        let t: TransferFunction
        switch info.transfer {
        case .bt709: t = .bt709
        case .sRGB: t = .sRGB
        case .linear: t = .linear
        case .pq: t = .pq
        case .hlg: t = .hlg
        case .gamma22: t = .gamma22
        case .gamma28: t = .gamma28
        case .log: t = .log
        case .slog3: t = .slog3
        case .appleLog: t = .appleLog
        case .unknown: t = .bt709 // Default
        }
        
        self.init(primaries: p, transfer: t)
    }
}
