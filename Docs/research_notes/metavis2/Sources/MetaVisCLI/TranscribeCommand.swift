// TranscribeCommand.swift
// MetaVisCLI
//
// Sprint 03: Audio transcription command
// Speech-to-text with optional speaker diarization and caption generation

import Foundation
import ArgumentParser
import MetaVisRender
import AVFoundation

struct Transcribe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Transcribe audio from a media file",
        discussion: """
            Extracts audio from a video or audio file and runs speech-to-text
            transcription using Whisper (on-device via WhisperKit).
            
            Examples:
              metavis transcribe interview.mp4
              metavis transcribe --model base --captions srt interview.mp4
              metavis transcribe --language es --diarize meeting.mov
              metavis transcribe --diarize --link-faces video.mp4
            """
    )
    
    // MARK: - Arguments
    
    @Argument(help: "Path to the media file to transcribe")
    var input: String
    
    @Option(name: .shortAndLong, help: "Output path for transcript")
    var output: String?
    
    // MARK: - Whisper Model Options
    
    @Option(name: .shortAndLong, help: "Whisper model: tiny, base, small, medium, large-v3, distil-large-v3")
    var model: String = "base"
    
    @Option(name: .shortAndLong, help: "Language code (e.g., en, es, fr) or 'auto' to detect")
    var language: String = "auto"
    
    @Flag(name: .long, help: "Detect and label speakers (diarization)")
    var diarize: Bool = false
    
    @Option(name: .long, help: "Diarization mode: monologue, interview, podcast, conversation")
    var diarizeMode: String = "conversation"
    
    @Option(name: .long, help: "Maximum number of speakers to detect")
    var maxSpeakers: Int = 6
    
    @Flag(name: .long, help: "Link speakers to detected faces (requires video)")
    var linkFaces: Bool = false
    
    @Option(name: .long, help: "Face detection interval in seconds")
    var faceInterval: Double = 0.5
    
    // MARK: - Output Options
    
    @Option(name: .long, help: "Caption format to generate (srt, vtt, json)")
    var captions: String?
    
    @Flag(name: .long, help: "Include word-level timing in output")
    var wordTiming: Bool = false
    
    @Flag(name: .long, help: "Output raw transcript as JSON")
    var json: Bool = false
    
    // MARK: - Progress Options
    
    @Option(name: .long, help: "Progress display mode: animated, json, quiet, verbose")
    var progress: String = "animated"
    
    // MARK: - Run
    
    mutating func run() async throws {
        let inputURL = URL(fileURLWithPath: input)
        
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            print("Error: File not found: \(inputURL.path)")
            throw ExitCode.failure
        }
        
        // Progress setup
        let progressFormat: ProgressFormat
        switch progress.lowercased() {
        case "json": progressFormat = .json
        case "quiet": progressFormat = .quiet
        case "verbose": progressFormat = .verbose
        default: progressFormat = .animated
        }
        let formatter = ProgressFormatter(format: progressFormat)
        
        let reporter = ProgressReporter(
            name: "Transcription",
            stages: StandardStages.transcribe
        )
        
        // Start progress reporting
        let progressTask = Task {
            for await event in await reporter.events() {
                let output = formatter.format(event)
                if !output.isEmpty {
                    print(output, terminator: progressFormat == .animated ? "" : "\n")
                    fflush(stdout)
                }
            }
        }
        
        // Stage 1: Extract audio if needed
        await reporter.setStage("extract", message: "Preparing audio...")
        
        let audioURL: URL
        let tempAudioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        
        // Check if we need to extract audio from video
        let asset = AVURLAsset(url: inputURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let hasVideoTrack = !videoTracks.isEmpty
        
        if hasVideoTrack {
            await reporter.update(message: "Extracting audio from video...")
            let extractor = AudioExtractor()
            _ = try await extractor.extract(
                from: inputURL,
                to: tempAudioURL,
                format: .wav16kMono  // Optimal for Whisper
            )
            audioURL = tempAudioURL
        } else {
            audioURL = inputURL
        }
        
        defer {
            if hasVideoTrack {
                try? FileManager.default.removeItem(at: tempAudioURL)
            }
        }
        
        // Stage 2: Load Whisper Model
        await reporter.setStage("vad", message: "Loading Whisper model (\(model))...")
        
        let whisperModel = WhisperTranscriptionEngine.WhisperModel(rawValue: model) 
            ?? WhisperTranscriptionEngine.recommendedModel
        let engine = WhisperTranscriptionEngine(model: whisperModel)
        
        try await engine.loadModel { progress in
            Task { @MainActor in
                await reporter.update(
                    message: "Downloading model: \(Int(progress * 100))%",
                    progress: Double(progress) * 0.5
                )
            }
        }
        
        await reporter.update(
            message: "Model loaded: \(whisperModel.description)",
            progress: 1.0
        )
        
        // Stage 3: Transcription
        await reporter.setStage("transcribe", message: "Transcribing audio...")
        
        var transcript = try await engine.transcribe(
            audioURL: audioURL,
            options: TranscriptionOptions(enableWordTiming: wordTiming)
        )
        
        // Stage 4: Speaker Diarization (if requested)
        var diarizationResult: DiarizationResult?
        
        if diarize {
            await reporter.setStage("diarize", message: "Identifying speakers...")
            
            // Select diarization preset based on mode
            let diarizerConfig: SpeakerDiarizer.Config
            switch diarizeMode.lowercased() {
            case "monologue", "single":
                diarizerConfig = .monologue
            case "interview":
                diarizerConfig = .interview
            case "podcast":
                diarizerConfig = .podcast
            case "conversation", "default":
                diarizerConfig = SpeakerDiarizer.Config(
                    minSegmentDuration: 0.3,
                    maxSpeakers: maxSpeakers,
                    clusteringThreshold: 0.65
                )
            default:
                diarizerConfig = .conversation
            }
            
            let diarizer = SpeakerDiarizer(config: diarizerConfig)
            
            // Run diarization on the audio
            diarizationResult = try await diarizer.diarize(url: audioURL)
            
            // Merge diarization with transcript segments
            transcript = mergeDiarization(transcript: transcript, diarization: diarizationResult!)
            
            await reporter.update(
                message: "Identified \(diarizationResult!.speakers.count) speakers",
                progress: 1.0
            )
        }
        
        // Stage 4.5: Face-Voice Linking (if requested and we have video + diarization)
        var faceLinks: FaceVoiceLinkResult?
        
        if linkFaces && hasVideoTrack && diarizationResult != nil {
            await reporter.setStage("face-link", message: "Detecting faces and linking to speakers...")
            
            // Detect faces throughout the video
            let faceObservations = try await detectFacesInVideo(
                url: inputURL,
                interval: faceInterval,
                reporter: reporter
            )
            
            // Count unique faces detected
            let uniqueFaces = Set(faceObservations.flatMap { $0.faces.map { $0.id } })
            
            if !faceObservations.isEmpty {
                await reporter.update(
                    message: "Found \(uniqueFaces.count) unique face(s) in \(faceObservations.count) frames",
                    progress: 0.7
                )
                
                // Link speakers to faces with lenient settings for better matching
                let linker = FaceVoiceLinker(config: .lenient)
                let videoDuration = try await getVideoDuration(url: inputURL)
                
                faceLinks = await linker.linkSpeakersToFaces(
                    diarization: diarizationResult!,
                    faceObservations: faceObservations,
                    videoDuration: videoDuration
                )
                
                // Update transcript with face IDs
                if let links = faceLinks {
                    transcript = addFaceLinksToTranscript(transcript: transcript, faceLinks: links)
                    
                    let matchedCount = links.links.filter { $0.isMatched }.count
                    await reporter.update(
                        message: "Linked \(matchedCount) of \(diarizationResult!.speakers.count) speakers to faces",
                        progress: 1.0
                    )
                }
            } else {
                await reporter.update(message: "No faces detected in video", progress: 1.0)
            }
        }
        
        // Stage 5: Generate Captions
        await reporter.setStage("caption", message: "Generating output...")
        
        // Determine output format and path
        let outputPath: String
        let captionFormat: CaptionFormat?
        
        if let format = captions {
            switch format.lowercased() {
            case "vtt": captionFormat = .vtt
            case "json": captionFormat = .json
            default: captionFormat = .srt
            }
            outputPath = output ?? inputURL.deletingPathExtension().appendingPathExtension(format).path
        } else if json {
            captionFormat = nil
            outputPath = output ?? inputURL.deletingPathExtension().appendingPathExtension("json").path
        } else {
            captionFormat = nil
            outputPath = output ?? ""
        }
        
        // Write output
        if let format = captionFormat {
            let generator = CaptionGenerator()
            try generator.generate(
                from: transcript,
                format: format,
                to: URL(fileURLWithPath: outputPath)
            )
            
            if progressFormat != .quiet {
                print("\n\nCaptions written to \(outputPath)")
            }
        } else if json || output != nil {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(transcript)
            
            if output != nil {
                try data.write(to: URL(fileURLWithPath: outputPath))
                if progressFormat != .quiet {
                    print("\n\nTranscript written to \(outputPath)")
                }
            } else if let jsonString = String(data: data, encoding: .utf8) {
                print("\n\n\(jsonString)")
            }
        } else {
            // Print transcript to stdout
            await reporter.complete(message: "Transcription complete")
            progressTask.cancel()
            
            print("\n\nTranscript:")
            print("===========")
            for segment in transcript.segments {
                let timeStr = formatTime(segment.start)
                let speakerPrefix = segment.speakerId != nil ? "[\(segment.speakerId!)] " : ""
                print("\(timeStr)  \(speakerPrefix)\(segment.text)")
            }
            
            print("\nDuration: \(formatTime(transcript.duration))")
            print("Word count: \(transcript.wordCount)")
            
            return
        }
        
        await reporter.complete(message: "Transcription complete")
        progressTask.cancel()
        
        // Print summary
        if progressFormat != .quiet {
            print("\nTranscription Summary:")
            print("  Duration: \(formatTime(transcript.duration))")
            print("  Segments: \(transcript.segments.count)")
            print("  Words: \(transcript.wordCount)")
            if diarize {
                let speakerCount = transcript.speakerIds.count
                print("  Speakers: \(speakerCount)")
            }
            if let links = faceLinks {
                let matchedCount = links.links.filter { $0.isMatched }.count
                print("  Faces detected: \(links.links.count)")
                print("  Speakers linked to faces: \(matchedCount)")
                for link in links.links where link.isMatched {
                    print("    \(link.speakerId) → \(link.faceId!) (confidence: \(String(format: "%.0f%%", link.confidence * 100)))")
                }
            }
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%03d", hours, minutes, secs, ms)
        } else {
            return String(format: "%02d:%02d.%03d", minutes, secs, ms)
        }
    }
}

// MARK: - Diarization Merge Helper

/// Merge speaker diarization results with transcript segments
private func mergeDiarization(transcript: Transcript, diarization: DiarizationResult) -> Transcript {
    var updatedSegments: [TranscriptSegment] = []
    
    for segment in transcript.segments {
        // Find the speaker segment that overlaps most with this transcript segment
        let midpoint = (segment.start + segment.end) / 2
        
        let matchingSpeaker = diarization.segments.first { speakerSeg in
            midpoint >= speakerSeg.start && midpoint < speakerSeg.end
        }
        
        let speakerId = matchingSpeaker?.speakerId ?? "SPEAKER_00"
        
        let newSegment = TranscriptSegment(
            id: segment.id,
            start: segment.start,
            end: segment.end,
            text: segment.text,
            confidence: segment.confidence,
            speakerId: speakerId
        )
        updatedSegments.append(newSegment)
    }
    
    return Transcript(
        id: transcript.id,
        text: transcript.text,
        language: transcript.language,
        segments: updatedSegments,
        words: transcript.words,
        confidence: transcript.confidence,
        engine: transcript.engine,
        duration: transcript.duration,
        createdAt: transcript.createdAt
    )
}

// MARK: - Face Detection and Linking Helpers

import Vision
import CoreImage

/// Detect faces at regular intervals throughout a video
private func detectFacesInVideo(
    url: URL,
    interval: Double,
    reporter: ProgressReporter
) async throws -> [TimedFaceObservation] {
    let asset = AVURLAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    
    // Get video duration
    let duration = try await asset.load(.duration).seconds
    
    var observations: [TimedFaceObservation] = []
    var currentTime: Double = 0
    var faceTracker: [String: CGRect] = [:]  // Track faces by position
    var nextFaceId = 0
    
    while currentTime < duration {
        let cmTime = CMTime(seconds: currentTime, preferredTimescale: 600)
        
        do {
            let (image, _) = try await generator.image(at: cmTime)
            
            // Run face detection
            let request = VNDetectFaceLandmarksRequest()
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])
            
            var faces: [FaceInfo] = []
            
            for observation in request.results ?? [] {
                // Try to match to existing tracked face
                let bounds = observation.boundingBox
                var matchedId: String?
                
                for (id, prevBounds) in faceTracker {
                    // Check if this face is close to a previously tracked face
                    let distance = hypot(bounds.midX - prevBounds.midX, bounds.midY - prevBounds.midY)
                    if distance < 0.15 {  // Within 15% of frame
                        matchedId = id
                        break
                    }
                }
                
                let faceId: String
                if let matched = matchedId {
                    faceId = matched
                } else {
                    faceId = "FACE_\(String(format: "%02d", nextFaceId))"
                    nextFaceId += 1
                }
                
                faceTracker[faceId] = bounds
                
                faces.append(FaceInfo(
                    id: faceId,
                    bounds: bounds,
                    confidence: observation.confidence
                ))
            }
            
            if !faces.isEmpty {
                observations.append(TimedFaceObservation(
                    timestamp: currentTime,
                    faces: faces
                ))
            }
            
            // Update progress
            await reporter.update(
                message: "Detecting faces... \(Int(currentTime / duration * 100))%",
                progress: currentTime / duration * 0.5  // 50% of stage
            )
            
        } catch {
            // Skip frames that fail
        }
        
        currentTime += interval
    }
    
    return observations
}

/// Get video duration
private func getVideoDuration(url: URL) async throws -> Double {
    let asset = AVURLAsset(url: url)
    return try await asset.load(.duration).seconds
}

/// Add face link information to transcript segments
private func addFaceLinksToTranscript(transcript: Transcript, faceLinks: FaceVoiceLinkResult) -> Transcript {
    var updatedSegments: [TranscriptSegment] = []
    
    for segment in transcript.segments {
        var newSpeakerId = segment.speakerId
        
        // Find face link for this speaker
        if let speakerId = segment.speakerId,
           let link = faceLinks.link(for: speakerId),
           let faceId = link.faceId {
            // Append face ID to speaker ID
            newSpeakerId = "\(speakerId) (\(faceId))"
        }
        
        let newSegment = TranscriptSegment(
            id: segment.id,
            start: segment.start,
            end: segment.end,
            text: segment.text,
            confidence: segment.confidence,
            speakerId: newSpeakerId
        )
        updatedSegments.append(newSegment)
    }
    
    return Transcript(
        id: transcript.id,
        text: transcript.text,
        language: transcript.language,
        segments: updatedSegments,
        words: transcript.words,
        confidence: transcript.confidence,
        engine: transcript.engine,
        duration: transcript.duration,
        createdAt: transcript.createdAt
    )
}
