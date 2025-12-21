import Foundation
import Metal
import CoreVideo
import AVFoundation

/// Handles zero-copy conversion from Metal textures to CVPixelBuffers
/// Optimized for Apple Silicon Media Engine (10-bit HEVC/ProRes)
public class ZeroCopyConverter {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var textureCache: CVMetalTextureCache?
    private var pipelineState: MTLComputePipelineState?
    
    public init(device: MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw ZeroCopyError.initializationFailed("Could not create command queue")
        }
        self.commandQueue = queue
        
        // Create Texture Cache
        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        guard status == kCVReturnSuccess, let createdCache = cache else {
            throw ZeroCopyError.initializationFailed("Could not create CVMetalTextureCache")
        }
        self.textureCache = createdCache
        
        // Load Shader
        try loadShader()
    }
    
    private func loadShader() throws {
        var library: MTLLibrary?
        
        print("      ZeroCopy: Searching for library...")
        
        // 1. Try Bundle.module (SwiftPM resource bundle)
        // This is the most likely place if running as a package dependency
        // We use a do-catch block because accessing Bundle.module might throw if resources aren't found
        do {
            let moduleBundle = Bundle.module
            print("      ZeroCopy: Checking Bundle.module: \(moduleBundle.bundlePath)")
            try? library = device.makeDefaultLibrary(bundle: moduleBundle)
            if library != nil { print("      ZeroCopy: Found library in Bundle.module") }
        }
        
        // 2. Try Bundle(for: Self)
        if library == nil {
            let bundle = Bundle(for: ZeroCopyConverter.self)
            print("      ZeroCopy: Checking Bundle(for: ZeroCopyConverter): \(bundle.bundlePath)")
            try? library = device.makeDefaultLibrary(bundle: bundle)
            if library != nil { print("      ZeroCopy: Found library in Bundle(for: ZeroCopyConverter)") }
        }
        
        // 3. Try default library (Main Bundle)
        if library == nil {
             print("      ZeroCopy: Checking default library (main bundle)")
             library = device.makeDefaultLibrary()
             if library != nil { print("      ZeroCopy: Found default library") }
        }
        
        // 4. Fallback: Compile from Source (if resource is present but not compiled)
        if library == nil {
             print("      ZeroCopy: Attempting to compile from source...")
             // Try to find ZeroCopy.metal in Bundle.module
             do {
                 let moduleBundle = Bundle.module
                 if let path = moduleBundle.path(forResource: "ZeroCopy", ofType: "metal", inDirectory: "Shaders") ?? 
                               moduleBundle.path(forResource: "ZeroCopy", ofType: "metal") {
                     print("      ZeroCopy: Found source at \(path)")
                     let source = try String(contentsOfFile: path, encoding: .utf8)
                     library = try device.makeLibrary(source: source, options: nil)
                     print("      ZeroCopy: ✅ Compiled library from source")
                 }
             } catch {
                 print("      ZeroCopy: Source compilation failed: \(error)")
             }
        }

        guard let lib = library else {
            print("      ZeroCopy: ❌ Could not load Metal library")
            throw ZeroCopyError.initializationFailed("Could not load Metal library")
        }
        
        guard let function = lib.makeFunction(name: "convert_rgba16float_to_yuv10_zerocopy") else {
            print("      ZeroCopy: ❌ Could not find function 'convert_rgba16float_to_yuv10_zerocopy'")
            print("      Available functions: \(lib.functionNames)")
            throw ZeroCopyError.initializationFailed("Could not find shader function 'convert_rgba16float_to_yuv10_zerocopy'")
        }
        
        self.pipelineState = try device.makeComputePipelineState(function: function)
        print("      ZeroCopy: ✅ Pipeline State Created")
    }
    
    /// Creates a CVPixelBufferPool for 10-bit 4:2:0 YUV
    public func createPixelBufferPool(width: Int, height: Int) -> CVPixelBufferPool? {
        let poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 3
        ]
        
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttributes as CFDictionary, pixelBufferAttributes as CFDictionary, &pool)
        return pool
    }
    
    /// Converts a Metal texture to a CVPixelBuffer using zero-copy compute shader
    public func convert(sourceTexture: MTLTexture, to pixelBuffer: CVPixelBuffer) async throws {
        guard let pipeline = pipelineState, let cache = textureCache else {
            throw ZeroCopyError.initializationFailed("Pipeline or TextureCache not initialized")
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // 1. Get Metal texture views of CVPixelBuffer planes (Zero-Copy)
        var yMetalTexture: CVMetalTexture?
        var uvMetalTexture: CVMetalTexture?
        
        // Y Plane (Full Res, r16Unorm for 10-bit)
        let yStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            .r16Unorm,
            width,
            height,
            0,
            &yMetalTexture
        )
        
        // UV Plane (Half Res, rg16Unorm for 10-bit)
        let uvStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            .rg16Unorm,
            width / 2,
            height / 2,
            1,
            &uvMetalTexture
        )
        
        guard yStatus == kCVReturnSuccess,
              uvStatus == kCVReturnSuccess,
              let yTex = yMetalTexture,
              let uvTex = uvMetalTexture,
              let yTexture = CVMetalTextureGetTexture(yTex),
              let uvTexture = CVMetalTextureGetTexture(uvTex) else {
            throw ZeroCopyError.renderingFailed("Could not create Metal textures from CVPixelBuffer")
        }
        
        // 2. Dispatch Compute Shader
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw ZeroCopyError.renderingFailed("Could not create command buffer/encoder")
        }
        
        encoder.label = "Zero-Copy RGB -> YUV10"
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(sourceTexture, index: 0)
        encoder.setTexture(yTexture, index: 1)
        encoder.setTexture(uvTexture, index: 2)
        
        // Dispatch threads (process 2x2 blocks)
        let w = pipeline.threadExecutionWidth
        let h = pipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
        let threadgroups = MTLSize(
            width: ((width / 2) + w - 1) / w,
            height: ((height / 2) + h - 1) / h,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
        // Wait for completion
        await withCheckedContinuation { continuation in
            commandBuffer.addCompletedHandler { _ in
                continuation.resume()
            }
            commandBuffer.commit()
        }
        
        if let error = commandBuffer.error {
            throw ZeroCopyError.renderingFailed("GPU execution failed: \(error.localizedDescription)")
        }
    }
}

public enum ZeroCopyError: Error {
    case initializationFailed(String)
    case renderingFailed(String)
}
