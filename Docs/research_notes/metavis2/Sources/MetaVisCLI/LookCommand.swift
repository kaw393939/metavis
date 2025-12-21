// LookCommand.swift
// MetaVisCLI
//
// Sprint 03: Look analysis and LUT commands
// Extracts CDL from footage and analyzes LUT files

import Foundation
import ArgumentParser
import MetaVisRender

struct LookExtract: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "look-extract",
        abstract: "Extract color look (CDL) from footage",
        discussion: """
            Analyzes video footage to extract Color Decision List parameters.
            
            Examples:
              metavis look-extract video.mov
              metavis look-extract --json footage.mp4
              metavis look-extract --output look.json interview.mov
            """
    )
    
    @Argument(help: "Path to the video file")
    var input: String
    
    @Option(name: .shortAndLong, help: "Output path for CDL")
    var output: String?
    
    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false
    
    @Flag(name: .long, help: "Detailed analysis mode")
    var detailed: Bool = false
    
    mutating func run() async throws {
        let inputURL = URL(fileURLWithPath: input)
        
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            print("Error: File not found: \(input)")
            throw ExitCode.failure
        }
        
        if !json {
            print("Extracting look from \(inputURL.lastPathComponent)...")
        }
        
        let config = detailed ?
            LookAnalysisEngine.Config.detailed :
            LookAnalysisEngine.Config.default
        let engine = LookAnalysisEngine(config: config)
        
        let look = try await engine.extractLook(from: inputURL)
        
        if json {
            let result = LookOutput(
                slope: [look.cdl.slope.x, look.cdl.slope.y, look.cdl.slope.z],
                offset: [look.cdl.offset.x, look.cdl.offset.y, look.cdl.offset.z],
                power: [look.cdl.power.x, look.cdl.power.y, look.cdl.power.z],
                saturation: look.cdl.saturation,
                colorCast: look.colorCast.rawValue,
                contrast: look.contrast,
                exposure: look.exposure
            )
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(result)
            
            if let outputPath = output {
                try data.write(to: URL(fileURLWithPath: outputPath))
                print("CDL written to \(outputPath)")
            } else if let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            }
        } else {
            print("")
            print("CDL Parameters:")
            print("  Slope:      R=\(f(look.cdl.slope.x)) G=\(f(look.cdl.slope.y)) B=\(f(look.cdl.slope.z))")
            print("  Offset:     R=\(f(look.cdl.offset.x)) G=\(f(look.cdl.offset.y)) B=\(f(look.cdl.offset.z))")
            print("  Power:      R=\(f(look.cdl.power.x)) G=\(f(look.cdl.power.y)) B=\(f(look.cdl.power.z))")
            print("  Saturation: \(f(look.cdl.saturation))")
            print("")
            print("Look Analysis:")
            print("  Color Cast: \(look.colorCast.rawValue)")
            print("  Contrast:   \(f(look.contrast))")
            print("  Exposure:   \(f(look.exposure))")
            
            if let skinHue = look.skinToneHue {
                print("  Skin Hue:   \(f(skinHue))")
            }
        }
    }
    
    private func f(_ value: Float) -> String {
        String(format: "%.3f", value)
    }
}

struct LUTAnalyze: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lut-analyze",
        abstract: "Analyze a LUT file",
        discussion: """
            Analyzes characteristics of a .cube LUT file.
            
            Examples:
              metavis lut-analyze cinematic.cube
              metavis lut-analyze --json film_look.cube
            """
    )
    
    @Argument(help: "Path to the LUT file (.cube)")
    var input: String
    
    @Option(name: .shortAndLong, help: "Output path for analysis")
    var output: String?
    
    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false
    
    mutating func run() async throws {
        let inputURL = URL(fileURLWithPath: input)
        
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            print("Error: File not found: \(input)")
            throw ExitCode.failure
        }
        
        if !json {
            print("Analyzing LUT: \(inputURL.lastPathComponent)...")
        }
        
        let engine = LookAnalysisEngine()
        let analysis = try await engine.analyzeLUT(at: inputURL)
        
        if json {
            let result = LUTAnalysisOutput(
                filename: inputURL.lastPathComponent,
                size: analysis.size,
                contrast: analysis.contrast,
                saturationChange: analysis.saturationChange,
                colorShift: [analysis.colorShift.x, analysis.colorShift.y, analysis.colorShift.z],
                isNearIdentity: analysis.isNearIdentity,
                approximateCDL: CDLOutput(
                    slope: [analysis.approximateCDL.slope.x, analysis.approximateCDL.slope.y, analysis.approximateCDL.slope.z],
                    offset: [analysis.approximateCDL.offset.x, analysis.approximateCDL.offset.y, analysis.approximateCDL.offset.z],
                    power: [analysis.approximateCDL.power.x, analysis.approximateCDL.power.y, analysis.approximateCDL.power.z],
                    saturation: analysis.approximateCDL.saturation
                )
            )
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(result)
            
            if let outputPath = output {
                try data.write(to: URL(fileURLWithPath: outputPath))
                print("Analysis written to \(outputPath)")
            } else if let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            }
        } else {
            print("")
            print("LUT: \(inputURL.lastPathComponent)")
            print("Size: \(analysis.size)×\(analysis.size)×\(analysis.size)")
            print("")
            print("Characteristics:")
            print("  Contrast Change:   \(f(analysis.contrast))x")
            print("  Saturation Change: \(f(analysis.saturationChange))x")
            print("  Color Shift:       R=\(f(analysis.colorShift.x)) G=\(f(analysis.colorShift.y)) B=\(f(analysis.colorShift.z))")
            print("  Near Identity:     \(analysis.isNearIdentity ? "Yes" : "No")")
            print("")
            print("Approximate CDL:")
            print("  Slope:      R=\(f(analysis.approximateCDL.slope.x)) G=\(f(analysis.approximateCDL.slope.y)) B=\(f(analysis.approximateCDL.slope.z))")
            print("  Offset:     R=\(f(analysis.approximateCDL.offset.x)) G=\(f(analysis.approximateCDL.offset.y)) B=\(f(analysis.approximateCDL.offset.z))")
            print("  Power:      R=\(f(analysis.approximateCDL.power.x)) G=\(f(analysis.approximateCDL.power.y)) B=\(f(analysis.approximateCDL.power.z))")
            print("  Saturation: \(f(analysis.approximateCDL.saturation))")
        }
    }
    
    private func f(_ value: Float) -> String {
        String(format: "%.3f", value)
    }
}

// MARK: - Output Types

private struct LookOutput: Codable {
    let slope: [Float]
    let offset: [Float]
    let power: [Float]
    let saturation: Float
    let colorCast: String
    let contrast: Float
    let exposure: Float
}

private struct LUTAnalysisOutput: Codable {
    let filename: String
    let size: Int
    let contrast: Float
    let saturationChange: Float
    let colorShift: [Float]
    let isNearIdentity: Bool
    let approximateCDL: CDLOutput
}

private struct CDLOutput: Codable {
    let slope: [Float]
    let offset: [Float]
    let power: [Float]
    let saturation: Float
}
