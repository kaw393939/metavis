// ClipCommand.swift
// MetaVisCLI
//
// Sprint 03: Clip analysis commands
// Shot classification, motion analysis, and quality assessment

import Foundation
import ArgumentParser
import MetaVisRender

struct ClipAnalyze: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clip-analyze",
        abstract: "Analyze a video clip for shot type and quality",
        discussion: """
            Performs shot classification, motion analysis, and quality assessment.
            
            Examples:
              metavis clip-analyze video.mov
              metavis clip-analyze --json footage.mp4
              metavis clip-analyze --detailed interview.mov
            """
    )
    
    @Argument(help: "Path to the video file")
    var input: String
    
    @Option(name: .shortAndLong, help: "Output path for analysis")
    var output: String?
    
    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false
    
    @Flag(name: .long, help: "Detailed analysis (more samples)")
    var detailed: Bool = false
    
    @Flag(name: .long, help: "Fast analysis (fewer samples)")
    var fast: Bool = false
    
    @Flag(name: .long, help: "Show quality flags only")
    var quality: Bool = false
    
    mutating func run() async throws {
        let inputURL = URL(fileURLWithPath: input)
        
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            print("Error: File not found: \(input)")
            throw ExitCode.failure
        }
        
        if !json {
            print("Analyzing \(inputURL.lastPathComponent)...")
        }
        
        let config: ClipAnalyzer.Config
        if detailed {
            config = .detailed
        } else if fast {
            config = .fast
        } else {
            config = .default
        }
        
        let analyzer = ClipAnalyzer(config: config)
        let result = try await analyzer.analyze(url: inputURL)
        
        if json {
            let output = ClipAnalysisOutput(
                duration: result.duration,
                frameCount: result.frameCount,
                shotType: result.shotType.type.rawValue,
                shotConfidence: result.shotType.confidence,
                shotSubType: result.shotType.subType,
                motion: MotionOutput(
                    intensity: result.motionSummary.overallIntensity,
                    direction: result.motionSummary.dominantDirection?.rawValue,
                    cameraMotion: result.motionSummary.cameraMotion.rawValue,
                    stability: result.motionSummary.stabilityScore
                ),
                color: ColorOutput(
                    dominantColor: [
                        result.colorAnalysis.dominantColor.x,
                        result.colorAnalysis.dominantColor.y,
                        result.colorAnalysis.dominantColor.z
                    ],
                    temperature: result.colorAnalysis.colorTemperature.rawValue,
                    saturation: result.colorAnalysis.saturation,
                    colorCast: result.colorAnalysis.colorCast
                ),
                qualityFlags: result.qualityFlags.map { flag in
                    QualityFlagOutput(
                        category: flag.category.rawValue,
                        severity: flag.severity.rawValue,
                        description: flag.description,
                        recommendation: flag.recommendation
                    )
                }
            )
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(output)
            
            if let outputPath = self.output {
                try data.write(to: URL(fileURLWithPath: outputPath))
                print("Analysis written to \(outputPath)")
            } else if let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            }
        } else {
            printHumanReadable(result)
        }
    }
    
    private func printHumanReadable(_ result: ClipAnalysisResult) {
        print("")
        print("CLIP ANALYSIS")
        print("=============")
        print("Duration: \(String(format: "%.1f", result.duration))s")
        print("Frames Analyzed: \(result.frameCount)")
        print("")
        
        if !quality {
            // Shot Classification
            print("SHOT TYPE:")
            print("  Type: \(result.shotType.type.rawValue)")
            if let subType = result.shotType.subType {
                print("  Sub-type: \(subType)")
            }
            print("  Confidence: \(pct(result.shotType.confidence))")
            print("")
            
            // Motion Analysis
            print("MOTION:")
            print("  Intensity: \(pct(result.motionSummary.overallIntensity))")
            if let direction = result.motionSummary.dominantDirection {
                print("  Direction: \(direction.rawValue)")
            }
            print("  Camera Motion: \(result.motionSummary.cameraMotion.rawValue)")
            print("  Stability: \(pct(result.motionSummary.stabilityScore))")
            print("")
            
            // Color Analysis
            print("COLOR:")
            let c = result.colorAnalysis.dominantColor
            print("  Dominant: R=\(f(c.x)) G=\(f(c.y)) B=\(f(c.z))")
            print("  Temperature: \(result.colorAnalysis.colorTemperature.rawValue)")
            print("  Saturation: \(pct(result.colorAnalysis.saturation))")
            if let cast = result.colorAnalysis.colorCast {
                print("  Color Cast: \(cast)")
            }
            print("")
        }
        
        // Quality Flags
        print("QUALITY FLAGS:")
        if result.qualityFlags.isEmpty {
            print("  ✓ No issues detected")
        } else {
            for flag in result.qualityFlags {
                let icon = flag.severity == .critical ? "✗" : flag.severity == .warning ? "⚠" : "ℹ"
                print("  \(icon) [\(flag.severity.rawValue.uppercased())] \(flag.description)")
                print("    → \(flag.recommendation)")
            }
        }
    }
    
    private func f(_ value: Float) -> String {
        String(format: "%.2f", value)
    }
    
    private func pct(_ value: Float) -> String {
        String(format: "%.0f%%", value * 100)
    }
}

// MARK: - Output Types

private struct ClipAnalysisOutput: Codable {
    let duration: Double
    let frameCount: Int
    let shotType: String
    let shotConfidence: Float
    let shotSubType: String?
    let motion: MotionOutput
    let color: ColorOutput
    let qualityFlags: [QualityFlagOutput]
}

private struct MotionOutput: Codable {
    let intensity: Float
    let direction: String?
    let cameraMotion: String
    let stability: Float
}

private struct ColorOutput: Codable {
    let dominantColor: [Float]
    let temperature: String
    let saturation: Float
    let colorCast: String?
}

private struct QualityFlagOutput: Codable {
    let category: String
    let severity: String
    let description: String
    let recommendation: String
}
