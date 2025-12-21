// DocumentCommand.swift
// MetaVisCLI
//
// Sprint 03: Document analysis commands
// Probes PDF documents and performs OCR analysis

import Foundation
import ArgumentParser
import MetaVisRender

struct DocumentProbeCmd: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doc-probe",
        abstract: "Probe a PDF document for metadata",
        discussion: """
            Extracts metadata from a PDF document without rendering pages.
            
            Examples:
              metavis doc-probe document.pdf
              metavis doc-probe --json presentation.pdf
            """
    )
    
    @Argument(help: "Path to the PDF file")
    var input: String
    
    @Option(name: .shortAndLong, help: "Output path for results")
    var output: String?
    
    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false
    
    mutating func run() async throws {
        let inputURL = URL(fileURLWithPath: input)
        
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            print("Error: File not found: \(input)")
            throw ExitCode.failure
        }
        
        let probe = DocumentProbe()
        let profile = try await probe.probe(inputURL)
        
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(profile)
            
            if let outputPath = output {
                try data.write(to: URL(fileURLWithPath: outputPath))
                print("Results written to \(outputPath)")
            } else if let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            }
        } else {
            printProfile(profile)
        }
    }
    
    private func printProfile(_ profile: DocumentProfile) {
        print("Document: \(profile.filename)")
        print("Pages: \(profile.pageCount)")
        if let title = profile.title {
            print("Title: \(title)")
        }
        if let author = profile.author {
            print("Author: \(author)")
        }
        if let subject = profile.subject {
            print("Subject: \(subject)")
        }
        if let creator = profile.creator {
            print("Creator: \(creator)")
        }
        if let created = profile.creationDate {
            print("Created: \(created)")
        }
        print("")
        print("Page Sizes:")
        for (index, size) in profile.pageSizes.prefix(5).enumerated() {
            print("  Page \(index + 1): \(Int(size.width))×\(Int(size.height))")
        }
        if profile.pageSizes.count > 5 {
            print("  ... and \(profile.pageSizes.count - 5) more pages")
        }
        print("")
        print("Encrypted: \(profile.isEncrypted ? "Yes" : "No")")
        if profile.hasExtractableText {
            print("Has Text Layer: Yes")
        }
    }
}

struct DocumentAnalyzeCmd: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doc-analyze",
        abstract: "Analyze a PDF document with OCR",
        discussion: """
            Performs OCR and layout analysis on PDF pages.
            
            Examples:
              metavis doc-analyze document.pdf
              metavis doc-analyze --pages 1-5 presentation.pdf
              metavis doc-analyze --json --output analysis.json document.pdf
            """
    )
    
    @Argument(help: "Path to the PDF file")
    var input: String
    
    @Option(name: .shortAndLong, help: "Output path for results")
    var output: String?
    
    @Option(name: .long, help: "Pages to analyze (e.g., '1-5' or '1,3,5')")
    var pages: String?
    
    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false
    
    @Flag(name: .long, help: "Include extracted text")
    var text: Bool = false
    
    mutating func run() async throws {
        let inputURL = URL(fileURLWithPath: input)
        
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            print("Error: File not found: \(input)")
            throw ExitCode.failure
        }
        
        if !json {
            print("Analyzing \(inputURL.lastPathComponent)...")
        }
        
        let engine = DocumentAnalysisEngine()
        let analysis = try await engine.analyze(inputURL)
        
        if json {
            // Create a simpler JSON-friendly structure
            let result = DocumentAnalysisOutput(
                pageCount: analysis.pages.count,
                totalTextRegions: analysis.pages.flatMap { $0.textBlocks }.count,
                hasText: !analysis.pages.allSatisfy { $0.textContent.isEmpty },
                pages: analysis.pages.enumerated().map { index, page in
                    PageOutput(
                        pageNumber: index + 1,
                        textRegionCount: page.textBlocks.count,
                        extractedText: text ? page.textContent : nil
                    )
                }
            )
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(result)
            
            if let outputPath = output {
                try data.write(to: URL(fileURLWithPath: outputPath))
                print("Results written to \(outputPath)")
            } else if let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            }
        } else {
            print("")
            print("Pages analyzed: \(analysis.pages.count)")
            
            for (index, page) in analysis.pages.enumerated() {
                print("")
                print("Page \(index + 1):")
                print("  Text blocks: \(page.textBlocks.count)")
                
                if text && !page.textContent.isEmpty {
                    let preview = String(page.textContent.prefix(200))
                    print("  Text preview: \(preview)...")
                }
            }
        }
    }
}

// MARK: - Output Types

private struct DocumentAnalysisOutput: Codable {
    let pageCount: Int
    let totalTextRegions: Int
    let hasText: Bool
    let pages: [PageOutput]
}

private struct PageOutput: Codable {
    let pageNumber: Int
    let textRegionCount: Int
    let extractedText: String?
}
