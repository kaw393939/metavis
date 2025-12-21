import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Nano Banana image generation client for deterministic reference image creation
public class NanoBananaImageGenerator {
    private let apiEndpoint: String
    private let model: String
    
    public init(apiEndpoint: String = "http://localhost:8080", model: String = "flux.1-schnell") {
        self.apiEndpoint = apiEndpoint
        self.model = model
    }
    
    /// Generate a single reference image with deterministic seed
    public func generate(
        prompt: String,
        width: Int,
        height: Int,
        seed: Int,
        steps: Int = 4
    ) async throws -> Data {
        let request = NanoBananaRequest(
            prompt: prompt,
            width: width,
            height: height,
            seed: seed,
            model: model,
            steps: steps,
            guidance: 1.0  // Low guidance for simple patterns
        )
        
        let url = URL(string: "\(apiEndpoint)/generate")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        urlRequest.timeoutInterval = 60.0
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NanoBananaError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw NanoBananaError.httpError(httpResponse.statusCode)
        }
        
        let result = try JSONDecoder().decode(NanoBananaResponse.self, from: data)
        
        guard let imageData = Data(base64Encoded: result.imageBase64) else {
            throw NanoBananaError.invalidImageData
        }
        
        return imageData
    }
    
    /// Generate all reference images from definitions
    public func generateReferenceLibrary(
        definitions: [ReferenceImageDefinition],
        outputDirectory: String = "Tests/MetaVisRenderTests/References"
    ) async throws {
        print("🎨 Generating \(definitions.count) reference images...")
        
        for (index, definition) in definitions.enumerated() {
            let progress = String(format: "[%d/%d]", index + 1, definitions.count)
            print("\(progress) Generating: \(definition.name)")
            
            let imageData = try await generate(
                prompt: definition.prompt,
                width: definition.width,
                height: definition.height,
                seed: definition.seed,
                steps: definition.steps
            )
            
            // Save to file
            let categoryPath = "\(outputDirectory)/\(definition.category)"
            let filePath = "\(categoryPath)/\(definition.filename)"
            
            // Create directory if needed
            try FileManager.default.createDirectory(
                atPath: categoryPath,
                withIntermediateDirectories: true
            )
            
            let fileURL = URL(fileURLWithPath: filePath)
            try imageData.write(to: fileURL)
            
            print("  ✅ Saved: \(filePath)")
        }
        
        print("\n✨ Generated \(definitions.count) reference images successfully!")
    }
    
    /// Test connectivity to Nano Banana endpoint
    public func testConnectivity() async throws -> Bool {
        let url = URL(string: "\(apiEndpoint)/health")!
        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = 5.0
        
        do {
            let (_, response) = try await URLSession.shared.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return httpResponse.statusCode == 200
        } catch {
            throw NanoBananaError.connectionFailed(error)
        }
    }
}

// MARK: - Request/Response Models

struct NanoBananaRequest: Codable {
    let prompt: String
    let width: Int
    let height: Int
    let seed: Int
    let model: String
    let steps: Int
    let guidance: Double
}

struct NanoBananaResponse: Codable {
    let imageBase64: String
    let seed: Int
    let model: String
    
    enum CodingKeys: String, CodingKey {
        case imageBase64 = "image"
        case seed
        case model
    }
}

// MARK: - Reference Image Definitions

public struct ReferenceImageDefinition {
    let name: String
    let category: String
    let filename: String
    let prompt: String
    let width: Int
    let height: Int
    let seed: Int
    let steps: Int
    
    public init(
        name: String,
        category: String,
        filename: String,
        prompt: String,
        width: Int,
        height: Int,
        seed: Int = 42,
        steps: Int = 4
    ) {
        self.name = name
        self.category = category
        self.filename = filename
        self.prompt = prompt
        self.width = width
        self.height = height
        self.seed = seed
        self.steps = steps
    }
}

public enum ReferenceImageDefinitions {
    // MARK: - ACES Color Tests
    
    public static let acesNeutralWhite = ReferenceImageDefinition(
        name: "ACES Neutral White",
        category: "aces",
        filename: "aces_neutral_white_128x128.png",
        prompt: "Pure white square, completely uniform, no gradient, no texture, solid white, 128x128 pixels",
        width: 128,
        height: 128,
        seed: 42
    )
    
    public static let acesNeutralGray = ReferenceImageDefinition(
        name: "ACES Neutral Gray",
        category: "aces",
        filename: "aces_neutral_gray_128x128.png",
        prompt: "Pure neutral gray square, 50% brightness, completely uniform, no gradient, 128x128 pixels",
        width: 128,
        height: 128,
        seed: 42
    )
    
    public static let acesPrimaries = ReferenceImageDefinition(
        name: "ACES Color Primaries",
        category: "aces",
        filename: "aces_primaries_128x128.png",
        prompt: "Four equal quadrants with sharp edges: top-left pure red, top-right pure green, bottom-left pure blue, bottom-right pure white, 128x128",
        width: 128,
        height: 128,
        seed: 42
    )
    
    public static let linearGradient = ReferenceImageDefinition(
        name: "Linear Gradient Black to White",
        category: "aces",
        filename: "aces_gradient_linear_256x256.png",
        prompt: "Perfect smooth linear gradient from pure black on left to pure white on right, horizontal, no banding, extremely smooth transition, 256x256",
        width: 256,
        height: 256,
        seed: 42
    )
    
    // MARK: - Background Tests
    
    public static let solidRed = ReferenceImageDefinition(
        name: "Solid Red Background",
        category: "backgrounds",
        filename: "solid_red_128x128.png",
        prompt: "Solid pure red color RGB(255,0,0), completely uniform, no variation, flat color, 128x128",
        width: 128,
        height: 128,
        seed: 42
    )
    
    public static let solidGreen = ReferenceImageDefinition(
        name: "Solid Green Background",
        category: "backgrounds",
        filename: "solid_green_128x128.png",
        prompt: "Solid pure green color RGB(0,255,0), completely uniform, no variation, flat color, 128x128",
        width: 128,
        height: 128,
        seed: 42
    )
    
    public static let solidBlue = ReferenceImageDefinition(
        name: "Solid Blue Background",
        category: "backgrounds",
        filename: "solid_blue_128x128.png",
        prompt: "Solid pure blue color RGB(0,0,255), completely uniform, no variation, flat color, 128x128",
        width: 128,
        height: 128,
        seed: 42
    )
    
    public static let starfield = ReferenceImageDefinition(
        name: "Starfield Background",
        category: "backgrounds",
        filename: "starfield_seed42_512x512.png",
        prompt: "Realistic starfield with white stars of varying sizes scattered on pure black background, natural random distribution, 512x512",
        width: 512,
        height: 512,
        seed: 42
    )
    
    // MARK: - Effects Tests
    
    public static let bloomTest = ReferenceImageDefinition(
        name: "Bloom Test Pattern",
        category: "effects",
        filename: "bloom_bright_spot_256x256.png",
        prompt: "Single bright white circle in center with soft glow bloom effect on pure black background, 256x256",
        width: 256,
        height: 256,
        seed: 42
    )
    
    public static let gradientSmooth = ReferenceImageDefinition(
        name: "Smooth Gradient for Banding Test",
        category: "effects",
        filename: "gradient_smooth_512x512.png",
        prompt: "Extremely smooth gradient from black to white, no visible banding, perfect smooth transition, 512x512",
        width: 512,
        height: 512,
        seed: 42
    )
    
    // MARK: - All Definitions
    
    public static var coreReferences: [ReferenceImageDefinition] {
        [
            acesNeutralWhite,
            acesNeutralGray,
            acesPrimaries,
            linearGradient,
            solidRed,
            solidGreen,
            solidBlue,
            starfield,
            bloomTest,
            gradientSmooth
        ]
    }
}

// MARK: - Errors

public enum NanoBananaError: Error, CustomStringConvertible {
    case invalidResponse
    case httpError(Int)
    case invalidImageData
    case connectionFailed(Error)
    
    public var description: String {
        switch self {
        case .invalidResponse:
            return "Invalid response from Nano Banana server"
        case .httpError(let code):
            return "HTTP error \(code) from Nano Banana server"
        case .invalidImageData:
            return "Received invalid image data from Nano Banana"
        case .connectionFailed(let error):
            return "Connection to Nano Banana failed: \(error.localizedDescription)"
        }
    }
}
