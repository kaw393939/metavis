import Metal
import CoreML
import Vision
import CoreVideo
import Accelerate
import QuartzCore

/// ML-based depth estimation from single RGB images
/// Uses Depth Anything V2 Core ML model for depth inference
public final class MLDepthEstimator: DepthEstimator, @unchecked Sendable {
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let textureCache: CVMetalTextureCache
    
    // Core ML model
    private var visionModel: VNCoreMLModel?
    private var modelLoaded: Bool = false
    
    // Cache for depth maps (keyed by texture pointer)
    private var cache: [ObjectIdentifier: DepthMap] = [:]
    private let cacheQueue = DispatchQueue(label: "com.metavis.depth.cache", qos: .userInteractive)
    
    // Configuration
    public var preferredDevice: ComputeDevice = .ane
    public private(set) var lastExecutionDevice: ComputeDevice?
    
    // Expected input size for Depth Anything V2 Small
    private let modelInputWidth = 518
    private let modelInputHeight = 392
    
    public init(device: MTLDevice? = nil) throws {
        self.device = device ?? MTLCreateSystemDefaultDevice()!
        
        guard let queue = self.device.makeCommandQueue() else {
            throw DepthEstimatorError.bufferCreationFailed
        }
        self.commandQueue = queue
        
        // Create texture cache for efficient CPU<->GPU transfers
        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            self.device,
            nil,
            &cache
        )
        
        guard status == kCVReturnSuccess, let textureCache = cache else {
            throw DepthEstimatorError.bufferCreationFailed
        }
        self.textureCache = textureCache
        
        // Try to load the ML model asynchronously
        Task {
            await loadModel()
        }
    }
    
    /// Load the Depth Anything V2 model
    private func loadModel() async {
        do {
            // Look for the model in the bundle or Resources directory
            let modelName = "DepthAnythingV2SmallF16"
            
            // Try bundle first - look in Models folder
            if let modelURL = Bundle.module.url(forResource: modelName, withExtension: "mlmodelc", subdirectory: "Models") ?? 
                              Bundle.module.url(forResource: modelName, withExtension: "mlpackage", subdirectory: "Models") ??
                              Bundle.module.url(forResource: modelName, withExtension: "mlmodelc") ?? 
                              Bundle.module.url(forResource: modelName, withExtension: "mlpackage") {
                let config = MLModelConfiguration()
                config.computeUnits = .cpuAndNeuralEngine  // Fixed: Force ANE usage for 10-50x speedup
                
                // Compile if needed (mlpackage) or load directly (mlmodelc)
                let compiledURL = try await compileModelIfNeeded(at: modelURL)
                let model = try await MLModel.load(contentsOf: compiledURL, configuration: config)
                self.visionModel = try VNCoreMLModel(for: model)
                self.modelLoaded = true
                print("✓ Loaded Depth Anything V2 model from bundle")
            } else {
                // Try Resources/Models path
                let resourcePath = Bundle.module.resourcePath ?? ""
                let possiblePaths = [
                    URL(fileURLWithPath: resourcePath).appendingPathComponent("Models/\(modelName).mlpackage"),
                    URL(fileURLWithPath: resourcePath).appendingPathComponent("\(modelName).mlpackage"),
                    URL(fileURLWithPath: "/Users/kwilliams/Projects/metavis_render/Resources/Models/\(modelName).mlpackage")
                ]
                
                for path in possiblePaths {
                    if FileManager.default.fileExists(atPath: path.path) {
                        let config = MLModelConfiguration()
                        config.computeUnits = .cpuAndNeuralEngine  // Fixed: Force ANE usage for 10-50x speedup
                        
                        // Compile if needed (mlpackage) or load directly (mlmodelc)
                        let compiledURL = try await compileModelIfNeeded(at: path)
                        let model = try await MLModel.load(contentsOf: compiledURL, configuration: config)
                        self.visionModel = try VNCoreMLModel(for: model)
                        self.modelLoaded = true
                        print("✓ Loaded Depth Anything V2 model from \(path.lastPathComponent)")
                        return
                    }
                }
                
                print("⚠ Depth Anything V2 model not found, using fallback depth estimation")
            }
        } catch {
            print("⚠ Failed to load depth model: \(error.localizedDescription)")
        }
    }
    
    /// Compile mlpackage to mlmodelc if needed
    private func compileModelIfNeeded(at url: URL) async throws -> URL {
        if url.pathExtension == "mlmodelc" {
            return url
        }
        
        // Check for cached compiled model
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("MetaVisModels")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        
        let compiledURL = cacheDir.appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".mlmodelc")
        
        if FileManager.default.fileExists(atPath: compiledURL.path) {
            return compiledURL
        }
        
        // Compile the model
        print("Compiling depth model (first run only)...")
        let compiled = try await MLModel.compileModel(at: url)
        
        // Move to cache
        try? FileManager.default.removeItem(at: compiledURL)
        try FileManager.default.copyItem(at: compiled, to: compiledURL)
        
        return compiledURL
    }
    
    public func estimateDepth(from texture: MTLTexture) async throws -> DepthMap {
        let textureId = ObjectIdentifier(texture)
        
        // Check cache first
        if let cached = cacheQueue.sync(execute: { cache[textureId] }) {
            return cached
        }
        
        // Convert texture to pixel buffer
        let pixelBuffer = try await textureToPixelBuffer(texture)
        
        // Run depth estimation
        let depthPixelBuffer: CVPixelBuffer
        
        if modelLoaded, let visionModel = visionModel {
            // Use ML model
            depthPixelBuffer = try await runMLDepthEstimation(pixelBuffer: pixelBuffer, model: visionModel)
            lastExecutionDevice = preferredDevice
        } else {
            // Use fallback
            depthPixelBuffer = try await runFallbackDepthEstimation(pixelBuffer: pixelBuffer)
            lastExecutionDevice = .gpu
        }
        
        // Convert result to Metal texture
        let depthTexture = try pixelBufferToDepthTexture(
            depthPixelBuffer,
            targetWidth: texture.width,
            targetHeight: texture.height
        )
        
        let depthMap = DepthMap(
            texture: depthTexture,
            minDepth: 0.0,
            maxDepth: 1.0,
            timestamp: CACurrentMediaTime()
        )
        
        // Cache result
        cacheQueue.async { [weak self] in
            self?.cache[textureId] = depthMap
            
            // Limit cache size
            if let cache = self?.cache, cache.count > 10 {
                let sortedKeys = Array(cache.keys).prefix(5)
                for key in sortedKeys {
                    self?.cache.removeValue(forKey: key)
                }
            }
        }
        
        return depthMap
    }
    
    public func clearCache() {
        cacheQueue.async { [weak self] in
            self?.cache.removeAll()
        }
    }
    
    // MARK: - ML Model Inference
    
    private func runMLDepthEstimation(pixelBuffer: CVPixelBuffer, model: VNCoreMLModel) async throws -> CVPixelBuffer {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observation = request.results?.first as? VNPixelBufferObservation else {
                    continuation.resume(throwing: DepthEstimatorError.noResults)
                    return
                }
                
                continuation.resume(returning: observation.pixelBuffer)
            }
            
            request.imageCropAndScaleOption = .scaleFill
            
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Fallback Depth Estimation
    
    private func runFallbackDepthEstimation(pixelBuffer: CVPixelBuffer) async throws -> CVPixelBuffer {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var outputBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_OneComponent32Float,
            kCVPixelBufferMetalCompatibilityKey: true
        ]
        
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_OneComponent32Float,
            attrs as CFDictionary,
            &outputBuffer
        )
        
        guard let output = outputBuffer else {
            throw DepthEstimatorError.bufferCreationFailed
        }
        
        try estimateDepthFromEdges(input: pixelBuffer, output: output)
        
        return output
    }
    
    /// Fallback depth estimation using edge detection and luminance
    private func estimateDepthFromEdges(input: CVPixelBuffer, output: CVPixelBuffer) throws {
        CVPixelBufferLockBaseAddress(input, .readOnly)
        CVPixelBufferLockBaseAddress(output, [])
        defer {
            CVPixelBufferUnlockBaseAddress(input, .readOnly)
            CVPixelBufferUnlockBaseAddress(output, [])
        }
        
        let width = CVPixelBufferGetWidth(input)
        let height = CVPixelBufferGetHeight(input)
        
        guard let inputBase = CVPixelBufferGetBaseAddress(input),
              let outputBase = CVPixelBufferGetBaseAddress(output) else {
            throw DepthEstimatorError.bufferCreationFailed
        }
        
        let inputBytesPerRow = CVPixelBufferGetBytesPerRow(input)
        let outputBytesPerRow = CVPixelBufferGetBytesPerRow(output)
        
        let outputPtr = outputBase.assumingMemoryBound(to: Float.self)
        let inputPtr = inputBase.assumingMemoryBound(to: UInt8.self)
        
        // Sobel edge detection + luminance-based depth
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                // Compute edge magnitude using Sobel
                var gx: Float = 0
                var gy: Float = 0
                
                for ky in -1...1 {
                    for kx in -1...1 {
                        let offset = (y + ky) * inputBytesPerRow + (x + kx) * 4
                        let lum = Float(inputPtr[offset + 1]) / 255.0  // Use green channel
                        
                        // Sobel kernels
                        let sobelX: [[Float]] = [[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]]
                        let sobelY: [[Float]] = [[-1, -2, -1], [0, 0, 0], [1, 2, 1]]
                        
                        gx += lum * sobelX[ky + 1][kx + 1]
                        gy += lum * sobelY[ky + 1][kx + 1]
                    }
                }
                
                let edgeMagnitude = min(1.0, sqrt(gx * gx + gy * gy))
                
                // Get luminance
                let inputOffset = y * inputBytesPerRow + x * 4
                let b = Float(inputPtr[inputOffset]) / 255.0
                let g = Float(inputPtr[inputOffset + 1]) / 255.0
                let r = Float(inputPtr[inputOffset + 2]) / 255.0
                let luminance = 0.299 * r + 0.587 * g + 0.114 * b
                
                // Combine: edges suggest closer objects, darker = further
                var depth = 0.5 + (1.0 - luminance) * 0.3 - edgeMagnitude * 0.2
                
                // Add vertical bias (lower = closer, like ground plane)
                let verticalBias = Float(y) / Float(height) * 0.2
                depth = max(0.0, min(1.0, depth - verticalBias + 0.1))
                
                let outputOffset = y * outputBytesPerRow / 4 + x
                outputPtr[outputOffset] = depth
            }
        }
        
        // Fill edges
        for x in 0..<width {
            let topOffset = 0 * outputBytesPerRow / 4 + x
            let bottomOffset = (height - 1) * outputBytesPerRow / 4 + x
            outputPtr[topOffset] = 0.9
            outputPtr[bottomOffset] = 0.3
        }
    }
    
    // MARK: - Texture/Buffer Conversion
    
    private func textureToPixelBuffer(_ texture: MTLTexture) async throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferWidthKey: texture.width,
            kCVPixelBufferHeightKey: texture.height,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            texture.width,
            texture.height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw DepthEstimatorError.bufferCreationFailed
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: texture.width, height: texture.height, depth: 1)
        )
        
        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            texture.getBytes(
                baseAddress,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                from: region,
                mipmapLevel: 0
            )
        }
        
        return buffer
    }
    
    private func pixelBufferToDepthTexture(
        _ pixelBuffer: CVPixelBuffer,
        targetWidth: Int,
        targetHeight: Int
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: targetWidth,
            height: targetHeight,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw DepthEstimatorError.textureCreationFailed
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let srcWidth = CVPixelBufferGetWidth(pixelBuffer)
        let srcHeight = CVPixelBufferGetHeight(pixelBuffer)
        
        guard let srcData = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw DepthEstimatorError.bufferCreationFailed
        }
        
        let srcBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        if srcWidth == targetWidth && srcHeight == targetHeight {
            // Direct copy
            let region = MTLRegion(
                origin: MTLOrigin(x: 0, y: 0, z: 0),
                size: MTLSize(width: targetWidth, height: targetHeight, depth: 1)
            )
            texture.replace(
                region: region,
                mipmapLevel: 0,
                withBytes: srcData,
                bytesPerRow: srcBytesPerRow
            )
        } else {
            // Bilinear resize using Accelerate
            let srcPtr = srcData.assumingMemoryBound(to: Float.self)
            var dstData = [Float](repeating: 0, count: targetWidth * targetHeight)
            
            // Simple bilinear interpolation
            for dstY in 0..<targetHeight {
                for dstX in 0..<targetWidth {
                    let srcX = Float(dstX) * Float(srcWidth - 1) / Float(targetWidth - 1)
                    let srcY = Float(dstY) * Float(srcHeight - 1) / Float(targetHeight - 1)
                    
                    let x0 = Int(srcX)
                    let y0 = Int(srcY)
                    let x1 = min(x0 + 1, srcWidth - 1)
                    let y1 = min(y0 + 1, srcHeight - 1)
                    
                    let fx = srcX - Float(x0)
                    let fy = srcY - Float(y0)
                    
                    let srcFloatsPerRow = srcBytesPerRow / 4
                    let v00 = srcPtr[y0 * srcFloatsPerRow + x0]
                    let v10 = srcPtr[y0 * srcFloatsPerRow + x1]
                    let v01 = srcPtr[y1 * srcFloatsPerRow + x0]
                    let v11 = srcPtr[y1 * srcFloatsPerRow + x1]
                    
                    let value = v00 * (1 - fx) * (1 - fy) +
                                v10 * fx * (1 - fy) +
                                v01 * (1 - fx) * fy +
                                v11 * fx * fy
                    
                    dstData[dstY * targetWidth + dstX] = value
                }
            }
            
            // Upload to texture
            let region = MTLRegion(
                origin: MTLOrigin(x: 0, y: 0, z: 0),
                size: MTLSize(width: targetWidth, height: targetHeight, depth: 1)
            )
            
            dstData.withUnsafeBytes { ptr in
                texture.replace(
                    region: region,
                    mipmapLevel: 0,
                    withBytes: ptr.baseAddress!,
                    bytesPerRow: targetWidth * MemoryLayout<Float>.stride
                )
            }
        }
        
        return texture
    }
}

// MARK: - Mock Depth Estimator for Testing

/// A mock depth estimator that returns synthetic depth maps
public final class MockDepthEstimator: DepthEstimator, @unchecked Sendable {
    private let device: MTLDevice
    
    /// Depth generation mode
    public enum Mode: Sendable {
        case gradient      // Vertical gradient (top=far, bottom=near)
        case centerBias    // Center is closer
        case uniform(Float) // Uniform depth value
        case random        // Random noise
    }
    
    public var mode: Mode = .gradient
    
    public init(device: MTLDevice? = nil) {
        self.device = device ?? MTLCreateSystemDefaultDevice()!
    }
    
    public func estimateDepth(from texture: MTLTexture) async throws -> DepthMap {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: texture.width,
            height: texture.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        
        guard let depthTexture = device.makeTexture(descriptor: descriptor) else {
            throw DepthEstimatorError.textureCreationFailed
        }
        
        // Generate depth data
        var depthData = [Float](repeating: 0.5, count: texture.width * texture.height)
        
        switch mode {
        case .gradient:
            for y in 0..<texture.height {
                let depth = Float(y) / Float(texture.height)
                for x in 0..<texture.width {
                    depthData[y * texture.width + x] = depth
                }
            }
            
        case .centerBias:
            let centerX = Float(texture.width) / 2.0
            let centerY = Float(texture.height) / 2.0
            let maxDist = sqrt(centerX * centerX + centerY * centerY)
            
            for y in 0..<texture.height {
                for x in 0..<texture.width {
                    let dx = Float(x) - centerX
                    let dy = Float(y) - centerY
                    let dist = sqrt(dx * dx + dy * dy)
                    let depth = dist / maxDist
                    depthData[y * texture.width + x] = depth
                }
            }
            
        case .uniform(let value):
            depthData = [Float](repeating: value, count: texture.width * texture.height)
            
        case .random:
            for i in 0..<depthData.count {
                depthData[i] = Float.random(in: 0...1)
            }
        }
        
        // Upload to texture
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: texture.width, height: texture.height, depth: 1)
        )
        
        depthData.withUnsafeBytes { ptr in
            depthTexture.replace(
                region: region,
                mipmapLevel: 0,
                withBytes: ptr.baseAddress!,
                bytesPerRow: texture.width * MemoryLayout<Float>.stride
            )
        }
        
        return DepthMap(
            texture: depthTexture,
            minDepth: 0.0,
            maxDepth: 1.0,
            timestamp: CACurrentMediaTime()
        )
    }
    
    public func clearCache() {
        // No cache in mock
    }
}
