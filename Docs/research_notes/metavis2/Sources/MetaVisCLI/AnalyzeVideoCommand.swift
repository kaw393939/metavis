// AnalyzeVideoCommand.swift
// Sprint D Week 2: CLI integration for ColorAnalyzer, MotionAnalyzer, QualityAnalyzer
// Provides AI agents with programmatic access to render quality analysis

import Foundation
import ArgumentParser
import MetaVisRender
import AVFoundation

struct AnalyzeVideo: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "analyze-video",
        abstract: "Analyze video quality using ColorAnalyzer, MotionAnalyzer, and QualityAnalyzer",
        discussion: """
        Provides comprehensive video analysis for AI-powered quality validation.
        
        Analysis Types:
        - color: Color accuracy, banding, clipping, neutral preservation (ΔE metrics)
        - motion: Optical flow smoothness, jitter, stutter detection
        - quality: PSNR, SSIM, sharpness, noise, contrast measurements
        - gemini: AI-powered qualitative analysis using Gemini 2.0 Flash
        - comprehensive: All quantitative analysis types combined
        
        Output Formats:
        - Human-readable text (default)
        - JSON for agent consumption (--json)
        - Structured grades (A+, A, B, C, F)
        
        Examples:
        metavis analyze-video --type color video.mp4
        metavis analyze-video --type gemini video.mp4 --json
        metavis analyze-video --type comprehensive video.mp4 --json
        metavis analyze-video --type quality video.mp4 --reference reference.mp4 --json
        """
    )
    
    // MARK: - Arguments
    
    @Argument(help: "Path to the video file to analyze")
    var videoPath: String
    
    // MARK: - Options
    
    @Option(name: .shortAndLong, help: "Analysis type: color, motion, quality, gemini, comprehensive (default: comprehensive)")
    var type: AnalysisType = .comprehensive
    
    @Option(name: .shortAndLong, help: "Reference video for comparison (optional, used with color/quality analysis)")
    var reference: String?
    
    @Flag(name: .long, help: "Output results as JSON for agent consumption")
    var json: Bool = false
    
    @Flag(name: .long, help: "Verbose output with detailed metrics")
    var verbose: Bool = false
    
    @Option(name: .shortAndLong, help: "Output path to save JSON results to file")
    var output: String?
    
    // MARK: - Analysis Types
    
    enum AnalysisType: String, ExpressibleByArgument {
        case color
        case motion
        case quality
        case gemini
        case comprehensive
    }
    
    // MARK: - Execution
    
    mutating func run() async throws {
        let videoURL = URL(fileURLWithPath: videoPath)
        
        // Validate video file exists
        guard FileManager.default.fileExists(atPath: videoPath) else {
            print("❌ Error: Video file not found: \(videoPath)")
            throw ExitCode.failure
        }
        
        // Validate reference if provided
        var referenceURL: URL? = nil
        if let refPath = reference {
            guard FileManager.default.fileExists(atPath: refPath) else {
                print("❌ Error: Reference video not found: \(refPath)")
                throw ExitCode.failure
            }
            referenceURL = URL(fileURLWithPath: refPath)
        }
        
        // Print header
        if !json {
            print("🎬 MetaVis Video Analysis")
            print("═══════════════════════════════════════════════════")
            print("Video: \(videoPath)")
            if let ref = reference {
                print("Reference: \(ref)")
            }
            print("Analysis Type: \(type.rawValue)")
            print("═══════════════════════════════════════════════════")
            print()
        }
        
        // Run analysis
        var results: [String: Any] = [
            "videoPath": videoPath,
            "analysisType": type.rawValue,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        if let ref = reference {
            results["referencePath"] = ref
        }
        
        switch type {
        case .color:
            try await analyzeColor(videoURL: videoURL, referenceURL: referenceURL, results: &results)
        case .motion:
            try await analyzeMotion(videoURL: videoURL, results: &results)
        case .quality:
            try await analyzeQuality(videoURL: videoURL, results: &results)
        case .gemini:
            try await analyzeGemini(videoURL: videoURL, results: &results)
        case .comprehensive:
            try await analyzeComprehensive(videoURL: videoURL, referenceURL: referenceURL, results: &results)
        }
        
        // Output results
        if json {
            try outputJSON(results: results)
        }
        
        if !json {
            print()
            print("═══════════════════════════════════════════════════")
            print("✅ Analysis complete")
        }
    }
    
    // MARK: - Color Analysis
    
    private func analyzeColor(videoURL: URL, referenceURL: URL?, results: inout [String: Any]) async throws {
        if !json {
            print("🎨 Analyzing Color...")
        }
        
        let analyzer = ColorAnalyzer()
        let colorResult = try await analyzer.analyzeColorAccuracy(videoURL: videoURL, referenceURL: referenceURL)
        
        if json {
            // Map issues to JSON-friendly format
            let issuesJSON = colorResult.issues.map { issue -> [String: Any] in
                return [
                    "type": issue.type,
                    "severity": issue.severity,
                    "description": issue.description,
                    "frameNumber": issue.frameNumber ?? -1
                ]
            }
            
            // Map frames if verbose mode
            var framesJSON: [[String: Any]]? = nil
            if verbose {
                framesJSON = colorResult.frames.map { frame in
                    return [
                        "accuracy": frame.accuracy,
                        "neutralAccuracy": frame.neutralAccuracy,
                        "hasBanding": frame.hasBanding,
                        "hasClipping": frame.hasClipping,
                        "gamutCoverage": frame.gamutCoverage,
                        "colorSpace": frame.colorSpace
                    ]
                }
            }
            
            results["color"] = [
                "grade": colorResult.grade,
                "averageAccuracy": colorResult.averageAccuracy,
                "frameCount": colorResult.frames.count,
                "issueCount": colorResult.issues.count,
                "issues": issuesJSON,
                "frames": framesJSON as Any
            ]
        } else {
            printColorResults(colorResult)
        }
    }
    
    // MARK: - Motion Analysis
    
    private func analyzeMotion(videoURL: URL, results: inout [String: Any]) async throws {
        if !json {
            print("🎯 Analyzing Motion...")
        }
        
        let analyzer = MotionAnalyzer()
        let motionResult = try await analyzer.analyzeMotion(videoURL: videoURL)
        
        if json {
            results["motion"] = [
                "grade": motionResult.grade,
                "smoothness": motionResult.smoothness,
                "jitter": motionResult.jitter,
                "stutter": motionResult.stutter
            ]
        } else {
            printMotionResults(motionResult)
        }
    }
    
    // MARK: - Quality Analysis
    
    private func analyzeQuality(videoURL: URL, results: inout [String: Any]) async throws {
        if !json {
            print("⭐ Analyzing Quality...")
        }
        
        let analyzer = QualityAnalyzer()
        let qualityResult = try await analyzer.analyzeQuality(videoURL: videoURL)
        
        if json {
            results["quality"] = [
                "grade": qualityResult.grade,
                "overallScore": qualityResult.overallScore,
                "sharpness": qualityResult.sharpness,
                "noise": qualityResult.noise,
                "contrast": qualityResult.contrast
            ]
        } else {
            printQualityResults(qualityResult)
        }
    }
    
    // MARK: - Gemini Analysis
    
    private func analyzeGemini(videoURL: URL, results: inout [String: Any]) async throws {
        if !json {
            print("🤖 Analyzing with Gemini 2.0 Flash...")
        }
        
        let analyzer = try GeminiAnalyzer()
        let geminiResult = try await analyzer.analyzeVideo(
            videoURL: videoURL,
            preset: .comprehensive,
            frameCount: 5
        )
        
        if json {
            results["gemini"] = [
                "preset": geminiResult.preset,
                "overallGrade": geminiResult.overallGrade,
                "summary": geminiResult.summary,
                "frameCount": geminiResult.frameAnalyses.count,
                "frames": verbose ? geminiResult.frameAnalyses.map { [
                    "frameIndex": $0.frameIndex,
                    "analysis": $0.analysis,
                    "grade": $0.grade
                ]} : nil
            ]
        } else {
            printGeminiResults(geminiResult)
        }
    }
    
    // MARK: - Comprehensive Analysis
    
    private func analyzeComprehensive(videoURL: URL, referenceURL: URL?, results: inout [String: Any]) async throws {
        if !json {
            print("📊 Running Comprehensive Analysis...")
            print()
        }
        
        // Run all analyzers
        try await analyzeColor(videoURL: videoURL, referenceURL: referenceURL, results: &results)
        if !json { print() }
        
        try await analyzeMotion(videoURL: videoURL, results: &results)
        if !json { print() }
        
        try await analyzeQuality(videoURL: videoURL, results: &results)
        
        // Calculate overall grade
        if json {
            let colorGrade = results["color"] as? [String: Any]
            let motionGrade = results["motion"] as? [String: Any]
            let qualityGrade = results["quality"] as? [String: Any]
            
            let grades = [
                colorGrade?["grade"] as? String,
                motionGrade?["grade"] as? String,
                qualityGrade?["grade"] as? String
            ].compactMap { $0 }
            
            results["overallGrade"] = calculateOverallGrade(grades: grades)
        } else {
            print()
            print("───────────────────────────────────────────────────")
            print("📈 Overall Assessment:")
            // Overall grade will be calculated from individual results
        }
    }
    
    // MARK: - Output Helpers
    
    private func printColorResults(_ result: ColorAnalysisResult) {
        print("  Grade: \(gradeWithEmoji(result.grade))")
        print("  Average Accuracy: \(String(format: "%.2f%%", result.averageAccuracy * 100))")
        print("  Frames Analyzed: \(result.frames.count)")
        print("  Issues Found: \(result.issues.count)")
        
        if !result.issues.isEmpty {
            print()
            print("  Issues:")
            for issue in result.issues.prefix(verbose ? result.issues.count : 5) {
                let severityUpper = issue.severity.uppercased()
                print("    • [\(severityUpper)] \(issue.type): \(issue.description)")
            }
            if result.issues.count > 5 && !verbose {
                let moreCount = result.issues.count - 5
                print("    ... and \(moreCount) more (use --verbose to see all)")
            }
        }
    }
    
    private func printMotionResults(_ result: MotionAnalysisResult) {
        print("  Grade: \(gradeWithEmoji(result.grade))")
        print("  Smoothness: \(String(format: "%.2f", result.smoothness)) (1.0 = perfect)")
        print("  Jitter: \(String(format: "%.3f", result.jitter)) (0 = none)")
        print("  Stutter: \(result.stutter ? "❌ Detected" : "✅ Not detected")")
    }
    
    private func printQualityResults(_ result: QualityAnalysisResult) {
        print("  Grade: \(gradeWithEmoji(result.grade))")
        print("  Overall Score: \(String(format: "%.2f", result.overallScore))")
        print("  Sharpness: \(String(format: "%.3f", result.sharpness))")
        print("  Noise Level: \(String(format: "%.3f", result.noise))")
        print("  Contrast: \(String(format: "%.3f", result.contrast))")
    }
    
    private func printGeminiResults(_ result: GeminiAnalysisResult) {
        print("  Grade: \(gradeWithEmoji(result.overallGrade))")
        print("  Frames Analyzed: \(result.frameAnalyses.count)")
        print("  Summary: \(result.summary)")
        
        if verbose {
            print()
            print("  Frame Details:")
            for frame in result.frameAnalyses {
                print("    Frame \(frame.frameIndex): \(gradeWithEmoji(frame.grade))")
                print("      \(frame.analysis)")
            }
        }
    }
    
    private func gradeWithEmoji(_ grade: String) -> String {
        switch grade {
        case "A+": return "🏆 A+"
        case "A": return "✅ A"
        case "B": return "👍 B"
        case "C": return "⚠️ C"
        case "F": return "❌ F"
        default: return grade
        }
    }
    
    private func calculateOverallGrade(grades: [String]) -> String {
        let gradeValues: [String: Int] = ["A+": 5, "A": 4, "B": 3, "C": 2, "F": 1]
        let values = grades.compactMap { gradeValues[$0] }
        
        guard !values.isEmpty else { return "F" }
        
        let average = Double(values.reduce(0, +)) / Double(values.count)
        
        switch average {
        case 4.5...: return "A+"
        case 3.5..<4.5: return "A"
        case 2.5..<3.5: return "B"
        case 1.5..<2.5: return "C"
        default: return "F"
        }
    }
    
    private func outputJSON(results: [String: Any]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let jsonData = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        
        if let outputPath = output {
            // Write to file
            let outputURL = URL(fileURLWithPath: outputPath)
            try jsonData.write(to: outputURL)
            if verbose {
                print("✅ JSON results written to: \(outputPath)", to: &standardError)
            }
        } else {
            // Write to stdout
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            }
        }
    }
}

// MARK: - Standard Error Output

private var standardError = FileHandle.standardError

extension FileHandle: TextOutputStream {
    public func write(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        self.write(data)
    }
}
