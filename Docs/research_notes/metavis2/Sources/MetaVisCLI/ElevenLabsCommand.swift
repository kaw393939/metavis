// ElevenLabsCommand.swift
// MetaVisCLI
//
// CLI commands for ElevenLabs API integration

import ArgumentParser
import Foundation
import MetaVisRender

struct ElevenLabsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "elevenlabs",
        abstract: "ElevenLabs voice generation and sound effects",
        subcommands: [
            ListVoices.self,
            GenerateSpeech.self,
            GenerateSFX.self,
            GenerateSpatialTest.self
        ]
    )
}

// MARK: - List Voices

extension ElevenLabsCommand {
    struct ListVoices: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "voices",
            abstract: "List available ElevenLabs voices"
        )
        
        @Flag(name: .long, help: "Output as JSON")
        var json: Bool = false
        
        mutating func run() async throws {
            let client = try ElevenLabsClient()
            let voices = try await client.listVoices()
            
            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(voices)
                if let jsonString = String(data: data, encoding: .utf8) {
                    print(jsonString)
                }
            } else {
                print("")
                print("Available Voices (\(voices.count)):")
                print("")
                for voice in voices {
                    print("• \(voice.name)")
                    print("  ID: \(voice.voiceId)")
                    if let category = voice.category {
                        print("  Category: \(category)")
                    }
                    if let description = voice.description {
                        print("  Description: \(description)")
                    }
                    print("")
                }
            }
        }
    }
}

// MARK: - Generate Speech

extension ElevenLabsCommand {
    struct GenerateSpeech: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "speak",
            abstract: "Generate speech from text"
        )
        
        @Argument(help: "Text to convert to speech")
        var text: String
        
        @Option(name: .shortAndLong, help: "Output audio file path")
        var output: String
        
        @Option(name: .long, help: "Voice ID (use 'metavis elevenlabs voices' to list)")
        var voice: String = "21m00Tcm4TlvDq8ikWAM"  // Rachel
        
        @Option(name: .long, help: "Model ID")
        var model: String = "eleven_turbo_v2_5"
        
        mutating func run() async throws {
            let client = try ElevenLabsClient()
            let outputURL = URL(fileURLWithPath: output)
            
            print("Generating speech...")
            let audioURL = try await client.generateSpeech(
                text: text,
                voiceId: voice,
                modelId: model,
                outputPath: outputURL
            )
            
            print("✓ Speech generated: \(audioURL.path)")
        }
    }
}

// MARK: - Generate Sound Effect

extension ElevenLabsCommand {
    struct GenerateSFX: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "sfx",
            abstract: "Generate sound effect from description"
        )
        
        @Argument(help: "Sound effect description (e.g., 'door creaking')")
        var description: String
        
        @Option(name: .shortAndLong, help: "Output audio file path")
        var output: String
        
        @Option(name: .long, help: "Duration in seconds")
        var duration: Double?
        
        @Option(name: .long, help: "Prompt influence (0.0-1.0)")
        var influence: Double = 0.3
        
        mutating func run() async throws {
            let client = try ElevenLabsClient()
            let outputURL = URL(fileURLWithPath: output)
            
            print("Generating sound effect...")
            let audioURL = try await client.generateSoundEffect(
                description: description,
                durationSeconds: duration,
                promptInfluence: influence,
                outputPath: outputURL
            )
            
            print("✓ Sound effect generated: \(audioURL.path)")
        }
    }
}

// MARK: - Generate Spatial Audio Test

extension ElevenLabsCommand {
    struct GenerateSpatialTest: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "spatial-test",
            abstract: "Generate audio clips for spatial/positional audio testing"
        )
        
        @Option(name: .shortAndLong, help: "Output directory for test audio clips")
        var output: String
        
        @Flag(name: .long, help: "Use preset positions (center, left, right, etc.)")
        var usePresets: Bool = true
        
        mutating func run() async throws {
            let client = try ElevenLabsClient()
            let outputDir = URL(fileURLWithPath: output)
            
            // Create output directory
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
            
            let positions = usePresets ? ElevenLabsSpatialPosition.presets : []
            
            print("Generating \(positions.count) spatial audio test clips...")
            let audioURLs = try await client.generatePositionalAudioTest(
                positions: positions,
                outputDirectory: outputDir
            )
            
            print("")
            print("✓ Generated \(audioURLs.count) test clips:")
            for url in audioURLs {
                print("  • \(url.lastPathComponent)")
            }
            print("")
            print("Output directory: \(outputDir.path)")
        }
    }
}
