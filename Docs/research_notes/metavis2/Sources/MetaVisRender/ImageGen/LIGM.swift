import Foundation
import Metal
import CoreGraphics
import ImageIO

/// Local Image Generation Module (LIGM)
/// Main orchestrator for offline, deterministic image generation
/// Supports: Procedural, CoreML/MLX backends with automatic selection
/// Output: ACEScg-linear RGBA16Float textures
public final class LIGM {
    
    // MARK: - Properties
    
    private let device: MTLDevice
    private let backends: [LIGMBackend]
    private let proceduralBackend: LIGMProceduralBackend
    private let mlBackend: LIGMBackend?
    
    // MARK: - Initialization
    
    /// Initialize LIGM with Metal device
    /// - Parameter device: Metal device for texture creation
    public init(device: MTLDevice? = nil) {
        // Get or create Metal device
        if let device = device {
            self.device = device
        } else if let defaultDevice = MTLCreateSystemDefaultDevice() {
            self.device = defaultDevice
        } else {
            fatalError("No Metal device available. LIGM requires Metal support.")
        }
        
        // Initialize backends
        self.proceduralBackend = LIGMProceduralBackend()
        
        // Initialize ML backend if available
        if #available(macOS 13.0, *) {
            self.mlBackend = LIGMCoreMLBackend()
        } else {
            self.mlBackend = nil
        }
        
        // Build backend list
        var backends: [LIGMBackend] = [proceduralBackend]
        if let mlBackend = mlBackend {
            backends.append(mlBackend)
        }
        self.backends = backends
    }
    
    // MARK: - Generation
    
    /// Generate image according to request
    /// Automatically selects best backend based on mode and availability
    public func generate(request: LIGMRequest) async throws -> LIGMResponse {
        let backend = try selectBackend(for: request)
        return try await backend.generate(request: request, device: device)
    }
    
    /// Generate multiple images in batch
    /// Uses concurrent execution for independent requests
    public func generateBatch(requests: [LIGMRequest]) async throws -> [LIGMResponse] {
        return try await withThrowingTaskGroup(of: LIGMResponse.self) { group in
            for request in requests {
                group.addTask {
                    try await self.generate(request: request)
                }
            }
            
            var responses: [LIGMResponse] = []
            for try await response in group {
                responses.append(response)
            }
            
            // Sort by request ID to maintain order
            return responses.sorted { $0.id < $1.id }
        }
    }
    
    // MARK: - Backend Selection
    
    /// Select appropriate backend for request
    /// Rules:
    /// 1. If forceBackend specified, use that (if available)
    /// 2. For shader tests → Procedural only
    /// 3. For ML mode → ML backend with procedural fallback
    /// 4. For procedural modes → Procedural backend
    private func selectBackend(for request: LIGMRequest) throws -> LIGMBackend {
        // Check for forced backend
        if let forced = request.forceBackend {
            guard let backend = backends.first(where: { $0.backendType == forced && $0.isAvailable }) else {
                throw LIGMError.backendUnavailable(forced)
            }
            return backend
        }
        
        // Auto-selection based on mode
        switch request.mode {
        case .ml:
            // Prefer ML backend, fallback to procedural
            if let ml = mlBackend, ml.isAvailable {
                return ml
            } else {
                print("⚠️ ML backend unavailable, using procedural fallback")
                return proceduralBackend
            }
            
        case .noise, .fbm, .domainWarp, .gradient, .sdf, .hubblePreprocess, .texture:
            // Use procedural backend for deterministic modes
            return proceduralBackend
        }
    }
    
    // MARK: - File I/O
    
    /// Save response texture to file (.exr or .png)
    /// Automatically determines format from extension
    public func save(response: LIGMResponse, to url: URL) throws {
        guard let pixelData = response.pixelData else {
            throw LIGMError.outputPathInvalid("No pixel data available in response")
        }
        
        let ext = url.pathExtension.lowercased()
        
        switch ext {
        case "exr":
            try saveEXR(pixels: pixelData, width: response.texture.width, height: response.texture.height, to: url)
        case "png":
            try savePNG(pixels: pixelData, width: response.texture.width, height: response.texture.height, to: url)
        default:
            throw LIGMError.outputPathInvalid("Unsupported format: \(ext). Use .exr or .png")
        }
    }
    
    /// Load request from JSON file
    public func loadRequest(from url: URL) throws -> LIGMRequest {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(LIGMRequest.self, from: data)
    }
    
    /// Save request to JSON file
    public func saveRequest(_ request: LIGMRequest, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(request)
        try data.write(to: url)
    }
    
    // MARK: - Private Helpers
    
    private func saveEXR(pixels: [Float], width: Int, height: Int, to url: URL) throws {
        // EXR saving requires external library (OpenEXR)
        // For now, we'll save as raw float data with .exr extension
        // TODO: Integrate OpenEXR library
        
        let data = pixels.withUnsafeBytes { Data($0) }
        try data.write(to: url)
    }
    
    private func savePNG(pixels: [Float], width: Int, height: Int, to url: URL) throws {
        // Convert Float → UInt8 for PNG
        // Apply sRGB transfer function for proper display
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        
        for i in 0..<(width * height) {
            let offset = i * 4
            
            // ACEScg → sRGB (simplified, assumes in-gamut)
            let r = linearToSRGB(pixels[offset])
            let g = linearToSRGB(pixels[offset + 1])
            let b = linearToSRGB(pixels[offset + 2])
            let a = pixels[offset + 3]
            
            bytes[offset] = UInt8(clamp(r * 255.0, 0, 255))
            bytes[offset + 1] = UInt8(clamp(g * 255.0, 0, 255))
            bytes[offset + 2] = UInt8(clamp(b * 255.0, 0, 255))
            bytes[offset + 3] = UInt8(clamp(a * 255.0, 0, 255))
        }
        
        // Create CGImage
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else {
            throw LIGMError.outputPathInvalid("Failed to create data provider")
        }
        
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: CGColorRenderingIntent.defaultIntent
        ) else {
            throw LIGMError.outputPathInvalid("Failed to create CGImage")
        }
        
        // Write PNG
        let utType = "public.png" as CFString
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, utType, 1, nil) else {
            throw LIGMError.outputPathInvalid("Failed to create image destination")
        }
        
        CGImageDestinationAddImage(destination, cgImage, nil as CFDictionary?)
        
        guard CGImageDestinationFinalize(destination) else {
            throw LIGMError.outputPathInvalid("Failed to write PNG file")
        }
    }
    
    private func linearToSRGB(_ linear: Float) -> Float {
        if linear <= 0.0031308 {
            return linear * 12.92
        } else {
            return 1.055 * pow(linear, 1.0 / 2.4) - 0.055
        }
    }
    
    private func clamp(_ value: Float, _ min: Float, _ max: Float) -> Float {
        return Swift.max(min, Swift.min(max, value))
    }
}

// MARK: - Convenience Extensions

extension LIGM {
    
    /// Quick noise generation
    public func generateNoise(
        width: Int,
        height: Int,
        seed: UInt64 = 42,
        frequency: Float = 1.0,
        amplitude: Float = 1.0
    ) async throws -> LIGMResponse {
        let request = LIGMRequest(
            id: UUID().uuidString,
            width: width,
            height: height,
            seed: seed,
            mode: .noise,
            parameters: ["frequency": frequency, "amplitude": amplitude]
        )
        return try await generate(request: request)
    }
    
    /// Quick FBM generation
    public func generateFBM(
        width: Int,
        height: Int,
        seed: UInt64 = 42,
        octaves: Int = 6,
        lacunarity: Float = 2.0,
        gain: Float = 0.5
    ) async throws -> LIGMResponse {
        let request = LIGMRequest(
            id: UUID().uuidString,
            width: width,
            height: height,
            seed: seed,
            mode: .fbm,
            parameters: [
                "octaves": Float(octaves),
                "lacunarity": lacunarity,
                "gain": gain
            ]
        )
        return try await generate(request: request)
    }
    
    /// Quick gradient generation
    public func generateGradient(
        width: Int,
        height: Int,
        start: SIMD3<Float>,
        end: SIMD3<Float>,
        angle: Float = 0.0
    ) async throws -> LIGMResponse {
        let request = LIGMRequest(
            id: UUID().uuidString,
            width: width,
            height: height,
            seed: 0,
            mode: .gradient,
            parameters: [
                "angle": angle,
                "startR": start.x,
                "startG": start.y,
                "startB": start.z,
                "endR": end.x,
                "endG": end.y,
                "endB": end.z
            ]
        )
        return try await generate(request: request)
    }
    
    /// Quick SDF generation
    public func generateSDF(
        width: Int,
        height: Int,
        shape: SDFShape,
        center: SIMD2<Float> = SIMD2(0.5, 0.5),
        radius: Float = 0.3
    ) async throws -> LIGMResponse {
        let request = LIGMRequest(
            id: UUID().uuidString,
            width: width,
            height: height,
            seed: 0,
            mode: .sdf,
            parameters: [
                "shape": Float(shape.rawValue),
                "centerX": center.x,
                "centerY": center.y,
                "radius": radius
            ]
        )
        return try await generate(request: request)
    }
}

// MARK: - Supporting Types

public enum SDFShape: Int {
    case circle = 0
    case box = 1
    case star = 2
}
