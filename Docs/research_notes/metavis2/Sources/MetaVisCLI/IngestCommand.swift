// IngestCommand.swift
// MetaVisCLI
//
// Sprint 03: Footage ingestion command
// Scans directories, probes media, extracts metadata

import Foundation
import ArgumentParser
import MetaVisRender

struct Ingest: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Ingest media files and extract metadata",
        discussion: """
            Scans a directory for media files, probes each file to extract
            technical metadata, and optionally runs transcription.
            
            Examples:
              metavis ingest ~/Videos --recursive
              metavis ingest ./footage --transcribe --captions srt
              metavis ingest . --output index.json --progress animated
            """
    )
    
    // MARK: - Arguments
    
    @Argument(help: "Path to directory or file to ingest")
    var input: String
    
    @Option(name: .shortAndLong, help: "Output path for ingestion results JSON")
    var output: String?
    
    // MARK: - Scanning Options
    
    @Flag(name: .shortAndLong, help: "Recursively scan subdirectories")
    var recursive: Bool = false
    
    @Option(name: .long, help: "File extensions to include (comma-separated)")
    var extensions: String = "mov,mp4,m4v,mxf,avi,mkv,wav,mp3,aac,pdf"
    
    @Option(name: .long, help: "Maximum files to process (0 = unlimited)")
    var maxFiles: Int = 0
    
    // MARK: - Processing Options
    
    @Flag(name: .long, help: "Run speech-to-text transcription on audio")
    var transcribe: Bool = false
    
    @Option(name: .long, help: "Caption format to generate (srt, vtt, json)")
    var captions: String?
    
    @Option(name: .long, help: "Language code for transcription (e.g., en-US)")
    var language: String = "en-US"
    
    @Flag(name: .long, help: "Detect and label speakers")
    var diarize: Bool = false
    
    @Flag(name: .long, help: "Extract thumbnails from video files")
    var thumbnails: Bool = false
    
    @Option(name: .long, help: "Thumbnail interval in seconds")
    var thumbnailInterval: Double = 10.0
    
    // MARK: - Progress Options
    
    @Option(name: .long, help: "Progress display mode: animated, json, quiet, verbose")
    var progress: String = "animated"
    
    // MARK: - Run
    
    mutating func run() async throws {
        let inputURL = URL(fileURLWithPath: input)
        let fileManager = FileManager.default
        
        // Determine progress format
        let progressFormat: ProgressFormat
        switch progress.lowercased() {
        case "json": progressFormat = .json
        case "quiet": progressFormat = .quiet
        case "verbose": progressFormat = .verbose
        default: progressFormat = .animated
        }
        let formatter = ProgressFormatter(format: progressFormat)
        
        // Create progress reporter
        let reporter = ProgressReporter(
            name: "Ingestion",
            stages: StandardStages.ingest
        )
        
        // Collect files
        var files: [URL] = []
        let allowedExtensions = Set(extensions.split(separator: ",").map { String($0).lowercased() })
        
        if progressFormat != .quiet {
            print("Scanning for media files...")
        }
        
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: inputURL.path, isDirectory: &isDirectory) else {
            print("Error: Path does not exist: \(inputURL.path)")
            throw ExitCode.failure
        }
        
        if isDirectory.boolValue {
            let enumerator: FileManager.DirectoryEnumerator?
            if recursive {
                enumerator = fileManager.enumerator(at: inputURL, includingPropertiesForKeys: [.isRegularFileKey])
            } else {
                let contents = try fileManager.contentsOfDirectory(at: inputURL, includingPropertiesForKeys: [.isRegularFileKey])
                for url in contents {
                    let ext = url.pathExtension.lowercased()
                    if allowedExtensions.contains(ext) {
                        files.append(url)
                    }
                }
                enumerator = nil
            }
            
            if let enumerator = enumerator {
                while let url = enumerator.nextObject() as? URL {
                    let ext = url.pathExtension.lowercased()
                    if allowedExtensions.contains(ext) {
                        files.append(url)
                    }
                    
                    if maxFiles > 0 && files.count >= maxFiles {
                        break
                    }
                }
            }
        } else {
            files.append(inputURL)
        }
        
        if files.isEmpty {
            print("No media files found.")
            throw ExitCode.failure
        }
        
        if progressFormat != .quiet {
            print("Found \(files.count) files to process\n")
        }
        
        // Set up progress reporting
        let progressTask = Task {
            for await event in await reporter.events() {
                let output = formatter.format(event)
                if !output.isEmpty {
                    print(output, terminator: progressFormat == .animated ? "" : "\n")
                    fflush(stdout)
                }
            }
        }
        
        // Start probing stage
        await reporter.setTotal(items: files.count)
        await reporter.setStage("probe")
        
        // Probe each file
        var profiles: [EnhancedMediaProfile] = []
        var transcripts: [String: Transcript] = [:]
        
        for (index, file) in files.enumerated() {
            await reporter.update(
                message: "Probing \(file.lastPathComponent)",
                itemsCompleted: index
            )
            
            do {
                let profile = try await EnhancedMediaProbe.probe(file)
                profiles.append(profile)
                
                // Transcribe if requested and file has audio
                if transcribe && profile.hasAudio {
                    await reporter.update(
                        message: "Transcribing \(file.lastPathComponent)",
                        itemsCompleted: index
                    )
                    
                    let engine = TranscriptionEngine(language: language)
                    let transcript = try await engine.transcribe(audioURL: file)
                    transcripts[file.path] = transcript
                    
                    // Generate captions if requested
                    if let captionFormat = captions {
                        let format: CaptionFormat
                        switch captionFormat.lowercased() {
                        case "vtt": format = .vtt
                        case "json": format = .json
                        default: format = .srt
                        }
                        
                        let generator = CaptionGenerator()
                        let captionURL = file.deletingPathExtension().appendingPathExtension(format.rawValue)
                        try generator.generate(
                            from: transcript,
                            format: format,
                            to: captionURL
                        )
                    }
                }
            } catch {
                if progressFormat != .quiet {
                    print("\nWarning: Failed to probe \(file.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
        
        await reporter.complete(message: "Ingestion complete")
        progressTask.cancel()
        
        // Build results
        let results = IngestionResults(
            timestamp: Date(),
            filesProcessed: profiles.count,
            profiles: profiles,
            transcripts: transcripts
        )
        
        // Output results
        if let outputPath = output {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(results)
            try data.write(to: URL(fileURLWithPath: outputPath))
            
            if progressFormat != .quiet {
                print("\nResults written to \(outputPath)")
            }
        } else if progressFormat != .quiet {
            print("\n\nIngestion Summary:")
            print("  Files processed: \(profiles.count)")
            print("  Video files: \(profiles.filter { $0.hasVideo }.count)")
            print("  Audio files: \(profiles.filter { $0.hasAudio && !$0.hasVideo }.count)")
            if !transcripts.isEmpty {
                print("  Files transcribed: \(transcripts.count)")
            }
        }
    }
}

// MARK: - Ingestion Results

struct IngestionResults: Codable {
    let timestamp: Date
    let filesProcessed: Int
    let profiles: [EnhancedMediaProfile]
    let transcripts: [String: Transcript]
}
