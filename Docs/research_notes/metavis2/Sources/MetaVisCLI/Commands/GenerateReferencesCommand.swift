// GenerateReferencesCommand.swift
// MetaVis CLI - Generate golden reference images for testing

import Foundation
import ArgumentParser
import MetaVisRender
import Metal

struct GenerateReferencesCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "generate-references",
        abstract: "Generate golden reference images for shader testing using LIGM",
        discussion: """
        Generates deterministic reference images in ACEScg color space for validating
        shader tests. Images are saved to Tests/MetaVisRenderTests/References/.
        
        Reference Categories:
        - ACES: Neutral whites, gradients, primaries for color pipeline testing
        - Backgrounds: Solid colors, noise patterns for background shader testing
        - Procedural: FBM, domain warp for procedural shader testing
        """
    )
    
    @Option(name: .long, help: "Output directory for reference images")
    var outputPath: String = "Tests/MetaVisRenderTests/References"
    
    @Flag(name: .long, help: "Generate only ACES references")
    var acesOnly: Bool = false
    
    @Flag(name: .long, help: "Generate only background references")
    var backgroundsOnly: Bool = false
    
    @Flag(name: .long, help: "Generate only procedural references")
    var proceduralOnly: Bool = false
    
    @Flag(name: .long, help: "Show verbose output")
    var verbose: Bool = false
    
    func run() async throws {
        print("🚀 Golden Reference Generator")
        print(String(repeating: "=", count: 60))
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ValidationError("Metal device not available. Golden references require Metal support.")
        }
        
        if verbose {
            print("✓ Metal device: \(device.name)")
            print("✓ Output path: \(outputPath)")
            print("")
        }
        
        let generator = try GoldenReferenceGenerator(device: device, basePath: outputPath)
        
        // Determine what to generate
        let generateAll = !acesOnly && !backgroundsOnly && !proceduralOnly
        
        if generateAll || acesOnly {
            try await generator.generateACESReferences()
        }
        
        if generateAll || backgroundsOnly {
            try await generator.generateBackgroundReferences()
        }
        
        if generateAll || proceduralOnly {
            try await generator.generateProceduralReferences()
        }
        
        print("")
        print("✅ Golden reference generation complete!")
        print("📁 Location: \(outputPath)")
        
        // List generated files
        if verbose {
            print("")
            print("Generated files:")
            let fileManager = FileManager.default
            
            for category in ["aces", "backgrounds", "procedural"] {
                let dirPath = "\(outputPath)/\(category)"
                if let files = try? fileManager.contentsOfDirectory(atPath: dirPath) {
                    for file in files.sorted() where file.hasSuffix(".png") {
                        print("  • \(category)/\(file)")
                    }
                }
            }
        }
    }
}
