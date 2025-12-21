import Foundation
import AVFoundation
import CoreVideo
import Metal
import MetaVisRender

class SimpleVideoInputProvider: InputProvider {
    private var readers: [String: AVAssetReader] = [:]
    private var outputs: [String: AVAssetReaderTrackOutput] = [:]
    private let device: MTLDevice
    private var textureCache: CVMetalTextureCache?
    
    init(device: MTLDevice) {
        self.device = device
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
    }
    
    func loadAsset(id: String, url: URL) async throws {
        print("Provider: Loading asset \(id) from \(url.path)")
        let asset = AVAsset(url: url)
        
        // Verify asset is readable
        let isReadable = try await asset.load(.isReadable)
        guard isReadable else {
            print("Asset is not readable: \(url.path)")
            return
        }
        
        let reader = try AVAssetReader(asset: asset)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            print("No video track found for \(url.lastPathComponent)")
            return
        }
        
        let settings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false 
        
        if reader.canAdd(output) {
            reader.add(output)
            if reader.startReading() {
                readers[id] = reader
                outputs[id] = output
                print("Loaded asset '\(id)' from \(url.lastPathComponent)")
            } else {
                print("Failed to start reading \(id): \(reader.error?.localizedDescription ?? "Unknown error")")
            }
        } else {
            print("Cannot add output to reader for \(id)")
        }
    }
    
    func texture(for assetId: String, time: Double) -> MTLTexture? {
        print("DEBUG: SimpleVideoInputProvider.texture called for \(assetId)")
        
        // DEBUG: Return a RED texture to test pipeline
        // Use rgba16Float to match pipeline output format
        let width = 1920
        let height = 1080
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        
        guard let texture = device.makeTexture(descriptor: desc) else {
            print("DEBUG: Failed to create texture")
            return nil
        }
        
        // Fill with Red (1.0, 0.0, 0.0, 1.0) in Float16
        // 1.0 in Float16 is 0x3C00
        // Pixel: R=0x3C00, G=0x0000, B=0x0000, A=0x3C00
        let pixel: [UInt16] = [0x3C00, 0x0000, 0x0000, 0x3C00] 
        
        var data = [UInt16](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            data[i*4 + 0] = pixel[0]
            data[i*4 + 1] = pixel[1]
            data[i*4 + 2] = pixel[2]
            data[i*4 + 3] = pixel[3]
        }
        
        texture.replace(region: MTLRegionMake2D(0, 0, width, height),
                        mipmapLevel: 0,
                        withBytes: data,
                        bytesPerRow: width * 8) // 4 components * 2 bytes
        
        // Verify memory
        var readPixel = [UInt16](repeating: 0, count: 4)
        texture.getBytes(&readPixel, bytesPerRow: width * 8, from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0)
        print("DEBUG: Provider: Wrote [15360, 0, 0, 15360], Read \(readPixel)")
        
        return texture
    }

    
    private func makeTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let textureCache = textureCache else { return nil }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )
        
        if status == kCVReturnSuccess, let cvTexture = cvTexture {
            return CVMetalTextureGetTexture(cvTexture)
        }
        print("Provider: Failed to create texture from image. Status: \(status)")
        return nil
    }
}
