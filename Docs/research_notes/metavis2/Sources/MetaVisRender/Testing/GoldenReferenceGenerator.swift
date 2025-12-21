// GoldenReferenceGenerator.swift
// MetaVis Render - Golden reference image generator using LIGM

import Foundation
import Metal

/// Generates golden reference images for shader testing using LIGM
public class GoldenReferenceGenerator {
    private let ligm: LIGM
    private let basePath: String
    
    public init(device: MTLDevice, basePath: String = "Tests/MetaVisRenderTests/References") throws {
        self.ligm = try LIGM(device: device)
        self.basePath = basePath
    }
    
    /// Generate all core reference images for ACES testing
    public func generateACESReferences() async throws {
        print("🎨 Generating ACES reference images...")
        
        let acesDir = "\(basePath)/aces"
        try FileManager.default.createDirectory(atPath: acesDir, withIntermediateDirectories: true)
        
        // 1. Neutral white - use uniform noise
        let white = try await ligm.generateNoise(width: 128, height: 128, seed: 42, frequency: 0.0, amplitude: 1.0)
        try ligm.save(response: white, to: URL(fileURLWithPath: "\(acesDir)/neutral_white_128x128.png"))
        print("  ✓ Neutral white")
        
        // 2. Linear gradient
        let gradient = try await ligm.generateGradient(width: 256, height: 256, start: SIMD3<Float>(0,0,0), end: SIMD3<Float>(1,1,1))
        try ligm.save(response: gradient, to: URL(fileURLWithPath: "\(acesDir)/gradient_linear_256x256.png"))
        print("  ✓ Linear gradient")
        
        // 3. Gray ramp (same as gradient)
        try ligm.save(response: gradient, to: URL(fileURLWithPath: "\(acesDir)/gray_ramp_256x256.png"))
        print("  ✓ Gray ramp")
        
        // 4. Noise pattern for primaries test
        let noise = try await ligm.generateNoise(width: 128, height: 128, seed: 42, frequency: 4.0, amplitude: 1.0)
        try ligm.save(response: noise, to: URL(fileURLWithPath: "\(acesDir)/primaries_128x128.png"))
        print("  ✓ Primary colors pattern")
        
        // 5. HDR gradient (scaled amplitude)
        let request = LIGMRequest(
            id: UUID().uuidString,
            width: 256,
            height: 256,
            seed: 42,
            mode: .gradient,
            parameters: ["amplitude": 10.0],
            colorSpace: .acesCg
        )
        let hdrGrad = try await ligm.generate(request: request)
        try ligm.save(response: hdrGrad, to: URL(fileURLWithPath: "\(acesDir)/hdr_gradient_256x256.png"))
        print("  ✓ HDR gradient")
        
        print("✅ ACES references complete")
    }
    
    /// Generate background shader references
    public func generateBackgroundReferences() async throws {
        print("🎨 Generating background reference images...")
        
        let bgDir = "\(basePath)/backgrounds"
        try FileManager.default.createDirectory(atPath: bgDir, withIntermediateDirectories: true)
        
        // Solid colors - use zero-frequency noise
        let red = try await ligm.generateNoise(width: 128, height: 128, seed: 42, frequency: 0.0, amplitude: 1.0)
        try ligm.save(response: red, to: URL(fileURLWithPath: "\(bgDir)/solid_red_128x128.png"))
        
        let green = try await ligm.generateNoise(width: 128, height: 128, seed: 43, frequency: 0.0, amplitude: 1.0)
        try ligm.save(response: green, to: URL(fileURLWithPath: "\(bgDir)/solid_green_128x128.png"))
        
        let blue = try await ligm.generateNoise(width: 128, height: 128, seed: 44, frequency: 0.0, amplitude: 1.0)
        try ligm.save(response: blue, to: URL(fileURLWithPath: "\(bgDir)/solid_blue_128x128.png"))
        
        print("  ✓ Solid colors")
        
        // Noise pattern for starfield
        let starfield = try await ligm.generateNoise(width: 512, height: 512, seed: 42, frequency: 8.0, amplitude: 1.0)
        try ligm.save(response: starfield, to: URL(fileURLWithPath: "\(bgDir)/noise_seed42_512x512.png"))
        print("  ✓ Starfield pattern")
        
        print("✅ Background references complete")
    }
    
    /// Generate procedural shader references
    public func generateProceduralReferences() async throws {
        print("🎨 Generating procedural reference images...")
        
        let procDir = "\(basePath)/procedural"
        try FileManager.default.createDirectory(atPath: procDir, withIntermediateDirectories: true)
        
        // FBM pattern
        let fbm = try await ligm.generateFBM(width: 512, height: 512, seed: 42, octaves: 4, lacunarity: 2.0, gain: 0.5)
        try ligm.save(response: fbm, to: URL(fileURLWithPath: "\(procDir)/fbm_seed42_octaves4_512x512.png"))
        print("  ✓ FBM pattern")
        
        // Domain warp
        let warp = LIGMRequest(
            id: UUID().uuidString,
            width: 512,
            height: 512,
            seed: 42,
            mode: .domainWarp,
            parameters: [
                "warpAmount": 0.3,
                "octaves": Float(3),
                "scale": 2.0
            ],
            colorSpace: .acesCg
        )
        let warpResponse = try await ligm.generate(request: warp)
        try ligm.save(response: warpResponse, to: URL(fileURLWithPath: "\(procDir)/warp_seed42_512x512.png"))
        print("  ✓ Domain warp")
        
        print("✅ Procedural references complete")
    }
    
    /// Generate all reference images
    public func generateAll() async throws {
        print("🚀 Starting golden reference generation...")
        print("Using LIGM with ACEScg color space")
        print("")
        
        try await generateACESReferences()
        try await generateBackgroundReferences()
        try await generateProceduralReferences()
        
        print("")
        print("✅ All golden references generated successfully")
        print("📁 Location: \(basePath)")
    }
}
