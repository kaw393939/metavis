// DraftManifestCommand.swift
// MetaVisCLI
//
// CLI command for generating AI-assisted render manifests

import ArgumentParser
import Foundation
import MetaVisRender

struct DraftManifestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "draft-manifest",
        abstract: "Generate an AI-assisted render manifest from video analysis"
    )
    
    @Argument(help: "Path to video file")
    var input: String
    
    @Option(name: .shortAndLong, help: "Output path for manifest JSON")
    var output: String?
    
    @Option(name: .long, help: "Template type: interview, presentation, documentary, social, minimal")
    var template: String = "interview"
    
    @Option(name: .long, help: "Title text for the video")
    var title: String?
    
    @Option(name: .long, help: "Lower third text (format: 'Name|Title')")
    var lowerThird: String?
    
    @Flag(name: .long, help: "Show detailed suggestions")
    var verbose: Bool = false
    
    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false
    
    mutating func run() async throws {
        let inputURL = URL(fileURLWithPath: input)
        
        guard FileManager.default.fileExists(atPath: input) else {
            throw ValidationError("File not found: \(input)")
        }
        
        if !json {
            print("Generating draft manifest from: \(inputURL.lastPathComponent)")
        }
        
        // Determine template type
        let manifestTemplate = parseTemplate(template)
        
        // Create generator
        let generator = DraftManifestGenerator()
        
        // Build text suggestions
        var textSuggestions: [DraftTextSuggestion] = []
        
        if let titleText = title {
            textSuggestions.append(DraftTextSuggestion(
                type: .title,
                content: titleText
            ))
        }
        
        if let lowerThirdText = lowerThird {
            let parts = lowerThirdText.split(separator: "|")
            let name = String(parts.first ?? "")
            textSuggestions.append(DraftTextSuggestion(
                type: .lowerThird,
                content: name
            ))
        }
        
        // Analyze video
        if !json {
            print("Analyzing video...")
        }
        
        let analyzer = ClipAnalyzer()
        let analysis = try await analyzer.analyze(url: inputURL)
        
        // Create draft analysis from clip analysis
        let draftAnalysis = DraftClipAnalysis(
            duration: Float(analysis.duration),
            fps: 30.0,  // Default FPS
            resolution: SIMD2<Int>(1920, 1080),  // Default resolution
            speakers: [],
            faces: []
        )
        
        // Generate draft manifest
        let draftManifest = try await generator.generate(
            from: draftAnalysis,
            template: manifestTemplate,
            textSuggestions: textSuggestions
        )
        
        // Output
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(draftManifest.manifest)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            }
        } else {
            printManifestSummary(draftManifest)
        }
        
        // Save to file if output specified
        if let outputPath = output {
            let outputURL = URL(fileURLWithPath: outputPath)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(draftManifest.manifest)
            try data.write(to: outputURL)
            print("\n✅ Manifest saved to: \(outputPath)")
        }
    }
    
    private func parseTemplate(_ template: String) -> DraftTemplate {
        switch template.lowercased() {
        case "interview":
            return .interview
        case "presentation":
            return .presentation
        case "documentary":
            return .documentary
        case "social":
            return .social
        case "minimal":
            return .minimal
        default:
            return .interview
        }
    }
    
    private func printManifestSummary(_ draft: DraftManifest) {
        print("""
        
        ┌─────────────────────────────────────────────────────────────┐
        │ DRAFT MANIFEST                                              │
        ├─────────────────────────────────────────────────────────────┤
        """)
        
        print("│ Template        │ \(draft.template.rawValue.padding(toLength: 43, withPad: " ", startingAt: 0)) │")
        print("│ Resolution      │ \(formatResolution(draft.manifest.metadata.resolution).padding(toLength: 43, withPad: " ", startingAt: 0)) │")
        print("│ FPS             │ \(String(format: "%.2f", draft.manifest.metadata.fps).padding(toLength: 43, withPad: " ", startingAt: 0)) │")
        print("│ Elements        │ \(String(draft.manifest.elements?.count ?? 0).padding(toLength: 43, withPad: " ", startingAt: 0)) │")
        print("│ Confidence      │ \(String(format: "%.1f%%", draft.confidence * 100).padding(toLength: 43, withPad: " ", startingAt: 0)) │")
        
        if let elements = draft.manifest.elements, !elements.isEmpty {
            print("├─────────────────────────────────────────────────────────────┤")
            print("│ ELEMENTS                                                    │")
            
            for (index, _) in elements.enumerated() {
                let elementStr = "Element \(index + 1)"
                print("│   • \(elementStr.padding(toLength: 55, withPad: " ", startingAt: 0)) │")
            }
        }
        
        if !draft.suggestions.isEmpty {
            print("├─────────────────────────────────────────────────────────────┤")
            print("│ AI SUGGESTIONS                                              │")
            
            for suggestion in draft.suggestions.prefix(5) {
                let reason = suggestion.reason.prefix(55)
                print("│   • \(String(reason).padding(toLength: 55, withPad: " ", startingAt: 0)) │")
            }
        }
        
        if !draft.reviewRequired.isEmpty {
            print("├─────────────────────────────────────────────────────────────┤")
            print("│ ⚠️  REVIEW REQUIRED                                          │")
            
            for item in draft.reviewRequired {
                let text = item.prefix(55)
                print("│   • \(String(text).padding(toLength: 55, withPad: " ", startingAt: 0)) │")
            }
        }
        
        print("└─────────────────────────────────────────────────────────────┘")
    }
    
    private func formatResolution(_ resolution: SIMD2<Int>) -> String {
        return "\(resolution.x)×\(resolution.y)"
    }
}
