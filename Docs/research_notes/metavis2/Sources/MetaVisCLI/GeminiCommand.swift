// GeminiCommand.swift
// MetaVisCLI
//
// CLI commands for Gemini API integration

import ArgumentParser
import Foundation
import MetaVisRender

struct GeminiCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gemini",
        abstract: "Gemini AI operations (document analysis, video validation)",
        subcommands: [
            UploadFile.self,
            AnalyzePDF.self,
            AnalyzeVideo.self,
            ValidateVideo.self
        ]
    )
}

// MARK: - Upload File

extension GeminiCommand {
    struct UploadFile: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "upload",
            abstract: "Upload a file to Gemini Files API"
        )
        
        @Argument(help: "Path to file to upload")
        var input: String
        
        @Option(name: .long, help: "MIME type (auto-detected if not specified)")
        var mimeType: String?
        
        @Flag(name: .long, help: "Output as JSON")
        var json: Bool = false
        
        mutating func run() async throws {
            let inputURL = URL(fileURLWithPath: input)
            
            guard FileManager.default.fileExists(atPath: inputURL.path) else {
                print("Error: File not found: \(input)")
                throw ExitCode.failure
            }
            
            if !json {
                print("Uploading \(inputURL.lastPathComponent)...")
            }
            
            let client = try GeminiClient()
            let response = try await client.uploadFile(inputURL, mimeType: mimeType)
            
            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(response)
                if let jsonString = String(data: data, encoding: .utf8) {
                    print(jsonString)
                }
            } else {
                print("")
                print("✓ Upload complete")
                print("")
                print("File URI: \(response.file.uri)")
                print("Name: \(response.file.name)")
                print("MIME Type: \(response.file.mimeType)")
                if let size = response.file.sizeBytes {
                    print("Size: \(formatBytes(size))")
                }
                if let expiration = response.file.expirationTime {
                    print("Expires: \(expiration)")
                }
            }
        }
        
        private func formatBytes(_ bytesString: String) -> String {
            guard let bytes = Int64(bytesString) else { return bytesString }
            let kb = Double(bytes) / 1024.0
            let mb = kb / 1024.0
            if mb > 1 {
                return String(format: "%.2f MB", mb)
            } else {
                return String(format: "%.2f KB", kb)
            }
        }
    }
}

// MARK: - Analyze PDF

extension GeminiCommand {
    struct AnalyzePDF: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "analyze-pdf",
            abstract: "Analyze a PDF document with Gemini"
        )
        
        @Argument(help: "Path to PDF file or Gemini file URI")
        var input: String
        
        @Option(name: .long, help: "Custom analysis prompt")
        var prompt: String?
        
        @Option(name: .shortAndLong, help: "Output path for analysis")
        var output: String?
        
        mutating func run() async throws {
            let client = try GeminiClient()
            
            // Check if input is a file URI or local path
            let fileURI: String
            if input.starts(with: "https://generativelanguage.googleapis.com/") {
                fileURI = input
                print("Using provided file URI...")
            } else {
                // Upload file first
                let inputURL = URL(fileURLWithPath: input)
                guard FileManager.default.fileExists(atPath: inputURL.path) else {
                    print("Error: File not found: \(input)")
                    throw ExitCode.failure
                }
                
                print("Uploading \(inputURL.lastPathComponent)...")
                let uploadResponse = try await client.uploadFile(inputURL)
                fileURI = uploadResponse.file.uri
                print("✓ Upload complete")
            }
            
            print("Analyzing document...")
            let analysis = try await client.analyzePDF(fileURI, prompt: prompt)
            
            if let outputPath = output {
                try analysis.write(toFile: outputPath, atomically: true, encoding: .utf8)
                print("✓ Analysis saved to \(outputPath)")
            } else {
                print("")
                print("=== Document Analysis ===")
                print("")
                print(analysis)
            }
        }
    }
}

// MARK: - Analyze Video

extension GeminiCommand {
    struct AnalyzeVideo: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "analyze-video",
            abstract: "Analyze a video file with Gemini"
        )
        
        @Argument(help: "Path to video file or Gemini file URI")
        var input: String
        
        @Argument(help: "Analysis prompt")
        var prompt: String
        
        @Option(name: .shortAndLong, help: "Output path for analysis")
        var output: String?
        
        mutating func run() async throws {
            let client = try GeminiClient()
            
            // Check if input is a file URI or local path
            let fileURI: String
            if input.starts(with: "https://generativelanguage.googleapis.com/") {
                fileURI = input
                print("Using provided file URI...")
            } else {
                // Upload file first
                let inputURL = URL(fileURLWithPath: input)
                guard FileManager.default.fileExists(atPath: inputURL.path) else {
                    print("Error: File not found: \(input)")
                    throw ExitCode.failure
                }
                
                print("Uploading \(inputURL.lastPathComponent)...")
                let uploadResponse = try await client.uploadFile(inputURL)
                fileURI = uploadResponse.file.uri
                print("✓ Upload complete")
            }
            
            print("Analyzing video...")
            let analysis = try await client.analyzeVideo(fileURI, prompt: prompt)
            
            if let outputPath = output {
                try analysis.write(toFile: outputPath, atomically: true, encoding: .utf8)
                print("✓ Analysis saved to \(outputPath)")
            } else {
                print("")
                print("=== Video Analysis ===")
                print("")
                print(analysis)
            }
        }
    }
}

// MARK: - Validate Video

extension GeminiCommand {
    struct ValidateVideo: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "validate-video",
            abstract: "Validate a generated video against expected criteria"
        )
        
        @Argument(help: "Path to video file or Gemini file URI")
        var input: String
        
        @Option(name: .long, help: "Expected effects (comma-separated)")
        var effects: String?
        
        @Option(name: .long, help: "Technical checks (comma-separated)")
        var checks: String?
        
        @Option(name: .shortAndLong, help: "Output path for validation report")
        var output: String?
        
        @Flag(name: .long, help: "Output as JSON")
        var json: Bool = false
        
        mutating func run() async throws {
            let client = try GeminiClient()
            
            // Check if input is a file URI or local path
            let fileURI: String
            if input.starts(with: "https://generativelanguage.googleapis.com/") {
                fileURI = input
                print("Using provided file URI...")
            } else {
                // Upload file first
                let inputURL = URL(fileURLWithPath: input)
                guard FileManager.default.fileExists(atPath: inputURL.path) else {
                    print("Error: File not found: \(input)")
                    throw ExitCode.failure
                }
                
                print("Uploading \(inputURL.lastPathComponent)...")
                let uploadResponse = try await client.uploadFile(inputURL)
                fileURI = uploadResponse.file.uri
                print("✓ Upload complete")
            }
            
            let expectedEffects = effects?.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) } ?? []
            let technicalChecks = checks?.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) } ?? []
            
            print("Validating video...")
            let result = try await client.validateVideo(
                fileURI,
                expectedEffects: expectedEffects,
                technicalChecks: technicalChecks
            )
            
            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(result)
                if let jsonString = String(data: data, encoding: .utf8) {
                    if let outputPath = output {
                        try jsonString.write(toFile: outputPath, atomically: true, encoding: .utf8)
                        print("✓ Validation report saved to \(outputPath)")
                    } else {
                        print(jsonString)
                    }
                }
            } else {
                print("")
                print("=== Validation Report ===")
                print("")
                print("Overall: \(result.overallPass ? "✓ PASS" : "✗ FAIL")")
                print("")
                
                for check in result.checks {
                    let status = check.status == "PASS" ? "✓" : "✗"
                    print("\(status) \(check.item)")
                    if let timestamps = check.timestamps, !timestamps.isEmpty {
                        print("   Timestamps: \(timestamps.joined(separator: ", "))")
                    }
                    if let notes = check.notes {
                        print("   \(notes)")
                    }
                    print("")
                }
                
                if let outputPath = output {
                    if let rawResponse = result.rawResponse {
                        try rawResponse.write(toFile: outputPath, atomically: true, encoding: .utf8)
                        print("✓ Full report saved to \(outputPath)")
                    }
                }
            }
        }
    }
}
